import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:dealbridge_flutter/core/utils/app_formatters.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppFormatters', () {
    test('formats dates as dd MMM yyyy', () {
      expect(AppFormatters.date(DateTime(2026, 2, 3)), '03 Feb 2026');
    });

    test('formats times as hh:mm AM/PM', () {
      expect(AppFormatters.time(DateTime(2026, 2, 3, 14, 5)), '02:05 PM');
      expect(AppFormatters.time(DateTime(2026, 2, 3, 9, 5)), '09:05 AM');
    });

    test('returns null for missing epoch values', () {
      expect(AppFormatters.fromEpoch(null), isNull);
      expect(AppFormatters.fromEpoch(0), isNull);
      expect(AppFormatters.fromEpoch(-1), isNull);
    });

    test('formats epoch values', () {
      final millis = DateTime(2026, 2, 3).millisecondsSinceEpoch;
      expect(AppFormatters.fromEpoch(millis), '03 Feb 2026');
    });

    test('parses supported date representations', () {
      expect(AppFormatters.parseDateTime(null), isNull);
      expect(AppFormatters.parseDateTime('2026-02-03T10:00:00Z'),
          isNotNull);
      expect(AppFormatters.parseDateTime(1767225600000), isNotNull);
      expect(
        AppFormatters.parseDateTime(
          Timestamp.fromDate(DateTime(2026, 2, 3)),
        ),
        isNotNull,
      );
      expect(AppFormatters.parseDateTime('not-a-date'), isNull);
    });

    test('renders relative labels', () {
      final now = DateTime.now();
      expect(AppFormatters.relative(now.subtract(const Duration(seconds: 5))),
          'just now');
      expect(AppFormatters.relative(now.subtract(const Duration(minutes: 5))),
          '5m ago');
      expect(AppFormatters.relative(now.subtract(const Duration(hours: 3))),
          '3h ago');
      expect(AppFormatters.relative(now.subtract(const Duration(days: 2))),
          '2d ago');
    });
  });
}
