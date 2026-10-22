import 'package:dealbridge_flutter/core/constants/app_constants.dart';
import 'package:dealbridge_flutter/core/theme/app_theme.dart';
import 'package:dealbridge_flutter/features/businesses/business_details_screen.dart';
import 'package:dealbridge_flutter/features/businesses/data/business_repository.dart';
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
  late BusinessRepository repository;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    repository = BusinessRepository(
      firestore: firestore,
      auth: FirebaseAuth.instance,
    );
  });

  Future<void> seedBusiness({
    String id = 'business-1',
    String ownerId = 'someone-else',
    String name = 'Acme Trading',
  }) async {
    await firestore.collection(FirestoreCollections.businesses).doc(id).set(
      <String, dynamic>{
        'name': name,
        'category': 'Retail',
        'city': 'Cape Town',
        'description': 'Hardware and tools',
        'phone': '+27 11 555 1234',
        'email': 'hello@acme.co',
        'website': 'https://acme.co',
        'ownerId': ownerId,
        'rating': 4.5,
        'ratingCount': 2,
      },
    );
  }

  Future<void> pumpScreen(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: BusinessDetailsScreen(
          businessId: 'business-1',
          repository: repository,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('shows the business profile', (tester) async {
    await seedBusiness();
    await pumpScreen(tester);

    expect(find.text('Acme Trading'), findsWidgets);
    expect(find.text('Retail'), findsOneWidget);
    expect(find.text('Cape Town'), findsOneWidget);
    expect(find.text('Hardware and tools'), findsOneWidget);
    expect(find.text('+27 11 555 1234'), findsOneWidget);
  });

  testWidgets('offers the deal proposal to other members', (tester) async {
    await seedBusiness();
    await pumpScreen(tester);

    expect(find.text('Propose a deal'), findsOneWidget);
    expect(find.text('This is your business.'), findsNothing);
  });

  testWidgets('shows the owner actions for the owner', (tester) async {
    await seedBusiness(ownerId: testUid);
    await pumpScreen(tester);

    expect(find.text('This is your business.'), findsOneWidget);
    expect(find.text('Edit details'), findsOneWidget);
    expect(find.text('Request verification'), findsOneWidget);
    expect(find.text('Propose a deal'), findsNothing);
  });

  testWidgets('reports a missing business', (tester) async {
    await pumpScreen(tester);

    expect(find.text('Business not found'), findsOneWidget);
  });
}
