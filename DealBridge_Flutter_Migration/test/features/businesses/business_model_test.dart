import 'package:dealbridge_flutter/core/constants/app_constants.dart';
import 'package:dealbridge_flutter/features/businesses/models/business.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Business', () {
    test('only shows the verified badge when the server confirmed it', () {
      const unverified = Business(id: 'b1', verified: false, verificationLevel: 0);
      expect(unverified.isGenuinelyVerified, isFalse);

      const flaggedOnly = Business(id: 'b1', verified: true, verificationLevel: 0);
      expect(flaggedOnly.isGenuinelyVerified, isFalse);

      const verified = Business(id: 'b1', verified: true, verificationLevel: 2);
      expect(verified.isGenuinelyVerified, isTrue);
    });

    test('flags suspended and disabled businesses', () {
      const suspended = Business(id: 'b1', businessStatus: 'Suspended');
      expect(suspended.isSuspended, isTrue);

      const disabled = Business(id: 'b1', businessStatus: 'disabled');
      expect(disabled.isSuspended, isTrue);

      const active = Business(id: 'b1', businessStatus: 'Active');
      expect(active.isSuspended, isFalse);
    });

    test('creates a payload with the server-owned defaults', () {
      const business = Business(
        id: 'b1',
        ownerId: 'owner-1',
        name: 'Acme',
        category: 'Retail',
        city: 'Cape Town',
      );

      final payload = business.toCreateMap();

      expect(payload['id'], 'b1');
      expect(payload['ownerId'], 'owner-1');
      expect(payload['trustScore'], 50);
      expect(payload['verificationLevel'], 0);
      expect(payload['verified'], isFalse);
      expect(payload['rating'], 0);
      expect(payload['ratingCount'], 0);
      expect(payload['promoted'], isFalse);
      expect(payload['completedDeals'], 0);
      expect(payload['disputeCount'], 0);
      expect(payload['reportCount'], 0);
      expect(payload.containsKey('createdAt'), isTrue);
    });

    test('updates only the editable fields', () {
      const business = Business(
        id: 'b1',
        ownerId: 'owner-1',
        name: 'Acme',
        rating: 4.5,
        verified: true,
      );

      final payload = business.toUpdateMap();

      expect(payload.keys, containsAll(<String>['name', 'category', 'city']));
      expect(payload.containsKey('rating'), isFalse);
      expect(payload.containsKey('verified'), isFalse);
      expect(payload.containsKey('trustScore'), isFalse);
      expect(payload.containsKey('ownerId'), isFalse);
    });
  });

  group('BusinessRating', () {
    test('parses the fields written by the rating form', () {
      const rating = BusinessRating(
        id: 'r1',
        raterId: 'user-1',
        stars: 5,
        dealId: 'deal-1',
        comment: 'Great partner',
        userName: 'Ada',
      );

      expect(rating.stars, 5);
      expect(rating.dealId, 'deal-1');
      expect(rating.comment, 'Great partner');
      expect(rating.userName, 'Ada');
    });
  });

  group('DealStatus', () {
    test('only exposes the client writable statuses', () {
      expect(DealStatus.clientWritable, <String>[
        DealStatus.pending,
        DealStatus.accepted,
        DealStatus.declined,
      ]);
    });
  });
}
