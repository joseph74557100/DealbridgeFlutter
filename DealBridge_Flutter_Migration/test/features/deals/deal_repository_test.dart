import 'package:dealbridge_flutter/core/constants/app_constants.dart';
import 'package:dealbridge_flutter/core/utils/app_exception.dart';
import 'package:dealbridge_flutter/features/deals/data/deal_repository.dart';
import 'package:dealbridge_flutter/features/deals/models/deal.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/test_firebase.dart';

void main() {
  setUpAll(() async {
    await installTestFirebase();
  });

  late FakeFirebaseFirestore firestore;
  late DealRepository repository;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    repository = DealRepository(
      firestore: firestore,
      auth: FirebaseAuth.instance,
    );
  });

  Future<void> seedBusiness(String id, String ownerId) async {
    await firestore.collection(FirestoreCollections.businesses).doc(id).set(
      <String, dynamic>{'name': 'Acme', 'ownerId': ownerId},
    );
  }

  Future<void> seedDeal({
    String id = 'deal-1',
    String senderId = 'someone-else',
    String status = DealStatus.pending,
    List<String>? participantIds,
  }) async {
    await firestore.collection(FirestoreCollections.deals).doc(id).set(
      <String, dynamic>{
        'title': 'Supply agreement',
        'businessId': 'business-1',
        'businessName': 'Acme',
        'senderId': senderId,
        'senderName': 'Ada',
        'status': status,
        'participantIds': participantIds ?? <String>[senderId, testUid],
        'timestamp': 1767225600000,
        'lastActivityAt': 1767225600000,
        'currentStep': DealStep.reviewTerms,
        'senderConfirmationStatus': ConfirmationStatus.reviewTerms,
        'recipientConfirmationStatus': ConfirmationStatus.reviewTerms,
      },
    );
  }

  group('createDeal', () {
    test('writes a pending deal with the owner as participant', () async {
      await seedBusiness('business-1', 'owner-1');

      final id = await repository.createDeal(
        businessId: 'business-1',
        businessName: 'Acme',
        title: '  Supply agreement  ',
        description: 'Monthly supply',
        value: 'R10,000',
        senderName: 'Ada',
      );

      final doc = await firestore
          .collection(FirestoreCollections.deals)
          .doc(id)
          .get();
      final data = doc.data()!;

      expect(data['title'], 'Supply agreement');
      expect(data['status'], DealStatus.pending);
      expect(data['senderId'], testUid);
      expect(data['participantIds'], <String>[testUid, 'owner-1']);
      expect(data['currentStep'], DealStep.reviewTerms);
      expect(data['terms'], isNotEmpty);
      expect(data['expiresAt'], greaterThan(0));
    });

    test('rejects a deal without a title', () {
      expect(
        () => repository.createDeal(
          businessId: 'business-1',
          businessName: 'Acme',
          title: '  ',
          description: '',
          value: '',
          senderName: 'Ada',
        ),
        throwsA(isA<AppException>()),
      );
    });

    test('rejects a deal without a business', () {
      expect(
        () => repository.createDeal(
          businessId: '',
          businessName: 'Acme',
          title: 'Supply agreement',
          description: '',
          value: '',
          senderName: 'Ada',
        ),
        throwsA(isA<AppException>()),
      );
    });

    test('rejects a deal to a business owned by the sender', () async {
      await seedBusiness('business-1', testUid);

      expect(
        () => repository.createDeal(
          businessId: 'business-1',
          businessName: 'Acme',
          title: 'Supply agreement',
          description: '',
          value: '',
          senderName: 'Ada',
        ),
        throwsA(isA<AppException>()),
      );
    });

    test('rejects a deal to a business that no longer exists', () async {
      expect(
        () => repository.createDeal(
          businessId: 'missing',
          businessName: 'Acme',
          title: 'Supply agreement',
          description: '',
          value: '',
          senderName: 'Ada',
        ),
        throwsA(isA<AppException>()),
      );
    });
  });

  group('acceptDeal', () {
    test('lets the recipient accept a pending deal', () async {
      await seedDeal();
      final deal = (await repository.fetchDeal('deal-1'))!;

      await repository.acceptDeal(deal);

      final updated = (await repository.fetchDeal('deal-1'))!;
      expect(updated.status, DealStatus.accepted);
      expect(updated.currentStep, DealStep.agreed);
    });

    test('rejects acceptance by the sender', () async {
      await seedDeal(senderId: testUid);
      final deal = (await repository.fetchDeal('deal-1'))!;

      expect(
        () => repository.acceptDeal(deal),
        throwsA(isA<AppException>()),
      );
    });

    test('rejects acceptance of a deal that is not pending', () async {
      await seedDeal(status: DealStatus.accepted);
      final deal = (await repository.fetchDeal('deal-1'))!;

      expect(
        () => repository.acceptDeal(deal),
        throwsA(isA<AppException>()),
      );
    });
  });

  group('declineDeal', () {
    test('lets the recipient decline a pending deal', () async {
      await seedDeal();
      final deal = (await repository.fetchDeal('deal-1'))!;

      await repository.declineDeal(deal);

      final updated = (await repository.fetchDeal('deal-1'))!;
      expect(updated.status, DealStatus.declined);
    });

    test('rejects a decline by a non participant', () async {
      await seedDeal(participantIds: <String>['a', 'b']);
      final deal = (await repository.fetchDeal('deal-1'))!;

      expect(
        () => repository.declineDeal(deal),
        throwsA(isA<AppException>()),
      );
    });
  });

  group('setConfirmationStatus', () {
    test('moves the recipient from review to agreed', () async {
      await seedDeal();
      final deal = (await repository.fetchDeal('deal-1'))!;

      await repository.setConfirmationStatus(
        deal,
        ConfirmationStatus.agreed,
      );

      final updated = (await repository.fetchDeal('deal-1'))!;
      expect(updated.recipientConfirmationStatus, ConfirmationStatus.agreed);
      expect(updated.recipientAgreedAt, greaterThan(0));
      expect(updated.senderConfirmationStatus,
          ConfirmationStatus.reviewTerms);
    });

    test('moves the recipient from agreed to confirmed', () async {
      await seedDeal();
      var deal = (await repository.fetchDeal('deal-1'))!;
      await repository.setConfirmationStatus(deal, ConfirmationStatus.agreed);
      deal = (await repository.fetchDeal('deal-1'))!;

      await repository.setConfirmationStatus(deal, ConfirmationStatus.confirmed);

      final updated = (await repository.fetchDeal('deal-1'))!;
      expect(updated.recipientConfirmationStatus, ConfirmationStatus.confirmed);
      expect(updated.recipientConfirmedAt, greaterThan(0));
    });

    test('rejects an illegal transition', () async {
      await seedDeal();
      final deal = (await repository.fetchDeal('deal-1'))!;

      expect(
        () => repository.setConfirmationStatus(deal, 'NONSENSE'),
        throwsA(isA<AppException>()),
      );
    });

    test('rejects confirming a deal for a non participant', () async {
      await seedDeal(participantIds: <String>['a', 'b']);
      final deal = (await repository.fetchDeal('deal-1'))!;

      expect(
        () => repository.setConfirmationStatus(deal, ConfirmationStatus.agreed),
        throwsA(isA<AppException>()),
      );
    });
  });

  group('cancelDeal', () {
    test('rejects an empty deal id before calling the backend', () {
      expect(() => repository.cancelDeal(''), throwsA(isA<AppException>()));
    });
  });

  group('watchMyDeals', () {
    test('only returns deals the user participates in', () async {
      await seedDeal(id: 'mine');
      await seedDeal(id: 'theirs', participantIds: <String>['a', 'b']);

      final deals = await repository.watchMyDeals().first;

      expect(deals.map((deal) => deal.id), <String>['mine']);
    });

    test('hides cancelled deals', () async {
      await seedDeal(id: 'cancelled', status: DealStatus.cancelled);

      final deals = await repository.watchMyDeals().first;

      expect(deals, isEmpty);
    });

    test('sorts by the most recent activity', () async {
      await seedDeal(id: 'old');
      await firestore.collection(FirestoreCollections.deals).doc('new').set(
        <String, dynamic>{
          'title': 'Newer',
          'senderId': 'someone-else',
          'status': DealStatus.pending,
          'participantIds': <String>['someone-else', testUid],
          'timestamp': 1767225600000,
          'lastActivityAt': 1767312000000,
        },
      );

      final deals = await repository.watchMyDeals().first;

      expect(deals.map((deal) => deal.id), <String>['new', 'old']);
    });
  });

  group('hidden deals', () {
    test('hides and restores a deal', () async {
      await seedDeal();

      await repository.hideDeal('deal-1');
      var hidden = await repository.watchHiddenDealIds().first;
      expect(hidden, contains('deal-1'));

      await repository.unhideDeal('deal-1');
      hidden = await repository.watchHiddenDealIds().first;
      expect(hidden, isNot(contains('deal-1')));
    });
  });

  group('Deal model mapping', () {
    test('reads the stored document back', () async {
      await seedDeal();

      final deal = (await repository.fetchDeal('deal-1'))!;

      expect(deal, isA<Deal>());
      expect(deal.title, 'Supply agreement');
      expect(deal.businessName, 'Acme');
      expect(deal.participantIds, <String>['someone-else', testUid]);
    });

    test('returns null for a missing deal', () async {
      expect(await repository.fetchDeal('missing'), isNull);
    });
  });
}
