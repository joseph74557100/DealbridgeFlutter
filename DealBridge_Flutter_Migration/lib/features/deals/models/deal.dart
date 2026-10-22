import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/utils/app_formatters.dart';

/// The canonical DealBridge deal.
///
/// `participantIds` always contains USER UIDs only:
/// `[senderUid, recipientBusinessOwnerUid]`. `businessId` is the target
/// business document id and is never a participant.
class Deal {
  const Deal({
    required this.id,
    this.businessId = '',
    this.businessName = '',
    this.title = '',
    this.description = '',
    this.value = '',
    this.senderId = '',
    this.senderName = '',
    this.status = DealStatus.pending,
    this.createdAt = '',
    this.timestamp = 0,
    this.deadline = 0,
    this.expiresAt = 0,
    this.completedAt = 0,
    this.acceptedAt = 0,
    this.completedDate = '',
    this.flagged = false,
    this.flagReasons = const <String>[],
    this.flaggedAt = 0,
    this.participantIds = const <String>[],
    this.disputeStatus = '',
    this.disputeId = '',
    this.senderConfirmationStatus = ConfirmationStatus.reviewTerms,
    this.senderAgreedAt = 0,
    this.senderConfirmedAt = 0,
    this.recipientConfirmationStatus = ConfirmationStatus.reviewTerms,
    this.recipientAgreedAt = 0,
    this.recipientConfirmedAt = 0,
    this.terms = '',
    this.lastActivityAt = 0,
    this.currentStep = DealStep.reviewTerms,
  });

  final String id;
  final String businessId;
  final String businessName;
  final String title;
  final String description;
  final String value;
  final String senderId;
  final String senderName;
  final String status;
  final String createdAt;
  final int timestamp;
  final int deadline;
  final int expiresAt;
  final int completedAt;
  final int acceptedAt;
  final String completedDate;
  final bool flagged;
  final List<String> flagReasons;
  final int flaggedAt;
  final List<String> participantIds;
  final String disputeStatus;
  final String disputeId;
  final String senderConfirmationStatus;
  final int senderAgreedAt;
  final int senderConfirmedAt;
  final String recipientConfirmationStatus;
  final int recipientAgreedAt;
  final int recipientConfirmedAt;
  final String terms;
  final int lastActivityAt;
  final int currentStep;

  bool get isExpired =>
      expiresAt > 0 && expiresAt <= DateTime.now().millisecondsSinceEpoch;

  bool get hasBothConfirmed =>
      senderConfirmationStatus == ConfirmationStatus.confirmed &&
      recipientConfirmationStatus == ConfirmationStatus.confirmed;

  bool get hasBothAgreed =>
      senderConfirmationStatus == ConfirmationStatus.agreed &&
      recipientConfirmationStatus == ConfirmationStatus.agreed;

  bool get hasOpenDispute => disputeStatus == 'Open';

  /// The counterpart business name for the current user.
  String counterpartyName(String currentUid) {
    if (senderId == currentUid) return businessName;
    return senderName;
  }

  /// The status label shown to the current user.
  String displayStatusFor(String currentUid) {
    if (status == DealStatus.pending && senderId == currentUid) {
      return 'Awaiting Approval';
    }
    switch (status) {
      case DealStatus.pending:
        return 'Pending';
      case DealStatus.accepted:
        return 'Accepted';
      case DealStatus.active:
        return 'Active';
      case DealStatus.completed:
        return 'Completed';
      case DealStatus.declined:
        return 'Declined';
      case DealStatus.cancelled:
        return 'Cancelled';
      case DealStatus.expired:
        return 'Expired';
      case DealStatus.flagged:
        return 'Under Review';
      default:
        return status;
    }
  }

  /// The current user's own confirmation state.
  String confirmationFor(String currentUid) =>
      senderId == currentUid ? senderConfirmationStatus : recipientConfirmationStatus;

  /// The current user's own confirmation timestamp.
  int confirmedAtFor(String currentUid) =>
      senderId == currentUid ? senderConfirmedAt : recipientConfirmedAt;

  bool isParticipant(String uid) => participantIds.contains(uid);

  bool isSender(String uid) => senderId == uid;

  bool isRecipient(String uid) =>
      uid != senderId && participantIds.contains(uid);

  /// Timestamp used for sorting: most recent activity wins.
  int get sortTimestamp => lastActivityAt > 0 ? lastActivityAt : timestamp;

  factory Deal.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const <String, dynamic>{};
    return Deal(
      id: doc.id,
      businessId: _string(data['businessId']),
      businessName: _string(data['businessName']),
      title: _string(data['title']),
      description: _string(data['description']),
      value: _string(data['value'] ?? data['amount']),
      senderId: _string(data['senderId']),
      senderName: _string(data['senderName']),
      status: _string(data['status'], fallback: DealStatus.pending),
      createdAt: _string(data['createdAt']),
      timestamp: _long(data['timestamp']),
      deadline: _long(data['deadline']),
      expiresAt: _long(data['expiresAt']),
      completedAt: _long(data['completedAt']),
      acceptedAt: _long(data['acceptedAt']),
      completedDate: _string(data['completedDate']),
      flagged: data['flagged'] == true,
      flagReasons: _stringList(data['flagReasons']),
      flaggedAt: _long(data['flaggedAt']),
      participantIds: _stringList(data['participantIds']),
      disputeStatus: _string(data['disputeStatus']),
      disputeId: _string(data['disputeId']),
      senderConfirmationStatus: _string(
        data['senderConfirmationStatus'],
        fallback: ConfirmationStatus.reviewTerms,
      ),
      senderAgreedAt: _long(data['senderAgreedAt']),
      senderConfirmedAt: _long(data['senderConfirmedAt']),
      recipientConfirmationStatus: _string(
        data['recipientConfirmationStatus'],
        fallback: ConfirmationStatus.reviewTerms,
      ),
      recipientAgreedAt: _long(data['recipientAgreedAt']),
      recipientConfirmedAt: _long(data['recipientConfirmedAt']),
      terms: _string(data['terms']),
      lastActivityAt: _long(data['lastActivityAt']),
      currentStep: _int(data['currentStep'], fallback: DealStep.reviewTerms),
    );
  }

  /// Builds the create payload. Field names mirror the Kotlin repository so
  /// the backend and rules see exactly what they expect.
  Map<String, dynamic> toCreateMap() {
    return <String, dynamic>{
      'id': id,
      'businessId': businessId,
      'businessName': businessName,
      'title': title,
      'description': description,
      'value': value,
      'senderId': senderId,
      'senderName': senderName,
      'status': DealStatus.pending,
      'createdAt': createdAt,
      'timestamp': timestamp,
      'deadline': deadline,
      'expiresAt': expiresAt,
      'participantIds': participantIds,
      'senderConfirmationStatus': ConfirmationStatus.reviewTerms,
      'senderAgreedAt': 0,
      'senderConfirmedAt': 0,
      'recipientConfirmationStatus': ConfirmationStatus.reviewTerms,
      'recipientAgreedAt': 0,
      'recipientConfirmedAt': 0,
      'terms': terms,
      'lastActivityAt': lastActivityAt,
      'currentStep': DealStep.reviewTerms,
    };
  }

  Deal copyWith({
    String? status,
    String? senderConfirmationStatus,
    String? recipientConfirmationStatus,
    int? currentStep,
    int? lastActivityAt,
    int? senderAgreedAt,
    int? senderConfirmedAt,
    int? recipientAgreedAt,
    int? recipientConfirmedAt,
  }) {
    return Deal(
      id: id,
      businessId: businessId,
      businessName: businessName,
      title: title,
      description: description,
      value: value,
      senderId: senderId,
      senderName: senderName,
      status: status ?? this.status,
      createdAt: createdAt,
      timestamp: timestamp,
      deadline: deadline,
      expiresAt: expiresAt,
      completedAt: completedAt,
      acceptedAt: acceptedAt,
      completedDate: completedDate,
      flagged: flagged,
      flagReasons: flagReasons,
      flaggedAt: flaggedAt,
      participantIds: participantIds,
      disputeStatus: disputeStatus,
      disputeId: disputeId,
      senderConfirmationStatus:
          senderConfirmationStatus ?? this.senderConfirmationStatus,
      senderAgreedAt: senderAgreedAt ?? this.senderAgreedAt,
      senderConfirmedAt: senderConfirmedAt ?? this.senderConfirmedAt,
      recipientConfirmationStatus:
          recipientConfirmationStatus ?? this.recipientConfirmationStatus,
      recipientAgreedAt: recipientAgreedAt ?? this.recipientAgreedAt,
      recipientConfirmedAt: recipientConfirmedAt ?? this.recipientConfirmedAt,
      terms: terms,
      lastActivityAt: lastActivityAt ?? this.lastActivityAt,
      currentStep: currentStep ?? this.currentStep,
    );
  }

  /// A human readable expiry date, `null` when no deadline exists.
  String? get expiryLabel => AppFormatters.fromEpoch(expiresAt);

  static String _string(dynamic value, {String fallback = ''}) {
    if (value == null) return fallback;
    final text = value.toString().trim();
    return text.isEmpty ? fallback : text;
  }

  static int _long(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is Timestamp) return value.toDate().millisecondsSinceEpoch;
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }

  static int _int(dynamic value, {int fallback = 0}) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? fallback;
    return fallback;
  }

  static List<String> _stringList(dynamic value) {
    if (value is List) {
      return value.whereType<String>().toList(growable: false);
    }
    return const <String>[];
  }
}
