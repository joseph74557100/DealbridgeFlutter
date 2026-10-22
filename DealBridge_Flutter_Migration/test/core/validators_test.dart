import 'package:dealbridge_flutter/core/utils/validators.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Validators.email', () {
    test('rejects empty input', () {
      expect(Validators.email(''), isNotNull);
      expect(Validators.email(null), isNotNull);
      expect(Validators.email('   '), isNotNull);
    });

    test('rejects malformed addresses', () {
      expect(Validators.email('nope'), isNotNull);
      expect(Validators.email('missing@domain'), isNotNull);
      expect(Validators.email('two@@example.com'), isNotNull);
      expect(Validators.email('spaces in@example.com'), isNotNull);
    });

    test('accepts valid addresses and trims them', () {
      expect(Validators.email('user@example.com'), isNull);
      expect(Validators.email('  user@example.com  '), isNull);
    });
  });

  group('Validators.password', () {
    test('requires at least six characters', () {
      expect(Validators.password(''), isNotNull);
      expect(Validators.password('12345'), isNotNull);
      expect(Validators.password('123456'), isNull);
    });
  });

  group('Validators.strongPassword', () {
    test('requires eight characters, a letter and a digit', () {
      expect(Validators.strongPassword('short1'), isNotNull);
      expect(Validators.strongPassword('12345678'), isNotNull);
      expect(Validators.strongPassword('abcdefgh'), isNotNull);
      expect(Validators.strongPassword('abcdefg1'), isNull);
    });
  });

  group('Validators.required', () {
    test('reports the field name', () {
      expect(Validators.required('', field: 'Full name'), 'Full name is required');
      expect(Validators.required('  ', field: 'Full name'),
          'Full name is required');
      expect(Validators.required('Ada', field: 'Full name'), isNull);
    });
  });

  group('Validators.optionalEmail', () {
    test('allows empty values but validates present ones', () {
      expect(Validators.optionalEmail(''), isNull);
      expect(Validators.optionalEmail('bad'), isNotNull);
      expect(Validators.optionalEmail('user@example.com'), isNull);
    });
  });

  group('Validators.phone', () {
    test('allows empty values and rejects short numbers', () {
      expect(Validators.phone(''), isNull);
      expect(Validators.phone('12345'), isNotNull);
      expect(Validators.phone('+27 11 555 1234'), isNull);
    });
  });

  group('Validators.website', () {
    test('requires a full URL when present', () {
      expect(Validators.website(''), isNull);
      expect(Validators.website('example.com'), isNotNull);
      expect(Validators.website('https://example.com'), isNull);
    });
  });
}
