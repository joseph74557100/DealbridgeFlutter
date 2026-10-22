import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/utils/app_formatters.dart';

/// Per-user notification preferences stored at `users/{uid}.notificationSettings`.
///
/// The backend reads `personalMessagesEnabled` and `businessMessagesEnabled`
/// before pushing OneSignal notifications, so those two names are load-bearing.
class NotificationPreferences {
  const NotificationPreferences({
    this.personalMessagesEnabled = true,
    this.businessMessagesEnabled = true,
    this.dealRequestsEnabled = true,
    this.dealUpdatesEnabled = true,
    this.postsEnabled = true,
    this.pushEnabled = true,
  });

  final bool personalMessagesEnabled;
  final bool businessMessagesEnabled;
  final bool dealRequestsEnabled;
  final bool dealUpdatesEnabled;
  final bool postsEnabled;
  final bool pushEnabled;

  factory NotificationPreferences.fromMap(Map<String, dynamic>? data) {
    final map = data ?? const <String, dynamic>{};
    bool read(String key, bool fallback) {
      final value = map[key];
      return value is bool ? value : fallback;
    }

    return NotificationPreferences(
      personalMessagesEnabled: read('personalMessagesEnabled', true),
      businessMessagesEnabled: read('businessMessagesEnabled', true),
      dealRequestsEnabled: read('dealRequestsEnabled', true),
      dealUpdatesEnabled: read('dealUpdatesEnabled', true),
      postsEnabled: read('postsEnabled', true),
      pushEnabled: read('pushEnabled', true),
    );
  }

  Map<String, dynamic> toMap() => <String, dynamic>{
        'personalMessagesEnabled': personalMessagesEnabled,
        'businessMessagesEnabled': businessMessagesEnabled,
        'dealRequestsEnabled': dealRequestsEnabled,
        'dealUpdatesEnabled': dealUpdatesEnabled,
        'postsEnabled': postsEnabled,
        'pushEnabled': pushEnabled,
      };

  NotificationPreferences copyWith({
    bool? personalMessagesEnabled,
    bool? businessMessagesEnabled,
    bool? dealRequestsEnabled,
    bool? dealUpdatesEnabled,
    bool? postsEnabled,
    bool? pushEnabled,
  }) {
    return NotificationPreferences(
      personalMessagesEnabled:
          personalMessagesEnabled ?? this.personalMessagesEnabled,
      businessMessagesEnabled:
          businessMessagesEnabled ?? this.businessMessagesEnabled,
      dealRequestsEnabled: dealRequestsEnabled ?? this.dealRequestsEnabled,
      dealUpdatesEnabled: dealUpdatesEnabled ?? this.dealUpdatesEnabled,
      postsEnabled: postsEnabled ?? this.postsEnabled,
      pushEnabled: pushEnabled ?? this.pushEnabled,
    );
  }
}

/// The `users/{uid}` document.
class UserProfile {
  const UserProfile({
    required this.id,
    this.uid = '',
    this.fullName = '',
    this.email = '',
    this.phone = '',
    this.company = '',
    this.city = '',
    this.bio = '',
    this.profileImage = '',
    this.profileImagePublicId = '',
    this.coverImage = '',
    this.coverImagePublicId = '',
    this.isOnline = false,
    this.status = '',
    this.lastSeen,
    this.notificationSettings = const NotificationPreferences(),
    this.twoFactorEnabled = false,
    this.blockedUsers = const <String>[],
  });

  final String id;
  final String uid;
  final String fullName;
  final String email;
  final String phone;
  final String company;
  final String city;
  final String bio;
  final String profileImage;
  final String profileImagePublicId;
  final String coverImage;
  final String coverImagePublicId;
  final bool isOnline;
  final String status;
  final DateTime? lastSeen;
  final NotificationPreferences notificationSettings;
  final bool twoFactorEnabled;
  final List<String> blockedUsers;

  bool get isProfileComplete => fullName.trim().isNotEmpty;

  factory UserProfile.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? const <String, dynamic>{};
    final blocked = data['blockedUsers'];
    return UserProfile(
      id: doc.id,
      uid: (data['uid'] ?? doc.id).toString(),
      fullName: (data['fullName'] ?? '').toString(),
      email: (data['email'] ?? '').toString(),
      phone: (data['phone'] ?? '').toString(),
      company: (data['company'] ?? '').toString(),
      city: (data['city'] ?? '').toString(),
      bio: (data['bio'] ?? '').toString(),
      profileImage: (data['profileImage'] ?? '').toString(),
      profileImagePublicId: (data['profileImagePublicId'] ?? '').toString(),
      coverImage: (data['coverImage'] ?? '').toString(),
      coverImagePublicId: (data['coverImagePublicId'] ?? '').toString(),
      isOnline: data['isOnline'] == true,
      status: (data['status'] ?? '').toString(),
      lastSeen: AppFormatters.parseDateTime(data['lastSeen']),
      notificationSettings: NotificationPreferences.fromMap(
        data['notificationSettings'] as Map<String, dynamic>?,
      ),
      twoFactorEnabled: data['twoFactorEnabled'] == true,
      blockedUsers: blocked is List
          ? blocked.whereType<String>().toList(growable: false)
          : const <String>[],
    );
  }

  UserProfile copyWith({
    String? fullName,
    String? email,
    String? phone,
    String? company,
    String? city,
    String? bio,
    String? profileImage,
    String? profileImagePublicId,
    String? coverImage,
    String? coverImagePublicId,
    String? status,
    bool? isOnline,
    DateTime? lastSeen,
    NotificationPreferences? notificationSettings,
    bool? twoFactorEnabled,
  }) {
    return UserProfile(
      id: id,
      uid: uid,
      fullName: fullName ?? this.fullName,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      company: company ?? this.company,
      city: city ?? this.city,
      bio: bio ?? this.bio,
      profileImage: profileImage ?? this.profileImage,
      profileImagePublicId: profileImagePublicId ?? this.profileImagePublicId,
      coverImage: coverImage ?? this.coverImage,
      coverImagePublicId: coverImagePublicId ?? this.coverImagePublicId,
      isOnline: isOnline ?? this.isOnline,
      status: status ?? this.status,
      lastSeen: lastSeen ?? this.lastSeen,
      notificationSettings:
          notificationSettings ?? this.notificationSettings,
      twoFactorEnabled: twoFactorEnabled ?? this.twoFactorEnabled,
      blockedUsers: blockedUsers,
    );
  }
}
