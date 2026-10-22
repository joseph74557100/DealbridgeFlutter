import 'package:dealbridge_flutter/features/agreements/models/agreement.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Agreement', () {
    test('exposes the agreement status constants', () {
      expect(AgreementStatus.pendingSignature, 'Pending Signature');
      expect(AgreementStatus.signed, 'Signed');
      expect(AgreementStatus.archived, 'Archived');
      expect(AgreementStatus.expired, 'Expired');
    });

    test('knows when the agreement is signed', () {
      const pending = Agreement(id: 'a1');
      expect(pending.isSigned, isFalse);
      expect(pending.status, AgreementStatus.pendingSignature);

      const signed = Agreement(id: 'a1', status: AgreementStatus.signed);
      expect(signed.isSigned, isTrue);
    });

    test('knows when a document is attached', () {
      expect(const Agreement(id: 'a1').hasDocument, isFalse);
      expect(
        const Agreement(id: 'a1', pdfUrl: 'https://example.com/a.pdf')
            .hasDocument,
        isTrue,
      );
      expect(
        const Agreement(id: 'a1', localPdfPath: '/tmp/a.pdf').hasDocument,
        isTrue,
      );
    });

    test('parses signatures', () {
      const signature = AgreementSignature(
        businessId: 'b1',
        businessName: 'Acme',
        signerUserId: 'user-1',
        signedDate: '03 Feb 2026',
        signedTime: '02:05 PM',
      );

      expect(signature.businessName, 'Acme');
      expect(signature.signedDate, '03 Feb 2026');
      expect(signature.signedTime, '02:05 PM');
    });

    test('exposes a readable creation date', () {
      final millis = DateTime(2026, 2, 3).millisecondsSinceEpoch;
      final agreement = Agreement(id: 'a1', createdAt: millis);
      expect(agreement.createdLabel, '03 Feb 2026');

      expect(const Agreement(id: 'a1').createdLabel, isNull);
    });
  });
}
