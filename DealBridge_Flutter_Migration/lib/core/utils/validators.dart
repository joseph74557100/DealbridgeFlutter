/// Form-field validators shared across sign-in, registration and forms.
abstract final class Validators {
  static String? email(String? value) {
    final text = (value ?? '').trim();
    if (text.isEmpty) return 'Enter your email address';
    final pattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
    if (!pattern.hasMatch(text)) return 'Enter a valid email address';
    return null;
  }

  static String? password(String? value) {
    final text = value ?? '';
    if (text.isEmpty) return 'Enter a password';
    if (text.length < 6) return 'Use at least 6 characters';
    return null;
  }

  static String? strongPassword(String? value) {
    final text = value ?? '';
    if (text.length < 8) return 'Use at least 8 characters';
    if (!text.contains(RegExp(r'[A-Za-z]'))) {
      return 'Include at least one letter';
    }
    if (!text.contains(RegExp(r'[0-9]'))) {
      return 'Include at least one number';
    }
    return null;
  }

  static String? required(String? value, {String field = 'This field'}) {
    if ((value ?? '').trim().isEmpty) return '$field is required';
    return null;
  }

  static String? optionalEmail(String? value) {
    if ((value ?? '').trim().isEmpty) return null;
    return email(value);
  }

  static String? phone(String? value) {
    final text = (value ?? '').trim();
    if (text.isEmpty) return null;
    if (text.replaceAll(RegExp(r'[\s+\-()]'), '').length < 6) {
      return 'Enter a valid phone number';
    }
    return null;
  }

  static String? website(String? value) {
    final text = (value ?? '').trim();
    if (text.isEmpty) return null;
    final uri = Uri.tryParse(text);
    if (uri == null || !uri.hasScheme || !uri.hasAuthority) {
      return 'Enter a full URL, e.g. https://example.com';
    }
    return null;
  }
}
