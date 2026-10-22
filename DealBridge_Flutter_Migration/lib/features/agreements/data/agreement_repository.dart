import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/services/firebase_service.dart';
import '../../../core/utils/app_exception.dart';
import '../../../core/utils/firestore_errors.dart';
import '../models/agreement.dart';

/// Reads and updates the `agreements` collection.
///
/// The backend generates agreements when both parties confirm a deal. The
/// client may only update whitelisted metadata keys.
class AgreementRepository {
  AgreementRepository({FirebaseFirestore? firestore, FirebaseAuth? auth})
      : _db = firestore ?? FirebaseService.firestore,
        _auth = auth ?? FirebaseService.auth;

  final FirebaseFirestore _db;
  final FirebaseAuth _auth;

  String get _uid => _auth.currentUser?.uid ?? '';

  CollectionReference<Map<String, dynamic>> get _agreements =>
      _db.collection(FirestoreCollections.agreements);

  /// Watches every agreement the signed-in user participates in.
  Stream<List<Agreement>> watchMyAgreements() {
    final uid = _uid;
    if (uid.isEmpty) return const Stream<List<Agreement>>.empty();
    return _agreements
        .where('participantIds', arrayContains: uid)
        .snapshots()
        .handleError((_) {})
        .map((snapshot) {
      final agreements = snapshot.docs
          .map(Agreement.fromFirestore)
          .toList();
      agreements.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return agreements;
    });
  }

  /// Reads a single agreement.
  Future<Agreement?> fetchAgreement(String agreementId) async {
    if (agreementId.isEmpty) return null;
    final doc = await _agreements.doc(agreementId).get();
    if (!doc.exists) return null;
    return Agreement.fromFirestore(doc);
  }

  /// Finds the agreement generated for a deal.
  ///
  /// The backend uses the deal id as the agreement document id, but older
  /// agreements use their own id, so both are checked.
  Future<Agreement?> findForDeal(String dealId) async {
    if (dealId.isEmpty) return null;
    final direct = await fetchAgreement(dealId);
    if (direct != null) return direct;
    try {
      final snapshot = await _agreements
          .where('dealId', isEqualTo: dealId)
          .limit(1)
          .get();
      if (snapshot.docs.isEmpty) return null;
      return Agreement.fromFirestore(snapshot.docs.first);
    } catch (_) {
      return null;
    }
  }

  /// Updates the whitelisted metadata fields of an agreement.
  Future<void> updateMetadata({
    required String agreementId,
    String? notes,
    String? status,
  }) async {
    final updates = <String, dynamic>{};
    if (notes != null) updates['notes'] = notes;
    if (status != null) updates['status'] = status;
    if (updates.isEmpty) return;
    updates['updatedBy'] = _uid;

    try {
      await _agreements.doc(agreementId).update(updates);
    } on FirebaseException catch (e) {
      throw AppException(
        firestoreErrorMessage(e, 'Unable to update the agreement.'),
        code: e.code,
      );
    } catch (e) {
      throw AppException(
        firestoreErrorMessage(e, 'Unable to update the agreement.'),
      );
    }
  }

  /// Archives an agreement.
  Future<void> archive(String agreementId) {
    return updateMetadata(
      agreementId: agreementId,
      status: AgreementStatus.archived,
    );
  }

  /// Restores an archived agreement.
  Future<void> restore(String agreementId) {
    return updateMetadata(
      agreementId: agreementId,
      status: AgreementStatus.pendingSignature,
    );
  }

  /// Deletes an unsigned agreement.
  Future<void> delete(String agreementId) async {
    try {
      await _agreements.doc(agreementId).delete();
    } on FirebaseException catch (e) {
      throw AppException(
        firestoreErrorMessage(e, 'Unable to delete the agreement.'),
        code: e.code,
      );
    } catch (e) {
      throw AppException(
        firestoreErrorMessage(e, 'Unable to delete the agreement.'),
      );
    }
  }
}
