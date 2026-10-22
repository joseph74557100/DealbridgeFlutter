import 'package:dealbridge_flutter/core/constants/app_constants.dart';
import 'package:dealbridge_flutter/core/theme/app_theme.dart';
import 'package:dealbridge_flutter/features/agreements/agreements_screen.dart';
import 'package:dealbridge_flutter/features/agreements/data/agreement_repository.dart';
import 'package:dealbridge_flutter/features/agreements/models/agreement.dart';
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
  late AgreementRepository repository;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    repository = AgreementRepository(
      firestore: firestore,
      auth: FirebaseAuth.instance,
    );
  });

  Future<void> seedAgreement({
    required String id,
    required String title,
    String status = AgreementStatus.signed,
  }) async {
    await firestore.collection(FirestoreCollections.agreements).doc(id).set(
      <String, dynamic>{
        'agreementId': id,
        'title': title,
        'businessOneName': 'Acme',
        'businessTwoName': 'Zeta',
        'participantIds': <String>['someone-else', testUid],
        'createdAt': 1767225600000,
        'status': status,
      },
    );
  }

  Future<void> pumpScreen(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: AgreementsScreen(repository: repository),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('lists the agreements of the signed-in user', (tester) async {
    await seedAgreement(id: 'a1', title: 'Steel supply agreement');
    await pumpScreen(tester);

    expect(find.text('Steel supply agreement'), findsOneWidget);
    expect(find.text('Acme • Zeta'), findsOneWidget);
    expect(find.text('Signed'), findsOneWidget);
  });

  testWidgets('shows an empty state when there are no agreements',
      (tester) async {
    await pumpScreen(tester);

    expect(find.text('No agreements yet'), findsOneWidget);
  });
}
