import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/services/firebase_service.dart';
import '../../../core/utils/app_exception.dart';
import '../../../core/utils/app_formatters.dart';
import '../../../core/utils/firestore_errors.dart';
import '../models/deal.dart';

/// Reads and writes the `deals` collection.
///
/// Only the client-writable lifecycle states are written directly:
/// `PENDING`, `ACCEPTED` and `DECLINED`. Server-authoritative states
/// (`COMPLETED`, `CANCELLED`, `EXPIRED`) are reached through Cloud Functions.
class DealRepository {
  DealRepository({FirebaseFirestore? firestore, FirebaseAuth? auth})
      : _db = firestore ?? FirebaseService.firestore,
        _auth = auth ?? FirebaseService.auth;

  final FirebaseFirestore _db;
  final FirebaseAuth _auth;

  String get _uid => _auth.currentUser?.uid ?? '';

  CollectionReference<Map<String, dynamic>> get _deals =>
      _db.collection(FirestoreCollections.deals);

  // ---------------------------------------------------------------------
  // READ
  // ---------------------------------------------------------------------

  /// Watches every deal the signed-in user participates in.
  ///
  /// The listener keeps the last successful snapshot when the stream reports
  /// an error so offline cached data stays visible.
  Stream<List<Deal>> watchMyDeals() {
    final uid = _uid;
    if (uid.isEmpty) return const Stream<List<Deal>>.empty();
    return _deals
        .where('participantIds', arrayContains: uid)
        .snapshots()
        .handleError((_) {})
        .map(_mapSnapshot);
  }

  /// Watches a single deal.
  Stream<Deal?> watchDeal(String dealId) {
    if (dealId.isEmpty) return const Stream<Deal?>.empty();
    return _deals
        .doc(dealId)
        .snapshots()
        .handleError((_) {})
        .map((doc) => doc.exists ? Deal.fromFirestore(doc) : null);
  }

  /// Watches the ids of deals the user has hidden.
  Stream<Set<String>> watchHiddenDealIds() {
    final uid = _uid;
    if (uid.isEmpty) return const Stream<Set<String>>.empty();
    return _db
        .collection(FirestoreCollections.users)
        .doc(uid)
        .collection(FirestoreCollections.hiddenDeals)
        .snapshots()
        .handleError((_) {})
        .map((snapshot) => snapshot.docs.map((doc) => doc.id).toSet());
  }

  List<Deal> _mapSnapshot(QuerySnapshot<Map<String, dynamic>> snapshot) {
    final deals = snapshot.docs
        .map(Deal.fromFirestore)
        .where((deal) => deal.status != DealStatus.cancelled)
        .toList();
    deals.sort(
      (a, b) => b.sortTimestamp.compareTo(a.sortTimestamp),
    );
    return deals;
  }

  /// Reads a deal once.
  Future<Deal?> fetchDeal(String dealId) async {
    final doc = await _deals.doc(dealId).get();
    if (!doc.exists) return null;
    return Deal.fromFirestore(doc);
  }

  // ---------------------------------------------------------------------
  // CREATE
  // ---------------------------------------------------------------------

  /// Creates a `PENDING` deal request against a target business.
  ///
  /// Firestore rules require `participantIds` to be exactly
  /// `[senderUid, businessOwnerUid]`, so the business owner is resolved
  /// before writing.
  Future<String> createDeal({
    required String businessId,
    required String businessName,
    required String title,
    required String description,
    required String value,
    required String senderName,
    String terms = '',
    int deadline = 0,
  }) async {
    final uid = _uid;
    if (uid.isEmpty) {
      throw const AppException('You must be signed in to send a deal.');
    }
    if (title.trim().isEmpty) {
      throw const AppException('Please enter a deal title.');
    }
    if (businessId.isEmpty) {
      throw const AppException('Please select a business.');
    }

    try {
      final businessDoc = await _db
          .collection(FirestoreCollections.businesses)
          .doc(businessId)
          .get();
      if (!businessDoc.exists) {
        throw const AppException('The selected business no longer exists.');
      }
      final ownerId = (businessDoc.data()?['ownerId'] ?? '').toString();
      if (ownerId.isEmpty) {
        throw const AppException(
          'This business has not been configured correctly.',
        );
      }
      if (ownerId == uid) {
        throw const AppException(
          'You cannot send a deal to your own business.',
        );
      }

      final now = DateTime.now().millisecondsSinceEpoch;
      final ref = _deals.doc();
      final id = ref.id;

      final resolvedTerms = terms.trim().isEmpty
          ? 'This deal is a proposed business agreement between the '
              'participating businesses. Both parties agree to complete the '
              'transaction according to the details recorded in DealBridge.'
          : terms.trim();

      final deal = Deal(
        id: id,
        businessId: businessId,
        businessName: businessName,
        title: title.trim(),
        description: description.trim(),
        value: value.trim(),
        senderId: uid,
        senderName: senderName.trim().isEmpty ? 'DealBridge User' : senderName.trim(),
        createdAt: AppFormatters.date(DateTime.now()),
        timestamp: now,
        deadline: deadline,
        expiresAt: now + defaultDealTtlMs,
        participantIds: <String>[uid, ownerId],
        terms: resolvedTerms,
        lastActivityAt: now,
        currentStep: DealStep.reviewTerms,
      );

      await ref.set(deal.toCreateMap());
      return id;
    } on AppException {
      rethrow;
    } on FirebaseFirestoreException catch (e) {
      throw AppException(
        firestoreErrorMessage(e, 'Unable to create the deal.'),
        code: e.code,
      );
    } catch (e) {
      throw AppException(
        firestoreErrorMessage(e, 'Unable to create the deal.'),
      );
    }
  }

  // ---------------------------------------------------------------------
  // LIFECYCLE
  // ---------------------------------------------------------------------

  /// Accepts a pending deal. Only the recipient may do this.
  Future<void> acceptDeal(Deal deal) async {
    _requireRecipient(deal, 'Only the receiving party can accept this deal.');
    if (deal.status != DealStatus.pending) {
      throw const AppException('Only pending deals can be accepted.');
    }
    if (deal.isExpired) {
      throw const AppException('This deal has expired.');
    }
    await _update(deal.id, <String, dynamic>{
      'status': DealStatus.accepted,
      'lastActivityAt': _now(),
      'currentStep': DealStep.agreed,
    }, 'Unable to accept the deal.');
  }

  /// Declines a pending deal. Only the recipient may do this.
  Future<void> declineDeal(Deal deal) async {
    _requireRecipient(deal, 'Only the receiving party can decline this deal.');
    if (deal.status != DealStatus.pending) {
      throw const AppException('Only pending deals can be declined.');
    }
    await _update(deal.id, <String, dynamic>{
      'status': DealStatus.declined,
      'lastActivityAt': _now(),
    }, 'Unable to decline the deal.');
  }

  /// Moves the current user's confirmation state forward.
  ///
  /// Allowed transitions: `REVIEW_TERMS -> AGREED`, `AGREED -> CONFIRMED`
  /// and `REVIEW_TERMS -> CONFIRMED`.
  Future<void> setConfirmationStatus(
    Deal deal,
    String newStatus,
  ) async {
    final uid = _uid;
    final isSender = deal.isSender(uid);
    final isRecipient = deal.isRecipient(uid);
    if (!isSender && !isRecipient) {
      throw const AppException('You are not a participant in this deal.');
    }
    if (deal.status != DealStatus.pending &&
        deal.status != DealStatus.accepted) {
      throw const AppException('This deal can no longer be confirmed.');
    }
    if (deal.hasBothConfirmed) {
      throw const AppException(
        'Both parties have confirmed this deal; it will be completed '
        'automatically.',
      );
    }

    final current = isSender
        ? deal.senderConfirmationStatus
        : deal.recipientConfirmationStatus;
    if (current == newStatus) return;
    if (current == ConfirmationStatus.confirmed) {
      throw const AppException('You have already confirmed this deal.');
    }
    final allowed = current == ConfirmationStatus.reviewTerms
        ? newStatus == ConfirmationStatus.agreed ||
            newStatus == ConfirmationStatus.confirmed
        : newStatus == ConfirmationStatus.confirmed;
    if (!allowed) {
      throw const AppException('This deal is not ready for confirmation.');
    }

    final now = _now();
    final updates = <String, dynamic>{
      'lastActivityAt': now,
      'currentStep': newStatus == ConfirmationStatus.agreed
          ? DealStep.agreed
          : DealStep.confirmed,
    };

    if (isSender) {
      updates['senderConfirmationStatus'] = newStatus;
      updates['senderConfirmedAt'] =
          newStatus == ConfirmationStatus.confirmed ? now : 0;
      if (current == ConfirmationStatus.reviewTerms) {
        updates['senderAgreedAt'] = now;
      }
    } else {
      updates['recipientConfirmationStatus'] = newStatus;
      updates['recipientConfirmedAt'] =
          newStatus == ConfirmationStatus.confirmed ? now : 0;
      if (current == ConfirmationStatus.reviewTerms) {
        updates['recipientAgreedAt'] = now;
      }
    }

    await _update(deal.id, updates, 'Unable to update the deal.');
  }

  /// Cancels a deal through the trusted backend.
  Future<void> cancelDeal(String dealId) async {
    await _update(deal.id, <String, dynamic>{
      'status': DealStatus.cancelled,
      'lastActivityAt': _now(),
    }, 'Unable to cancel the deal.');
  }

  // ---------------------------------------------------------------------
  // HIDDEN DEALS
  // ---------------------------------------------------------------------

  /// Hides a deal from the user's list without deleting it.
  Future<void> hideDeal(String dealId) async {
    final uid = _uid;
    if (uid.isEmpty || dealId.isEmpty) return;
    await _db
        .collection(FirestoreCollections.users)
        .doc(uid)
        .collection(FirestoreCollections.hiddenDeals)
        .doc(dealId)
        .set(<String, dynamic>{
          'dealId': dealId,
          'hiddenAt': FieldValue.serverTimestamp(),
        });
  }

  /// Restores a hidden deal.
  Future<void> unhideDeal(String dealId) async {
    final uid = _uid;
    if (uid.isEmpty || dealId.isEmpty) return;
    await _db
        .collection(FirestoreCollections.users)
        .doc(uid)
        .collection(FirestoreCollections.hiddenDeals)
        .doc(dealId)
        .delete();
  }

  // ---------------------------------------------------------------------
  // HELPERS
  // ---------------------------------------------------------------------

  void _requireRecipient(Deal deal, String message) {
    if (!deal.isRecipient(_uid)) throw AppException(message);
  }

  int _now() => DateTime.now().millisecondsSinceEpoch;

  Future<void> _update(
    String dealId,
    Map<String, dynamic> updates,
    String fallbackMessage,
  ) async {
    try {
      await _deals.doc(dealId).update(updates);
    } on FirebaseFirestoreException catch (e) {
      throw AppException(
        firestoreErrorMessage(e, fallbackMessage),
        code: e.code,
      );
    } catch (e) {
      throw AppException(firestoreErrorMessage(e, fallbackMessage));
    }
  }
}
