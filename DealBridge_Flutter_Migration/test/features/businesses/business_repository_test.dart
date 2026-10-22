import 'package:dealbridge_flutter/core/constants/app_constants.dart';
import 'package:dealbridge_flutter/core/utils/app_exception.dart';
import 'package:dealbridge_flutter/features/businesses/data/business_repository.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/test_firebase.dart';

void main() {
  setUpAll(() async {
    await installTestFirebase();
  });

  late FakeFirebaseFirestore firestore;
  late BusinessRepository repository;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    repository = BusinessRepository(
      firestore: firestore,
      auth: FirebaseAuth.instance,
    );
  });

  group('createBusiness', () {
    test('stores the business with the owner and safe defaults', () async {
      final id = await repository.createBusiness(
        name: '  Acme  ',
        category: 'Retail',
        city: 'Cape Town',
        description: 'Hardware',
        phone: '+27 11 555 1234',
        email: 'hello@acme.co',
        website: 'https://acme.co',
      );

      final doc = await firestore
          .collection(FirestoreCollections.businesses)
          .doc(id)
          .get();
      final data = doc.data()!;

      expect(data['name'], 'Acme');
      expect(data['ownerId'], testUid);
      expect(data['trustScore'], 50);
      expect(data['verificationLevel'], 0);
      expect(data['verified'], isFalse);
      expect(data['promoted'], isFalse);
    });

    test('rejects a business without a name', () {
      expect(
        () => repository.createBusiness(
          name: '   ',
          category: 'Retail',
          city: 'Cape Town',
          description: '',
          phone: '',
          email: '',
          website: '',
        ),
        throwsA(isA<AppException>()),
      );
    });
  });

  group('updateBusiness', () {
    test('only writes the editable fields', () async {
      await firestore.collection(FirestoreCollections.businesses).doc('b1').set(
        <String, dynamic>{
          'name': 'Acme',
          'ownerId': testUid,
          'rating': 4.5,
          'trustScore': 80,
        },
      );

      final business = await repository.fetchBusiness('b1');
      await repository.updateBusiness(
        business!.copyWith(name: 'Acme Trading'),
      );

      final data = (await firestore
              .collection(FirestoreCollections.businesses)
              .doc('b1')
              .get())
          .data()!;

      expect(data['name'], 'Acme Trading');
      expect(data['rating'], 4.5);
      expect(data['trustScore'], 80);
    });
  });

  group('deleteBusiness', () {
    test('removes the document', () async {
      await firestore
          .collection(FirestoreCollections.businesses)
          .doc('b1')
          .set(<String, dynamic>{'name': 'Acme'});

      await repository.deleteBusiness('b1');

      final doc = await firestore
          .collection(FirestoreCollections.businesses)
          .doc('b1')
          .get();
      expect(doc.exists, isFalse);
    });
  });

  group('watchDirectory', () {
    test('returns the businesses ordered by name', () async {
      await firestore.collection(FirestoreCollections.businesses).doc('b2').set(
        <String, dynamic>{'name': 'Zeta'},
      );
      await firestore.collection(FirestoreCollections.businesses).doc('b1').set(
        <String, dynamic>{'name': 'Acme'},
      );

      final businesses = await repository.watchDirectory().first;

      expect(businesses.map((b) => b.name), <String>['Acme', 'Zeta']);
    });
  });

  group('watchMyBusinesses', () {
    test('only returns the businesses owned by the user', () async {
      await firestore.collection(FirestoreCollections.businesses).doc('mine').set(
        <String, dynamic>{'name': 'Acme', 'ownerId': testUid},
      );
      await firestore.collection(FirestoreCollections.businesses).doc('other').set(
        <String, dynamic>{'name': 'Zeta', 'ownerId': 'someone-else'},
      );

      final businesses = await repository.watchMyBusinesses().first;

      expect(businesses.map((b) => b.id), <String>['mine']);
    });
  });

  group('saved businesses', () {
    test('saves and removes a business', () async {
      await repository.setSaved('b1', saved: true);

      var saved = await repository.watchSavedBusinessIds().first;
      expect(saved, contains('b1'));

      await repository.setSaved('b1', saved: false);
      saved = await repository.watchSavedBusinessIds().first;
      expect(saved, isNot(contains('b1')));
    });
  });

  group('rateBusiness', () {
    test('writes the rating under the rule mandated document id', () async {
      await firestore
          .collection(FirestoreCollections.businesses)
          .doc('b1')
          .set(<String, dynamic>{'name': 'Acme'});

      await repository.rateBusiness(
        businessId: 'b1',
        dealId: 'deal-1',
        stars: 4,
        comment: 'Reliable',
        userName: 'Ada',
      );

      final doc = await firestore
          .collection(FirestoreCollections.businesses)
          .doc('b1')
          .collection('ratings')
          .doc('${testUid}_deal-1')
          .get();

      expect(doc.exists, isTrue);
      expect(doc.data()?['stars'], 4);
      expect(doc.data()?['raterId'], testUid);
    });

    test('rejects a rating outside the one to five star range', () async {
      expect(
        () => repository.rateBusiness(
          businessId: 'b1',
          dealId: 'deal-1',
          stars: 6,
        ),
        throwsA(isA<AppException>()),
      );
      expect(
        () => repository.rateBusiness(
          businessId: 'b1',
          dealId: 'deal-1',
          stars: 0,
        ),
        throwsA(isA<AppException>()),
      );
    });
  });

  group('watchRatings', () {
    test('returns the ratings newest first', () async {
      final ratings = firestore
          .collection(FirestoreCollections.businesses)
          .doc('b1')
          .collection('ratings');
      await ratings.doc('r1').set(
        <String, dynamic>{'stars': 5, 'createdAt': 1000},
      );
      await ratings.doc('r2').set(
        <String, dynamic>{'stars': 3, 'createdAt': 2000},
      );

      final result = await repository.watchRatings('b1').first;

      expect(result.map((r) => r.id), <String>['r2', 'r1']);
    });
  });

  group('requestVerification', () {
    test('stores a pending verification request', () async {
      await repository.requestVerification(
        businessId: 'b1',
        documentType: 'Registration certificate',
        documentUrl: 'https://example.com/doc.pdf',
      );

      final doc = await firestore
          .collection(FirestoreCollections.verificationRequests)
          .doc('b1')
          .get();

      expect(doc.data()?['status'], 'Pending');
      expect(doc.data()?['ownerId'], testUid);
    });
  });
}
