import 'package:cloud_firestore/cloud_firestore.dart';

/// The `businesses/{businessId}` document.
class Business {
  const Business({
    required this.id,
    this.ownerId = '',
    this.name = '',
    this.category = '',
    this.city = '',
    this.description = '',
    this.phone = '',
    this.email = '',
    this.website = '',
    this.logoUrl = '',
    this.logoPublicId = '',
    this.gallery = const <String>[],
    this.galleryPublicIds = const <String>[],
    this.verified = false,
    this.rating = 0,
    this.ratingCount = 0,
    this.promoted = false,
    this.followersCount = 0,
    this.createdAt = 0,
    this.verificationStatus = 'Not Verified',
    this.verificationLevel = 0,
    this.trustScore = 50,
    this.completedDeals = 0,
    this.disputeCount = 0,
    this.reportCount = 0,
    this.businessStatus = '',
  });

  final String id;
  final String ownerId;
  final String name;
  final String category;
  final String city;
  final String description;
  final String phone;
  final String email;
  final String website;
  final String logoUrl;
  final String logoPublicId;
  final List<String> gallery;
  final List<String> galleryPublicIds;
  final bool verified;
  final double rating;
  final int ratingCount;
  final bool promoted;
  final int followersCount;
  final int createdAt;
  final String verificationStatus;
  final int verificationLevel;
  final int trustScore;
  final int completedDeals;
  final int disputeCount;
  final int reportCount;
  final String businessStatus;

  /// The badge only shows when the server confirmed both flags.
  bool get isGenuinelyVerified => verified && verificationLevel >= 1;

  bool get isSuspended =>
      businessStatus.toLowerCase() == 'suspended' ||
      businessStatus.toLowerCase() == 'disabled';

  factory Business.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const <String, dynamic>{};
    return Business(
      id: doc.id,
      ownerId: (data['ownerId'] ?? '').toString(),
      name: (data['name'] ?? '').toString(),
      category: (data['category'] ?? '').toString(),
      city: (data['city'] ?? '').toString(),
      description: (data['description'] ?? '').toString(),
      phone: (data['phone'] ?? '').toString(),
      email: (data['email'] ?? '').toString(),
      website: (data['website'] ?? '').toString(),
      logoUrl: (data['logoUrl'] ?? '').toString(),
      logoPublicId: (data['logoPublicId'] ?? '').toString(),
      gallery: _stringList(data['gallery']),
      galleryPublicIds: _stringList(data['galleryPublicIds']),
      verified: data['verified'] == true,
      rating: (data['rating'] as num?)?.toDouble() ?? 0,
      ratingCount: (data['ratingCount'] as num?)?.toInt() ?? 0,
      promoted: data['promoted'] == true,
      followersCount: (data['followersCount'] as num?)?.toInt() ?? 0,
      createdAt: _int(data['createdAt']),
      verificationStatus: (data['verificationStatus'] ?? 'Not Verified').toString(),
      verificationLevel: (data['verificationLevel'] as num?)?.toInt() ?? 0,
      trustScore: (data['trustScore'] as num?)?.toInt() ?? 50,
      completedDeals: (data['completedDeals'] as num?)?.toInt() ?? 0,
      disputeCount: (data['disputeCount'] as num?)?.toInt() ?? 0,
      reportCount: (data['reportCount'] as num?)?.toInt() ?? 0,
      businessStatus: (data['businessStatus'] ?? '').toString(),
    );
  }

  /// The payload accepted by the Firestore `businesses` create rule.
  ///
  /// Server-owned counters must be written with their required defaults.
  Map<String, dynamic> toCreateMap() {
    return <String, dynamic>{
      'id': id,
      'ownerId': ownerId,
      'name': name,
      'category': category,
      'city': city,
      'description': description,
      'phone': phone,
      'email': email,
      'website': website,
      'logoUrl': logoUrl,
      'logoPublicId': logoPublicId,
      'gallery': gallery,
      'galleryPublicIds': galleryPublicIds,
      'trustScore': 50,
      'verificationLevel': 0,
      'verified': false,
      'completedDeals': 0,
      'disputeCount': 0,
      'reportCount': 0,
      'rating': 0,
      'ratingCount': 0,
      'promoted': false,
      'followersCount': 0,
      'createdAt': FieldValue.serverTimestamp(),
    };
  }

  /// The subset of fields the Firestore update rule allows.
  Map<String, dynamic> toUpdateMap() {
    return <String, dynamic>{
      'name': name,
      'category': category,
      'city': city,
      'description': description,
      'phone': phone,
      'email': email,
      'website': website,
      'logoUrl': logoUrl,
      'logoPublicId': logoPublicId,
      'gallery': gallery,
      'galleryPublicIds': galleryPublicIds,
    };
  }

  static int _int(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is Timestamp) return value.toDate().millisecondsSinceEpoch;
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }

  static List<String> _stringList(dynamic value) {
    if (value is List) {
      return value.whereType<String>().toList(growable: false);
    }
    return const <String>[];
  }
}

/// A rating stored under `businesses/{businessId}/ratings/{ratingId}`.
class BusinessRating {
  const BusinessRating({
    required this.id,
    this.raterId = '',
    this.stars = 0,
    this.dealId = '',
    this.comment = '',
    this.userName = '',
    this.createdAt = 0,
  });

  final String id;
  final String raterId;
  final int stars;
  final String dealId;
  final String comment;
  final String userName;
  final int createdAt;

  factory BusinessRating.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? const <String, dynamic>{};
    return BusinessRating(
      id: doc.id,
      raterId: (data['raterId'] ?? '').toString(),
      stars: (data['stars'] as num?)?.toInt() ?? 0,
      dealId: (data['dealId'] ?? '').toString(),
      comment: (data['comment'] ?? '').toString(),
      userName: (data['userName'] ?? '').toString(),
      createdAt: _int(data['createdAt']),
    );
  }

  static int _int(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is Timestamp) return value.toDate().millisecondsSinceEpoch;
    return 0;
  }
}
