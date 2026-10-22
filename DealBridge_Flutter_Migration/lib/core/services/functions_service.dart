import 'package:cloud_functions/cloud_functions.dart';

import '../constants/app_constants.dart';
import '../utils/app_exception.dart';

/// A user returned by the `searchUsers` callable.
class UserSearchResult {
  const UserSearchResult({
    required this.id,
    required this.fullName,
    this.email = '',
    this.phone = '',
    this.company = '',
    this.city = '',
    this.status = '',
    this.isOnline = false,
    this.lastSeen,
    this.profileImage = '',
  });

  final String id;
  final String fullName;
  final String email;
  final String phone;
  final String company;
  final String city;
  final String status;
  final bool isOnline;
  final int? lastSeen;
  final String profileImage;

  factory UserSearchResult.fromMap(Map<String, dynamic> data) {
    return UserSearchResult(
      id: (data['id'] ?? '').toString(),
      fullName: (data['fullName'] ?? '').toString(),
      email: (data['email'] ?? '').toString(),
      phone: (data['phone'] ?? '').toString(),
      company: (data['company'] ?? '').toString(),
      city: (data['city'] ?? '').toString(),
      status: (data['status'] ?? '').toString(),
      isOnline: data['isOnline'] == true,
      lastSeen: (data['lastSeen'] as num?)?.toInt(),
      profileImage: (data['profileImage'] ?? '').toString(),
    );
  }
}

/// Outcome of the `deleteAccount` / `adminDeleteUser` callables.
class AccountDeletionReport {
  const AccountDeletionReport({
    this.deleted = const <String>[],
    this.anonymized = const <String>[],
    this.retained = const <String>[],
    this.requiresAdminAttention = const <String>[],
    this.cloudinaryDeleted = 0,
    this.cloudinaryFailed = const <String>[],
    this.cloudinary = '',
    this.onesignal = '',
  });

  final List<String> deleted;
  final List<String> anonymized;
  final List<String> retained;
  final List<String> requiresAdminAttention;
  final int cloudinaryDeleted;
  final List<String> cloudinaryFailed;
  final String cloudinary;
  final String onesignal;

  factory AccountDeletionReport.fromMap(Map<String, dynamic> data) {
    List<String> strings(String key) =>
        (data[key] as List?)?.map((e) => e.toString()).toList() ?? const <String>[];
    return AccountDeletionReport(
      deleted: strings('deleted'),
      anonymized: strings('anonymized'),
      retained: strings('retained'),
      requiresAdminAttention: strings('requiresAdminAttention'),
      cloudinaryDeleted: (data['cloudinaryDeleted'] as num?)?.toInt() ?? 0,
      cloudinaryFailed: strings('cloudinaryFailed'),
      cloudinary: (data['cloudinary'] ?? '').toString(),
      onesignal: (data['onesignal'] ?? '').toString(),
    );
  }
}

/// Outcome of the `deleteCloudinaryMedia` callable.
class CloudinaryDeletionResult {
  const CloudinaryDeletionResult({
    this.deleted = 0,
    this.failed = const <String>[],
    this.skipped = const <String>[],
  });

  final int deleted;
  final List<String> failed;
  final List<String> skipped;

  factory CloudinaryDeletionResult.fromMap(Map<String, dynamic> data) {
    List<String> strings(String key) =>
        (data[key] as List?)?.map((e) => e.toString()).toList() ?? const <String>[];
    return CloudinaryDeletionResult(
      deleted: (data['deleted'] as num?)?.toInt() ?? 0,
      failed: strings('failed'),
      skipped: strings('skipped'),
    );
  }
}

/// Typed wrapper around every callable Cloud Function exposed by the backend.
///
/// All functions are deployed to `us-central1`.
class FunctionsService {
  FunctionsService({FirebaseFunctions? functions})
      : _functions = functions ??
            FirebaseFunctions.instanceFor(region: functionsRegion);

  final FirebaseFunctions _functions;

  Future<T> _call<T>(
    String name,
    Map<String, dynamic> payload, {
    required T Function(Map<String, dynamic> data) parse,
  }) async {
    try {
      final result = await _functions.httpsCallable(name).call<Map<String, dynamic>>(
        payload,
      );
      final data = result.data ?? const <String, dynamic>{};
      return parse(data);
    } on FirebaseFunctionsException catch (e) {
      throw AppException(
        e.message ?? _friendlyCode(e.code),
        code: e.code,
      );
    } on AppException {
      rethrow;
    } catch (_) {
      throw const AppException(
        'Something went wrong. Please check your connection and try again.',
      );
    }
  }

  static String _friendlyCode(String code) {
    switch (code) {
      case 'unauthenticated':
        return 'Please sign in to continue.';
      case 'permission-denied':
        return 'You do not have permission to do that.';
      case 'not-found':
        return 'The requested item could not be found.';
      case 'failed-precondition':
        return 'That action is not available right now.';
      case 'resource-exhausted':
        return 'Too many attempts. Please try again later.';
      case 'already-exists':
        return 'That already exists.';
      case 'invalid-argument':
        return 'Some of the details provided are not valid.';
      default:
        return 'Something went wrong. Please try again.';
    }
  }

  // ---------------------------------------------------------------------
  // DEALS
  // ---------------------------------------------------------------------

  Future<void> cancelDeal(String dealId) {
    return _call<void>(
      'cancelDeal',
      {'dealId': dealId},
      parse: (_) {},
    );
  }

  // ---------------------------------------------------------------------
  // DISPUTES
  // ---------------------------------------------------------------------

  Future<String> fileDealDispute({
    required String dealId,
    required String businessId,
    required String reason,
    required String description,
  }) {
    return _call<String>(
      'fileDealDispute',
      {
        'dealId': dealId,
        'businessId': businessId,
        'reason': reason,
        'description': description,
      },
      parse: (data) => (data['disputeId'] ?? '').toString(),
    );
  }

  Future<String> resolveDealDispute({
    required String disputeId,
    String resolution = '',
    bool dismiss = false,
  }) {
    return _call<String>(
      'resolveDealDispute',
      {
        'disputeId': disputeId,
        'resolution': resolution,
        'dismiss': dismiss,
      },
      parse: (data) => (data['status'] ?? '').toString(),
    );
  }

  // ---------------------------------------------------------------------
  // USERS
  // ---------------------------------------------------------------------

  Future<List<UserSearchResult>> searchUsers(String query, {int limit = 20}) {
    return _call<List<UserSearchResult>>(
      'searchUsers',
      {'query': query, 'limit': limit},
      parse: (data) {
        final users = data['users'];
        if (users is! List) return const <UserSearchResult>[];
        return users
            .whereType<Map>()
            .map((e) => UserSearchResult.fromMap(e.cast<String, dynamic>()))
            .toList();
      },
    );
  }

  // ---------------------------------------------------------------------
  // ACCOUNT SECURITY
  // ---------------------------------------------------------------------

  Future<void> recordReauthentication() {
    return _call<void>(
      'recordReauthentication',
      const <String, dynamic>{},
      parse: (_) {},
    );
  }

  Future<void> recordSecurityEvent(
    String eventType, [
    Map<String, dynamic> details = const <String, dynamic>{},
  ]) {
    return _call<void>(
      'recordSecurityEvent',
      {'eventType': eventType, 'details': details},
      parse: (_) {},
    );
  }

  Future<void> revokeAllSessions() {
    return _call<void>(
      'revokeAllSessions',
      const <String, dynamic>{},
      parse: (_) {},
    );
  }

  Future<void> signOutDevice({
    required String sessionId,
    String? callerSessionId,
  }) {
    return _call<void>(
      'signOutDevice',
      {
        'sessionId': sessionId,
        if (callerSessionId != null) 'callerSessionId': callerSessionId,
      },
      parse: (_) {},
    );
  }

  Future<void> validateSession(String sessionId) {
    return _call<void>(
      'validateSession',
      {'sessionId': sessionId},
      parse: (_) {},
    );
  }

  Future<void> saveSecurityQuestion({
    required String question,
    required String answer,
  }) {
    return _call<void>(
      'saveSecurityQuestion',
      {'question': question, 'answer': answer},
      parse: (_) {},
    );
  }

  Future<String> getResetQuestion(String email) {
    return _call<String>(
      'getResetQuestion',
      {'email': email},
      parse: (data) => (data['question'] ?? '').toString(),
    );
  }

  Future<void> resetPassword({
    required String email,
    required String answer,
    required String newPassword,
  }) {
    return _call<void>(
      'resetPassword',
      {
        'email': email,
        'answer': answer,
        'newPassword': newPassword,
      },
      parse: (_) {},
    );
  }

  // ---------------------------------------------------------------------
  // ACCOUNT DELETION
  // ---------------------------------------------------------------------

  Future<AccountDeletionReport> deleteAccount() {
    return _call<AccountDeletionReport>(
      'deleteAccount',
      const <String, dynamic>{},
      parse: AccountDeletionReport.fromMap,
    );
  }

  // ---------------------------------------------------------------------
  // MEDIA
  // ---------------------------------------------------------------------

  Future<CloudinaryDeletionResult> deleteCloudinaryMedia(
    List<Map<String, String>> publicIds,
  ) {
    return _call<CloudinaryDeletionResult>(
      'deleteCloudinaryMedia',
      {'publicIds': publicIds},
      parse: CloudinaryDeletionResult.fromMap,
    );
  }

  Future<void> markMediaDelivered({
    required String messageId,
    required String mediaUrl,
  }) {
    return _call<void>(
      'markMediaDelivered',
      {'messageId': messageId, 'mediaUrl': mediaUrl},
      parse: (_) {},
    );
  }
}
