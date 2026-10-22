import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/services/firebase_service.dart';
import '../models/user_profile.dart';

/// Reads and writes the `users/{uid}` document.
///
/// Firestore rules only permit a fixed set of fields to change, so every
/// write in this repository is restricted to those keys.
class UserRepository {
  UserRepository({FirebaseFirestore? firestore, FirebaseAuth? auth})
      : _db = firestore ?? FirebaseService.firestore,
        _auth = auth ?? FirebaseService.auth;

  final FirebaseFirestore _db;
  final FirebaseAuth _auth;

  String get _uid => _auth.currentUser?.uid ?? '';

  DocumentReference<Map<String, dynamic>> get _ref =>
      _db.collection(FirestoreCollections.users).doc(_uid);

  /// Watches the signed-in user's own profile document.
  Stream<UserProfile?> watchMyProfile() {
    final uid = _uid;
    if (uid.isEmpty) return const Stream<UserProfile?>.empty();
    return _db
        .collection(FirestoreCollections.users)
        .doc(uid)
        .snapshots()
        .map((doc) => doc.exists ? UserProfile.fromFirestore(doc) : null);
  }

  /// Reads a single user profile.
  Future<UserProfile?> fetchProfile(String uid) async {
    if (uid.isEmpty) return null;
    final doc =
        await _db.collection(FirestoreCollections.users).doc(uid).get();
    if (!doc.exists) return null;
    return UserProfile.fromFirestore(doc);
  }

  /// Creates the `users/{uid}` document for a newly registered account.
  ///
  /// Rules reject documents containing `role`, `isAdmin`, `ownerId`, `flagged`
  /// and related keys, so only the profile fields are written.
  Future<void> createProfile({
    required String email,
    String fullName = '',
    String phone = '',
    String company = '',
    String city = '',
  }) async {
    final uid = _uid;
    if (uid.isEmpty) return;
    await _ref.set(<String, dynamic>{
      'id': uid,
      'uid': uid,
      'email': email,
      'fullName': fullName,
      'phone': phone,
      'company': company,
      'city': city,
      'bio': '',
      'profileImage': '',
      'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Updates the editable profile fields.
  Future<void> updateProfile(UserProfile profile) {
    return _ref.update(<String, dynamic>{
      'fullName': profile.fullName,
      'email': profile.email,
      'phone': profile.phone,
      'company': profile.company,
      'city': profile.city,
      'bio': profile.bio,
      'profileImage': profile.profileImage,
      'profileImagePublicId': profile.profileImagePublicId,
      'coverImage': profile.coverImage,
      'coverImagePublicId': profile.coverImagePublicId,
      'status': profile.status,
    });
  }

  /// Stores the notification preference map.
  Future<void> updateNotificationPreferences(
    NotificationPreferences preferences,
  ) {
    return _ref.update(<String, dynamic>{
      'notificationSettings': preferences.toMap(),
    });
  }

  /// Flips the online flag and records the last-seen timestamp.
  Future<void> setPresence({required bool online}) {
    if (_uid.isEmpty) return Future<void>.value();
    return _ref.update(<String, dynamic>{
      'isOnline': online,
      'lastSeen': FieldValue.serverTimestamp(),
    });
  }

  /// Lists the users blocked by the signed-in account.
  Future<List<String>> blockedUserIds() async {
    final doc = await _ref.get();
    if (!doc.exists) return const <String>[];
    final blocked = doc.data()?['blockedUsers'];
    if (blocked is! List) return const <String>[];
    return blocked.whereType<String>().toList(growable: false);
  }

  /// Blocks or unblocks another user.
  Future<void> setUserBlocked(String targetUid, {required bool blocked}) async {
    final doc = await _ref.get();
    final current = doc.data()?['blockedUsers'];
    final ids = current is List
        ? current.whereType<String>().toSet()
        : <String>{};
    if (blocked) {
      ids.add(targetUid);
    } else {
      ids.remove(targetUid);
    }
    await _ref.update(<String, dynamic>{'blockedUsers': ids.toList()});
  }
}
