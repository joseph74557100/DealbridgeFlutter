import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_platform_interface/firebase_auth_platform_interface.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/test.dart';
import 'package:flutter_test/flutter_test.dart';

/// Default uid used by the fake authentication platform.
const String testUid = 'test-user-1';

/// Installs the fake Firebase Core and Auth platforms.
///
/// `FirebaseAuth.instance` requires an initialised default app, so the core
/// mocks are installed first and a default app is created.
Future<void> installTestFirebase({String uid = testUid}) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  if (Firebase.apps.isEmpty) {
    setupFirebaseCoreMocks();
    await Firebase.initializeApp(
      options: const FirebaseOptions(
        apiKey: '123',
        appId: '123',
        messagingSenderId: '123',
        projectId: '123',
      ),
    );
  }
  FirebaseAuthPlatform.instance = FakeAuthPlatform(uid);
}

/// A [FirebaseAuthPlatform] that always reports the same signed-in user.
class FakeAuthPlatform extends FirebaseAuthPlatform {
  FakeAuthPlatform(this._uid);

  final String _uid;

  @override
  FirebaseAuthPlatform delegateFor({required FirebaseApp app}) => this;

  @override
  FirebaseAuthPlatform setInitialValues({
    PigeonUserDetails? currentUser,
    String? languageCode,
  }) =>
      this;

  @override
  UserPlatform? get currentUser => FakeUserPlatform(this, _uid);
}

/// A minimal [UserPlatform] carrying only a uid.
class FakeUserPlatform extends UserPlatform {
  FakeUserPlatform(FirebaseAuthPlatform auth, String uid)
      : super(
          auth,
          _FakeMultiFactor(auth),
          PigeonUserDetails(
            userInfo: PigeonUserInfo(
              uid: uid,
              email: 'test@example.com',
              isAnonymous: false,
              isEmailVerified: true,
            ),
            providerData: const <Map<Object?, Object?>?>[],
          ),
        );
}

class _FakeMultiFactor extends MultiFactorPlatform {
  _FakeMultiFactor(super.auth);
}

/// Creates a fake Firestore seeded with [documents].
///
/// The collection paths are relative to the root, e.g. `users/user-1`.
FakeFirebaseFirestore createFakeFirestore([
  Map<String, Object> documents = const <String, Object>{},
]) {
  final firestore = FakeFirebaseFirestore();
  documents.forEach((path, data) {
    final parts = path.split('/');
    final collection = parts.first;
    final documentId = parts.length > 1 ? parts[1] : path;
    final map = (data as Map<Object?, Object?>?)?.cast<String, dynamic>() ??
        <String, dynamic>{};
    firestore.collection(collection).doc(documentId).set(map);
  });
  return firestore;
}
