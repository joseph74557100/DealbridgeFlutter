import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/services/firebase_service.dart';

/// A device session recorded under `users/{uid}/sessions/{sessionId}`.
class DeviceSession {
  const DeviceSession({
    required this.id,
    this.deviceName = '',
    this.platform = '',
    this.lastActive,
    this.loginTimestamp,
    this.sessionVersion = 1,
    this.current = false,
  });

  final String id;
  final String deviceName;
  final String platform;
  final DateTime? lastActive;
  final DateTime? loginTimestamp;
  final int sessionVersion;
  final bool current;

  factory DeviceSession.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
    {required String currentSessionId}) {
    final data = doc.data() ?? const <String, dynamic>{};
    final lastActive = data['lastActive'];
    final loginTimestamp = data['loginTimestamp'];
    return DeviceSession(
      id: doc.id,
      deviceName: (data['deviceName'] ?? '').toString(),
      platform: (data['platform'] ?? '').toString(),
      lastActive: lastActive is Timestamp ? lastActive.toDate() : null,
      loginTimestamp: loginTimestamp is Timestamp
          ? loginTimestamp.toDate()
          : null,
      sessionVersion: (data['sessionVersion'] as num?)?.toInt() ?? 1,
      current: doc.id == currentSessionId,
    );
  }
}

/// Tracks the signed-in device session so users can review and revoke devices.
class SessionRepository {
  SessionRepository({FirebaseFirestore? firestore, FirebaseAuth? auth})
      : _db = firestore ?? FirebaseService.firestore,
        _auth = auth ?? FirebaseService.auth;

  final FirebaseFirestore _db;
  final FirebaseAuth _auth;

  static const _idAlphabet =
      'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';

  String get _uid => _auth.currentUser?.uid ?? '';

  /// Generates a random session identifier.
  String newSessionId() {
    final random = Random.secure();
    return List<String>.generate(
      24,
      (_) => _idAlphabet[random.nextInt(_idAlphabet.length)],
    ).join();
  }

  /// Registers the current device session.
  Future<void> registerSession({
    required String sessionId,
    required String deviceName,
    required String platform,
    required String appVersion,
    required String timezone,
  }) async {
    if (_uid.isEmpty) return;
    await _db
        .collection(FirestoreCollections.users)
        .doc(_uid)
        .collection(FirestoreCollections.sessions)
        .doc(sessionId)
        .set(<String, dynamic>{
          'deviceName': deviceName,
          'platform': platform,
          'appVersion': appVersion,
          'timezone': timezone,
          'loginTimestamp': FieldValue.serverTimestamp(),
          'lastActive': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
  }

  /// Refreshes the `lastActive` timestamp. Rules only allow this key to change.
  Future<void> touchSession(String sessionId) async {
    if (_uid.isEmpty || sessionId.isEmpty) return;
    try {
      await _db
          .collection(FirestoreCollections.users)
          .doc(_uid)
          .collection(FirestoreCollections.sessions)
          .doc(sessionId)
          .update(<String, dynamic>{
            'lastActive': FieldValue.serverTimestamp(),
          });
    } catch (_) {
      // A revoked session must not break the app.
    }
  }

  /// Lists all sessions for the signed-in account.
  Future<List<DeviceSession>> listSessions({
    required String currentSessionId,
  }) async {
    if (_uid.isEmpty) return const <DeviceSession>[];
    final snapshot = await _db
        .collection(FirestoreCollections.users)
        .doc(_uid)
        .collection(FirestoreCollections.sessions)
        .get();
    final sessions = snapshot.docs
        .map(
          (doc) => DeviceSession.fromFirestore(
            doc,
            currentSessionId: currentSessionId,
          ),
        )
        .toList();
    sessions.sort((a, b) {
      final aTime = a.lastActive ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bTime = b.lastActive ?? DateTime.fromMillisecondsSinceEpoch(0);
      return bTime.compareTo(aTime);
    });
    return sessions;
  }

  /// Removes a session document.
  Future<void> deleteSession(String sessionId) async {
    if (_uid.isEmpty || sessionId.isEmpty) return;
    await _db
        .collection(FirestoreCollections.users)
        .doc(_uid)
        .collection(FirestoreCollections.sessions)
        .doc(sessionId)
        .delete();
  }
}
