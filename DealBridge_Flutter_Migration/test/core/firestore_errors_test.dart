import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:dealbridge_flutter/core/utils/firestore_errors.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('firestoreErrorMessage', () {
    test('maps permission errors', () {
      final error = FirebaseException(plugin: 'firestore', code: 'permission-denied');
      expect(
        firestoreErrorMessage(error, 'fallback'),
        'You do not have permission to perform this action.',
      );
    });

    test('maps expired sessions', () {
      final error = FirebaseException(plugin: 'firestore', code: 'unauthenticated');
      expect(
        firestoreErrorMessage(error, 'fallback'),
        'Your session has expired. Please sign in again.',
      );
    });

    test('maps network errors', () {
      final error = FirebaseException(plugin: 'firestore', code: 'unavailable');
      expect(
        firestoreErrorMessage(error, 'fallback'),
        'Network error. Please check your connection and try again.',
      );
    });

    test('maps missing documents', () {
      final error = FirebaseException(plugin: 'firestore', code: 'not-found');
      expect(
        firestoreErrorMessage(error, 'fallback'),
        'The requested item no longer exists.',
      );
    });

    test('falls back to the default message for unknown codes', () {
      final error = FirebaseException(plugin: 'firestore', code: 'something-else');
      expect(firestoreErrorMessage(error, 'fallback'), 'fallback');
    });

    test('inspects the message when the error is not a FirebaseException', () {
      expect(
        firestoreErrorMessage(
          Exception('PERMISSION_DENIED: missing index'),
          'fallback',
        ),
        'You do not have permission to perform this action.',
      );
      expect(
        firestoreErrorMessage(Exception('SocketException'), 'fallback'),
        'Network error. Please check your connection and try again.',
      );
      expect(firestoreErrorMessage(Exception('boom'), 'fallback'), 'fallback');
    });
  });
}
