import 'package:cloud_firestore/cloud_firestore.dart';

/// Converts Firestore exceptions into readable user-facing messages.
///
/// Firestore reports every failure as a [FirebaseException] whose `code`
/// mirrors the gRPC status name (for example `permission-denied`).
String firestoreErrorMessage(Object error, String defaultMessage) {
  if (error is FirebaseException) {
    switch (error.code) {
      case 'unauthenticated':
        return 'Your session has expired. Please sign in again.';
      case 'permission-denied':
        return 'You do not have permission to perform this action.';
      case 'not-found':
        return 'The requested item no longer exists.';
      case 'unavailable':
      case 'deadline-exceeded':
        return 'Network error. Please check your connection and try again.';
      case 'failed-precondition':
      case 'aborted':
        return 'This action is no longer available.';
      case 'already-exists':
        return 'That already exists.';
      case 'resource-exhausted':
        return 'Too many attempts. Please try again later.';
      case 'unimplemented':
      case 'invalid-argument':
      case 'out-of-range':
        return 'Some of the details provided are not valid.';
      default:
        break;
    }
  }

  final message = error.toString();
  final lower = message.toLowerCase();
  if (lower.contains('permission')) {
    return 'You do not have permission to perform this action.';
  }
  if (lower.contains('unauthenticated') || lower.contains('not signed in')) {
    return 'Your session has expired. Please sign in again.';
  }
  if (lower.contains('network') ||
      lower.contains('socket') ||
      lower.contains('unavailable')) {
    return 'Network error. Please check your connection and try again.';
  }
  if (lower.contains('already exists')) {
    return 'That already exists.';
  }

  return defaultMessage;
}
