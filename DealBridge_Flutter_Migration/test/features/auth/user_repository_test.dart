import 'package:dealbridge_flutter/core/constants/app_constants.dart';
import 'package:dealbridge_flutter/features/auth/data/user_repository.dart';
import 'package:dealbridge_flutter/features/auth/models/user_profile.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/test_firebase.dart';

void main() {
  setUpAll(() async {
    await installTestFirebase();
  });

  late FakeFirebaseFirestore firestore;
  late UserRepository repository;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    repository = UserRepository(
      firestore: firestore,
      auth: FirebaseAuth.instance,
    );
  });

  group('createProfile', () {
    test('writes the profile document for the signed-in user', () async {
      await repository.createProfile(
        email: 'ada@example.com',
        fullName: 'Ada',
        phone: '+27 11 555 1234',
        company: 'Acme',
        city: 'Cape Town',
      );

      final doc = await firestore
          .collection(FirestoreCollections.users)
          .doc(testUid)
          .get();
      final data = doc.data()!;

      expect(data['id'], testUid);
      expect(data['uid'], testUid);
      expect(data['email'], 'ada@example.com');
      expect(data['fullName'], 'Ada');
      expect(data['company'], 'Acme');
      expect(data['city'], 'Cape Town');
      expect(data.containsKey('role'), isFalse);
      expect(data.containsKey('isAdmin'), isFalse);
    });
  });

  group('watchMyProfile', () {
    test('reads the profile document', () async {
      await firestore.collection(FirestoreCollections.users).doc(testUid).set(
        <String, dynamic>{
          'id': testUid,
          'fullName': 'Ada',
          'email': 'ada@example.com',
          'company': 'Acme',
        },
      );

      final profile = await repository.watchMyProfile().first;

      expect(profile, isNotNull);
      expect(profile!.fullName, 'Ada');
      expect(profile.email, 'ada@example.com');
      expect(profile.isProfileComplete, isTrue);
    });
  });

  group('updateProfile', () {
    test('writes the editable profile fields', () async {
      await firestore.collection(FirestoreCollections.users).doc(testUid).set(
        <String, dynamic>{'id': testUid, 'fullName': 'Ada'},
      );

      final profile = await repository.fetchProfile(testUid);
      await repository.updateProfile(
        profile!.copyWith(fullName: 'Ada Lovelace', city: 'London'),
      );

      final data = (await firestore
              .collection(FirestoreCollections.users)
              .doc(testUid)
              .get())
          .data()!;

      expect(data['fullName'], 'Ada Lovelace');
      expect(data['city'], 'London');
    });
  });

  group('notification preferences', () {
    test('stores the preference map', () async {
      await firestore.collection(FirestoreCollections.users).doc(testUid).set(
        <String, dynamic>{'id': testUid},
      );

      await repository.updateNotificationPreferences(
        const NotificationPreferences(
          personalMessagesEnabled: false,
          businessMessagesEnabled: true,
        ),
      );

      final data = (await firestore
              .collection(FirestoreCollections.users)
              .doc(testUid)
              .get())
          .data()!;
      final preferences = data['notificationSettings'] as Map<String, dynamic>;

      expect(preferences['personalMessagesEnabled'], isFalse);
      expect(preferences['businessMessagesEnabled'], isTrue);
      expect(preferences['dealRequestsEnabled'], isTrue);
    });
  });

  group('blocked users', () {
    test('blocks and unblocks a user', () async {
      await firestore.collection(FirestoreCollections.users).doc(testUid).set(
        <String, dynamic>{'id': testUid},
      );

      await repository.setUserBlocked('other-user', blocked: true);
      var blocked = await repository.blockedUserIds();
      expect(blocked, contains('other-user'));

      await repository.setUserBlocked('other-user', blocked: false);
      blocked = await repository.blockedUserIds();
      expect(blocked, isNot(contains('other-user')));
    });
  });
}
