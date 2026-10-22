import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/test_firebase.dart';

void main() {
  setUpAll(() async {
    await installTestFirebase();
  });

  test('the fake auth platform reports the signed-in user', () {
    expect(FirebaseAuth.instance.currentUser?.uid, testUid);
  });

  test('the fake firestore accepts writes and reads', () async {
    final firestore = createFakeFirestore();
    await firestore.collection('businesses').doc('b1').set(<String, dynamic>{
      'name': 'Acme',
    });
    final doc = await firestore.collection('businesses').doc('b1').get();
    expect(doc.data()?['name'], 'Acme');
  });
}
