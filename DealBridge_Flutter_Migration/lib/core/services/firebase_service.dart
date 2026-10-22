import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

/// Lazily-initialised Firebase singletons.
///
/// Keeping these behind a single accessor makes every repository trivially
/// mockable in tests by passing explicit instances instead.
abstract final class FirebaseService {
  static FirebaseAuth get auth => FirebaseAuth.instance;

  static FirebaseFirestore get firestore => FirebaseFirestore.instance;

  static FirebaseFunctions get functions =>
      FirebaseFunctions.instanceFor(region: 'us-central1');

  static String get currentUid => auth.currentUser?.uid ?? '';

  static String get currentEmail => auth.currentUser?.email ?? '';
}
