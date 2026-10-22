import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

/// Date/time formatting helpers matching the backend's canonical formats:
/// dates render as `dd MMM yyyy` and times as `hh:mm AM/PM`.
abstract final class AppFormatters {
  static final DateFormat _date = DateFormat('dd MMM yyyy');
  static final DateFormat _dateTime = DateFormat('dd MMM yyyy HH:mm');
  static final DateFormat _time = DateFormat('hh:mm AM/PM');

  static String date(DateTime value) => _date.format(value.toLocal());

  static String dateTime(DateTime value) => _dateTime.format(value.toLocal());

  static String time(DateTime value) => _time.format(value.toLocal());

  /// Formats an epoch-milliseconds value, returning `null` for missing data.
  static String? fromEpoch(int? millis) {
    if (millis == null || millis <= 0) return null;
    return date(DateTime.fromMillisecondsSinceEpoch(millis));
  }

  /// Formats an epoch-milliseconds value with time, `null` for missing data.
  static String? dateTimeFromEpoch(int? millis) {
    if (millis == null || millis <= 0) return null;
    return dateTime(DateTime.fromMillisecondsSinceEpoch(millis));
  }

  /// Human readable "2h ago" style label.
  static String relative(DateTime value) {
    final now = DateTime.now();
    final diff = now.difference(value.toLocal());
    if (diff.isNegative) return 'just now';
    if (diff.inSeconds < 60) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    if (diff.inDays < 365) return _date.format(value.toLocal());
    return _date.format(value.toLocal());
  }

  /// Reads a Firestore `Timestamp`/epoch/int/ISO string into a `DateTime`.
  static DateTime? parseDateTime(dynamic raw) {
    if (raw == null) return null;
    if (raw is DateTime) return raw;
    if (raw is Timestamp) return raw.toDate();
    if (raw is int) {
      return raw <= 0 ? null : DateTime.fromMillisecondsSinceEpoch(raw);
    }
    if (raw is String) {
      final parsed = DateTime.tryParse(raw);
      if (parsed != null) return parsed;
      final asInt = int.tryParse(raw);
      if (asInt != null && asInt > 0) {
        return DateTime.fromMillisecondsSinceEpoch(asInt);
      }
    }
    return null;
  }
}
