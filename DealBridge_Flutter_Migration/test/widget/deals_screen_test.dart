import 'package:dealbridge_flutter/core/constants/app_constants.dart';
import 'package:dealbridge_flutter/core/theme/app_theme.dart';
import 'package:dealbridge_flutter/features/deals/data/deal_repository.dart';
import 'package:dealbridge_flutter/features/deals/deals_screen.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/test_firebase.dart';

void main() {
  setUpAll(() async {
    await installTestFirebase();
  });

  late FakeFirebaseFirestore firestore;
  late DealRepository repository;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    repository = DealRepository(
      firestore: firestore,
      auth: FirebaseAuth.instance,
    );
  });

  Future<void> seedDeal({
    required String id,
    required String title,
    String status = DealStatus.pending,
  }) async {
    await firestore.collection(FirestoreCollections.deals).doc(id).set(
      <String, dynamic>{
        'title': title,
        'businessId': 'business-1',
        'businessName': 'Acme',
        'senderId': 'someone-else',
        'senderName': 'Ada',
        'status': status,
        'participantIds': <String>['someone-else', testUid],
        'timestamp': 1767225600000,
        'lastActivityAt': 1767225600000,
        'value': 'R10,000',
      },
    );
  }

  Future<void> pumpScreen(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: DealsScreen(repository: repository),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('lists the deals of the signed-in user', (tester) async {
    await seedDeal(id: 'deal-1', title: 'Steel supply');
    await seedDeal(
      id: 'deal-2',
      title: 'Fleet services',
      status: DealStatus.accepted,
    );
    await pumpScreen(tester);

    expect(find.text('Steel supply'), findsOneWidget);
    expect(find.text('Fleet services'), findsOneWidget);
  });

  testWidgets('filters the list by status', (tester) async {
    await seedDeal(id: 'deal-1', title: 'Steel supply');
    await seedDeal(
      id: 'deal-2',
      title: 'Fleet services',
      status: DealStatus.accepted,
    );
    await pumpScreen(tester);

    await tester.tap(find.widgetWithText(ChoiceChip, DealStatus.accepted));
    await tester.pumpAndSettle();

    expect(find.text('Fleet services'), findsOneWidget);
    expect(find.text('Steel supply'), findsNothing);
  });

  testWidgets('shows an empty state when there are no deals', (tester) async {
    await pumpScreen(tester);

    expect(find.text('No deals yet'), findsOneWidget);
  });
}
