import 'package:dealbridge_flutter/core/constants/app_constants.dart';
import 'package:dealbridge_flutter/core/theme/app_theme.dart';
import 'package:dealbridge_flutter/features/auth/data/user_repository.dart';
import 'package:dealbridge_flutter/features/businesses/data/business_repository.dart';
import 'package:dealbridge_flutter/features/deals/data/deal_repository.dart';
import 'package:dealbridge_flutter/features/deals/propose_deal_screen.dart';
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
  late DealRepository deals;
  late BusinessRepository businesses;
  late UserRepository users;

  setUp(() async {
    firestore = FakeFirebaseFirestore();
    deals = DealRepository(firestore: firestore, auth: FirebaseAuth.instance);
    businesses = BusinessRepository(
      firestore: firestore,
      auth: FirebaseAuth.instance,
    );
    users = UserRepository(firestore: firestore, auth: FirebaseAuth.instance);

    await firestore.collection(FirestoreCollections.businesses).doc('b1').set(
      <String, dynamic>{'name': 'Acme Trading', 'ownerId': 'someone-else'},
    );
    await firestore.collection(FirestoreCollections.users).doc(testUid).set(
      <String, dynamic>{'id': testUid, 'fullName': 'Ada Lovelace'},
    );
  });

  Future<void> pumpScreen(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: ProposeDealScreen(
          dealRepository: deals,
          businessRepository: businesses,
          userRepository: users,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('requires a business, title and description', (tester) async {
    await pumpScreen(tester);

    await tester.tap(find.text('Send deal'));
    await tester.pumpAndSettle();

    expect(find.text('Select a business'), findsWidgets);
    expect(find.text('Deal title is required'), findsOneWidget);
    expect(find.text('A description is required'), findsOneWidget);
  });

  testWidgets('writes the deal for the selected business', (tester) async {
    await pumpScreen(tester);

    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Acme Trading').last);
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Deal title'),
      'Steel supply',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'What are you offering?'),
      '100 tonnes of steel',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Deal value (optional)'),
      'R50,000',
    );

    await tester.tap(find.text('Send deal'));
    await tester.pumpAndSettle();

    final snapshot = await firestore
        .collection(FirestoreCollections.deals)
        .get();
    expect(snapshot.docs, hasLength(1));

    final data = snapshot.docs.first.data();
    expect(data['title'], 'Steel supply');
    expect(data['value'], 'R50,000');
    expect(data['senderName'], 'Ada Lovelace');
    expect(data['participantIds'], <String>[testUid, 'someone-else']);
    expect(data['status'], DealStatus.pending);
  });
}
