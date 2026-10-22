import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/services/firebase_service.dart';
import '../../../core/utils/app_exception.dart';
import '../../../core/utils/firestore_errors.dart';
import '../models/business.dart';

/// Reads and writes the `businesses` collection plus the per-user
/// `savedBusinesses` and `followedUsers` subcollections.
class BusinessRepository {
  BusinessRepository({FirebaseFirestore? firestore, FirebaseAuth? auth})
      : _db = firestore ?? FirebaseService.firestore,
        _auth = auth ?? FirebaseService.auth;

  final FirebaseFirestore _db;
  final FirebaseAuth _auth;

  String get _uid => _auth.currentUser?.uid ?? '';

  CollectionReference<Map<String, dynamic>> get _businesses =>
      _db.collection(FirestoreCollections.businesses);

  // ---------------------------------------------------------------------
  // READ
  // ---------------------------------------------------------------------

  /// Watches the business directory.
  ///
  /// The query is bounded and filtered on the client so it works without
  /// deploying additional composite indexes.
  Stream<List<Business>> watchDirectory({int limit = 300}) {
    return _businesses
        .orderBy('name')
        .limit(limit)
        .snapshots()
        .handleError((_) {})
        .map((snapshot) => snapshot.docs.map(Business.fromFirestore).toList());
  }

  /// Watches the businesses owned by the signed-in user.
  Stream<List<Business>> watchMyBusinesses() {
    final uid = _uid;
    if (uid.isEmpty) return const Stream<List<Business>>.empty();
    return _businesses
        .where('ownerId', isEqualTo: uid)
        .snapshots()
        .handleError((_) {})
        .map((snapshot) => snapshot.docs.map(Business.fromFirestore).toList());
  }

  /// Watches a single business.
  Stream<Business?> watchBusiness(String businessId) {
    if (businessId.isEmpty) return const Stream<Business?>.empty();
    return _businesses
        .doc(businessId)
        .snapshots()
        .handleError((_) {})
        .map((doc) => doc.exists ? Business.fromFirestore(doc) : null);
  }

  /// Reads a single business.
  Future<Business?> fetchBusiness(String businessId) async {
    if (businessId.isEmpty) return null;
    final doc = await _businesses.doc(businessId).get();
    if (!doc.exists) return null;
    return Business.fromFirestore(doc);
  }

  /// Watches the ratings for a business.
  Stream<List<BusinessRating>> watchRatings(String businessId) {
    if (businessId.isEmpty) return const Stream<List<BusinessRating>>.empty();
    return _businesses
        .doc(businessId)
        .collection('ratings')
        .snapshots()
        .handleError((_) {})
        .map((snapshot) {
      final ratings = snapshot.docs.map(BusinessRating.fromFirestore).toList();
      ratings.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return ratings;
    });
  }

  // ---------------------------------------------------------------------
  // WRITE
  // ---------------------------------------------------------------------

  /// Creates a business owned by the signed-in user.
  Future<String> createBusiness({
    required String name,
    required String category,
    required String city,
    required String description,
    required String phone,
    required String email,
    required String website,
    String logoUrl = '',
    String logoPublicId = '',
    List<String> gallery = const <String>[],
    List<String> galleryPublicIds = const <String>[],
  }) async {
    final uid = _uid;
    if (uid.isEmpty) {
      throw const AppException('You must be signed in to add a business.');
    }
    if (name.trim().isEmpty) {
      throw const AppException('Please enter a business name.');
    }

    try {
      final ref = _businesses.doc();
      final business = Business(
        id: ref.id,
        ownerId: uid,
        name: name.trim(),
        category: category.trim(),
        city: city.trim(),
        description: description.trim(),
        phone: phone.trim(),
        email: email.trim(),
        website: website.trim(),
        logoUrl: logoUrl,
        logoPublicId: logoPublicId,
        gallery: gallery,
        galleryPublicIds: galleryPublicIds,
      );
      await ref.set(business.toCreateMap());
      return ref.id;
    } on FirebaseFirestoreException catch (e) {
      throw AppException(
        firestoreErrorMessage(e, 'Unable to add the business.'),
        code: e.code,
      );
    } catch (e) {
      throw AppException(
        firestoreErrorMessage(e, 'Unable to add the business.'),
      );
    }
  }

  /// Updates the editable fields of a business.
  Future<void> updateBusiness(Business business) async {
    try {
      await _businesses.doc(business.id).update(business.toUpdateMap());
    } on FirebaseFirestoreException catch (e) {
      throw AppException(
        firestoreErrorMessage(e, 'Unable to save the business.'),
        code: e.code,
      );
    } catch (e) {
      throw AppException(
        firestoreErrorMessage(e, 'Unable to save the business.'),
      );
    }
  }

  /// Deletes a business owned by the signed-in user.
  Future<void> deleteBusiness(String businessId) async {
    try {
      await _businesses.doc(businessId).delete();
    } on FirebaseFirestoreException catch (e) {
      throw AppException(
        firestoreErrorMessage(e, 'Unable to delete the business.'),
        code: e.code,
      );
    } catch (e) {
      throw AppException(
        firestoreErrorMessage(e, 'Unable to delete the business.'),
      );
    }
  }

  /// Publishes a rating for a completed deal.
  ///
  /// The rating document id is fixed by the security rules to
  /// `{raterId}_{dealId}`.
  Future<void> rateBusiness({
    required String businessId,
    required String dealId,
    required int stars,
    String comment = '',
    String userName = '',
  }) async {
    final uid = _uid;
    if (uid.isEmpty) {
      throw const AppException('You must be signed in to rate a business.');
    }
    if (stars < 1 || stars > 5) {
      throw const AppException('Choose a rating between 1 and 5 stars.');
    }

    try {
      await _businesses
          .doc(businessId)
          .collection('ratings')
          .doc('${uid}_$dealId')
          .set(<String, dynamic>{
            'raterId': uid,
            'stars': stars,
            'dealId': dealId,
            'comment': comment.trim(),
            'userName': userName.trim(),
            'createdAt': FieldValue.serverTimestamp(),
          });
    } on FirebaseFirestoreException catch (e) {
      throw AppException(
        firestoreErrorMessage(e, 'Unable to submit the rating.'),
        code: e.code,
      );
    } catch (e) {
      throw AppException(
        firestoreErrorMessage(e, 'Unable to submit the rating.'),
      );
    }
  }

  // ---------------------------------------------------------------------
  // SAVED BUSINESSES
  // ---------------------------------------------------------------------

  /// Watches the ids of the user's saved businesses.
  Stream<Set<String>> watchSavedBusinessIds() {
    final uid = _uid;
    if (uid.isEmpty) return const Stream<Set<String>>.empty();
    return _db
        .collection(FirestoreCollections.users)
        .doc(uid)
        .collection(FirestoreCollections.savedBusinesses)
        .snapshots()
        .handleError((_) {})
        .map((snapshot) => snapshot.docs.map((doc) => doc.id).toSet());
  }

  /// Saves or removes a business from the user's saved list.
  Future<void> setSaved(String businessId, {required bool saved}) async {
    final uid = _uid;
    if (uid.isEmpty || businessId.isEmpty) return;
    final ref = _db
        .collection(FirestoreCollections.users)
        .doc(uid)
        .collection(FirestoreCollections.savedBusinesses)
        .doc(businessId);
    if (saved) {
      await ref.set(<String, dynamic>{
        'businessId': businessId,
        'savedAt': FieldValue.serverTimestamp(),
      });
    } else {
      await ref.delete();
    }
  }

  // ---------------------------------------------------------------------
  // VERIFICATION
  // ---------------------------------------------------------------------

  /// Requests business verification.
  Future<void> requestVerification({
    required String businessId,
    required String documentType,
    required String documentUrl,
    String note = '',
  }) async {
    final uid = _uid;
    if (uid.isEmpty) {
      throw const AppException('You must be signed in to request verification.');
    }
    try {
      await _db
          .collection(FirestoreCollections.verificationRequests)
          .doc(businessId)
          .set(<String, dynamic>{
            'businessId': businessId,
            'ownerId': uid,
            'documentType': documentType,
            'documentUrl': documentUrl,
            'note': note.trim(),
            'status': 'Pending',
            'requestedAt': FieldValue.serverTimestamp(),
          });
    } on FirebaseFirestoreException catch (e) {
      throw AppException(
        firestoreErrorMessage(e, 'Unable to submit the request.'),
        code: e.code,
      );
    } catch (e) {
      throw AppException(
        firestoreErrorMessage(e, 'Unable to submit the request.'),
      );
    }
  }

  /// Reads the verification request for a business, when the owner can see it.
  Future<Map<String, dynamic>?> fetchVerificationRequest(
    String businessId,
  ) async {
    try {
      final doc = await _db
          .collection(FirestoreCollections.verificationRequests)
          .doc(businessId)
          .get();
      if (!doc.exists) return null;
      return doc.data();
    } catch (_) {
      return null;
    }
  }
}
