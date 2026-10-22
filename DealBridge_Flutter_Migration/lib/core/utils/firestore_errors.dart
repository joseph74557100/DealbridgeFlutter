import 'package:cloud_firestore/cloud_firestore.dart';

/// Converts Firestore exceptions into readable user-facing messages.
String firestoreErrorMessage(Object error, String defaultMessage) {
  if (error is FirebaseFirestoreException) {
    switch (error.code) {
      case 'unauthenticated':
        return 'Your session has expired. Please sign in again.';
      case 'permission-denied':
        return 'You do not have permission to perform this action.';
      case 'not-found':
        return 'The requested item no longer exists.';
      case 'unavailable':
        return 'Network error. Please check your connection and try again.';
      case 'failed-precondition':
        return 'This action is no longer available.';
      case 'already-exists':
        return 'That already exists.';
      case 'unimplemented':
      case 'invalid-argument':
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
  if (lower.contains('unauthenticated')) {
    return 'Your session has expired. Please sign in again.';
  }
  if (lower.contains('network') || lower.contains('socket')) {
    return 'Network error. Please check your connection and try again.';
  }
  if (lower.contains('already exists')) {
    return 'That already exists.';
  }

  return defaultMessage;
}
