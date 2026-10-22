import 'package:dealbridge_flutter/core/constants/app_constants.dart';
import 'package:dealbridge_flutter/features/agreements/data/agreement_repository.dart';
import 'package:dealbridge_flutter/features/agreements/models/agreement.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/test_firebase.dart';

void main() {
  setUpAll(() async {
    await installTestFirebase();
  });

  late FakeFirebaseFirestore firestore;
  late AgreementRepository repository;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    repository = AgreementRepository(
      firestore: firestore,
      auth: FirebaseAuth.instance,
    );
  });

  Future<void> seedAgreement({
    String id = 'agreement-1',
    String dealId = 'deal-1',
    List<String>? participantIds,
    int createdAt = 1767225600000,
    String status = AgreementStatus.pendingSignature,
  }) async {
    await firestore.collection(FirestoreCollections.agreements).doc(id).set(
      <String, dynamic>{
        'agreementId': id,
        'agreementNumber': 'DB-0001',
        'dealId': dealId,
        'title': 'Supply agreement',
        'businessOneName': 'Acme',
        'businessTwoName': 'Zeta',
        'participantIds': participantIds ?? <String>['someone-else', testUid],
        'createdAt': createdAt,
        'status': status,
        'notes': '',
      },
    );
  }

  group('watchMyAgreements', () {
    test('only returns agreements the user participates in', () async {
      await seedAgreement(id: 'mine');
      await seedAgreement(
        id: 'theirs',
        participantIds: <String>['a', 'b'],
      );

      final agreements = await repository.watchMyAgreements().first;

      expect(agreements.map((a) => a.id), <String>['mine']);
    });

    test('sorts the newest agreement first', () async {
      await seedAgreement(id: 'old', createdAt: 1000);
      await seedAgreement(id: 'new', createdAt: 2000);

      final agreements = await repository.watchMyAgreements().first;

      expect(agreements.map((a) => a.id), <String>['new', 'old']);
    });
  });

  group('fetchAgreement', () {
    test('reads the stored document', () async {
      await seedAgreement();

      final agreement = await repository.fetchAgreement('agreement-1');

      expect(agreement, isNotNull);
      expect(agreement!.agreementNumber, 'DB-0001');
      expect(agreement.businessOneName, 'Acme');
      expect(agreement.businessTwoName, 'Zeta');
    });

    test('returns null for an unknown id', () async {
      expect(await repository.fetchAgreement('missing'), isNull);
      expect(await repository.fetchAgreement(''), isNull);
    });
  });

  group('findForDeal', () {
    test('finds the agreement stored under the deal id', () async {
      await seedAgreement(id: 'deal-1');

      final agreement = await repository.findForDeal('deal-1');

      expect(agreement?.id, 'deal-1');
    });

    test('falls back to the dealId field', () async {
      await seedAgreement(id: 'agreement-9', dealId: 'deal-7');

      final agreement = await repository.findForDeal('deal-7');

      expect(agreement?.id, 'agreement-9');
    });

    test('returns null when no agreement exists', () async {
      expect(await repository.findForDeal('deal-7'), isNull);
    });
  });

  group('updateMetadata', () {
    test('writes only the whitelisted keys', () async {
      await seedAgreement();

      await repository.updateMetadata(
        agreementId: 'agreement-1',
        notes: 'Signed on site',
        status: AgreementStatus.archived,
      );

      final data = (await firestore
              .collection(FirestoreCollections.agreements)
              .doc('agreement-1')
              .get())
          .data()!;

      expect(data['notes'], 'Signed on site');
      expect(data['status'], AgreementStatus.archived);
      expect(data['updatedBy'], testUid);
      expect(data['title'], 'Supply agreement');
      expect(data.keys, isNot(contains('signatures')));
    });

    test('does nothing when no field is provided', () async {
      await seedAgreement();

      await repository.updateMetadata(agreementId: 'agreement-1');

      final data = (await firestore
              .collection(FirestoreCollections.agreements)
              .doc('agreement-1')
              .get())
          .data()!;

      expect(data.containsKey('updatedBy'), isFalse);
    });
  });

  group('archive and restore', () {
    test('archives an agreement', () async {
      await seedAgreement();

      await repository.archive('agreement-1');

      final agreement = await repository.fetchAgreement('agreement-1');
      expect(agreement?.status, AgreementStatus.archived);
    });

    test('restores an archived agreement', () async {
      await seedAgreement(status: AgreementStatus.archived);

      await repository.restore('agreement-1');

      final agreement = await repository.fetchAgreement('agreement-1');
      expect(agreement?.status, AgreementStatus.pendingSignature);
    });
  });

  group('delete', () {
    test('removes the document', () async {
      await seedAgreement();

      await repository.delete('agreement-1');

      final doc = await firestore
          .collection(FirestoreCollections.agreements)
          .doc('agreement-1')
          .get();
      expect(doc.exists, isFalse);
    });
  });
}
