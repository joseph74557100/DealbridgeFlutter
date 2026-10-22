import 'package:dealbridge_flutter/core/constants/app_constants.dart';
import 'package:dealbridge_flutter/features/deals/models/deal.dart';
import 'package:flutter_test/flutter_test.dart';

Deal buildDeal({
  String id = 'deal-1',
  String senderId = 'sender-1',
  String businessId = 'business-1',
  String businessName = 'Acme',
  String status = DealStatus.pending,
  String senderConfirmationStatus = ConfirmationStatus.reviewTerms,
  String recipientConfirmationStatus = ConfirmationStatus.reviewTerms,
  List<String>? participantIds,
  int timestamp = 1767225600000,
  int expiresAt = 0,
}) {
  return Deal(
    id: id,
    senderId: senderId,
    senderName: 'Ada',
    businessId: businessId,
    businessName: businessName,
    title: 'Supply agreement',
    status: status,
    participantIds: participantIds ??
        <String>[senderId, 'owner-1'],
    senderConfirmationStatus: senderConfirmationStatus,
    recipientConfirmationStatus: recipientConfirmationStatus,
    timestamp: timestamp,
    expiresAt: expiresAt,
  );
}

void main() {
  group('Deal', () {
    test('reports the counterparty for each participant', () {
      final deal = buildDeal();
      expect(deal.counterpartyName('sender-1'), 'Acme');
      expect(deal.counterpartyName('owner-1'), 'Ada');
    });

    test('labels the status for the current user', () {
      final pending = buildDeal();
      expect(pending.displayStatusFor('sender-1'), 'Awaiting Approval');
      expect(pending.displayStatusFor('owner-1'), 'Pending');

      expect(
        buildDeal(status: DealStatus.accepted).displayStatusFor('sender-1'),
        'Accepted',
      );
      expect(
        buildDeal(status: DealStatus.completed).displayStatusFor('owner-1'),
        'Completed',
      );
      expect(
        buildDeal(status: DealStatus.cancelled).displayStatusFor('owner-1'),
        'Cancelled',
      );
    });

    test('identifies participants, senders and recipients', () {
      final deal = buildDeal();
      expect(deal.isParticipant('owner-1'), isTrue);
      expect(deal.isParticipant('someone-else'), isFalse);
      expect(deal.isSender('sender-1'), isTrue);
      expect(deal.isRecipient('owner-1'), isTrue);
      expect(deal.isRecipient('sender-1'), isFalse);
    });

    test('tracks the confirmation state per participant', () {
      final deal = buildDeal(
        senderConfirmationStatus: ConfirmationStatus.confirmed,
        recipientConfirmationStatus: ConfirmationStatus.agreed,
      );
      expect(deal.confirmationFor('sender-1'), ConfirmationStatus.confirmed);
      expect(deal.confirmationFor('owner-1'), ConfirmationStatus.agreed);
      expect(deal.hasBothConfirmed, isFalse);

      final both = buildDeal(
        senderConfirmationStatus: ConfirmationStatus.confirmed,
        recipientConfirmationStatus: ConfirmationStatus.confirmed,
      );
      expect(both.hasBothConfirmed, isTrue);
    });

    test('detects expiry', () {
      final expired = buildDeal(
        expiresAt: DateTime.now().millisecondsSinceEpoch - 1000,
      );
      expect(expired.isExpired, isTrue);

      final live = buildDeal(
        expiresAt: DateTime.now().millisecondsSinceEpoch + 60000,
      );
      expect(live.isExpired, isFalse);

      expect(buildDeal().isExpired, isFalse);
    });

    test('uses the most recent activity for sorting', () {
      expect(buildDeal(timestamp: 100).sortTimestamp, 100);
    });

    test('builds a create payload that satisfies the Firestore rules', () {
      final payload = buildDeal().toCreateMap();

      expect(payload['status'], DealStatus.pending);
      expect(payload['participantIds'], <String>['sender-1', 'owner-1']);
      expect(payload['senderConfirmationStatus'], ConfirmationStatus.reviewTerms);
      expect(
        payload['recipientConfirmationStatus'],
        ConfirmationStatus.reviewTerms,
      );
      expect(payload['currentStep'], DealStep.reviewTerms);
      expect(payload['businessId'], 'business-1');
    });
  });
}
