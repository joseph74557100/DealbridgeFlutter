import 'package:firebase_auth/firebase_auth.dart';

import '../../../core/services/firebase_service.dart';
import '../../../core/utils/app_exception.dart';
import 'user_repository.dart';

/// Authentication operations backed by Firebase Auth.
class AuthRepository {
  AuthRepository({FirebaseAuth? auth, UserRepository? userRepository})
      : _auth = auth ?? FirebaseService.auth,
        _users = userRepository ?? UserRepository();

  final FirebaseAuth _auth;
  final UserRepository _users;

  User? get currentUser => _auth.currentUser;

  String get currentUid => _auth.currentUser?.uid ?? '';

  /// Signs in with email and password.
  Future<UserCredential> signIn({
    required String email,
    required String password,
  }) async {
    try {
      return await _auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
    } on FirebaseAuthException catch (e) {
      throw AppException(_messageFor(e.code), code: e.code);
    }
  }

  /// Registers a new account and provisions its `users/{uid}` document.
  Future<UserCredential> register({
    required String email,
    required String password,
    String fullName = '',
    String phone = '',
    String company = '',
    String city = '',
  }) async {
    try {
      final credential = await _auth.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      await _users.createProfile(
        email: email.trim(),
        fullName: fullName.trim(),
        phone: phone.trim(),
        company: company.trim(),
        city: city.trim(),
      );
      return credential;
    } on FirebaseAuthException catch (e) {
      throw AppException(_messageFor(e.code), code: e.code);
    }
  }

  /// Sends the standard Firebase password-reset email.
  Future<void> sendPasswordResetEmail(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email.trim());
    } on FirebaseAuthException catch (e) {
      throw AppException(_messageFor(e.code), code: e.code);
    }
  }

  /// Signs the user out.
  Future<void> signOut() async {
    await _auth.signOut();
  }

  static String _messageFor(String code) {
    switch (code) {
      case 'invalid-email':
        return 'That email address is not valid.';
      case 'user-disabled':
        return 'This account has been disabled.';
      case 'user-not-found':
        return 'No account found for that email address.';
      case 'wrong-password':
      case 'invalid-credential':
      case 'invalid-login-credentials':
        return 'Incorrect email address or password.';
      case 'email-already-in-use':
        return 'An account already exists for that email address.';
      case 'weak-password':
        return 'Choose a stronger password.';
      case 'too-many-requests':
        return 'Too many attempts. Please try again later.';
      case 'network-request-failed':
        return 'Network error. Check your connection and try again.';
      default:
        return 'Something went wrong. Please try again.';
    }
  }
}
