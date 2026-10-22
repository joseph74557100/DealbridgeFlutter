/// Canonical Firestore collection names and server contract literals.
///
/// Every value here mirrors the deployed backend (`backend_reference/firestore.rules`
/// and `backend_reference/functions/`). Never change a literal without changing
/// the backend first: the client is validated by Firestore security rules.
abstract final class FirestoreCollections {
  static const users = 'users';
  static const businesses = 'businesses';
  static const deals = 'deals';
  static const agreements = 'agreements';
  static const notifications = 'notifications';
  static const newsfeed = 'newsfeed';
  static const stories = 'stories';
  static const personalChats = 'personalChats';
  static const businessChats = 'businessChats';
  static const savedBusinesses = 'savedBusinesses';
  static const savedPosts = 'savedPosts';
  static const hiddenDeals = 'hiddenDeals';
  static const followedUsers = 'followedUsers';
  static const verificationRequests = 'verificationRequests';
  static const dealDisputes = 'dealDisputes';
  static const supportRequests = 'supportRequests';
  static const problemReports = 'problemReports';
  static const featureRequests = 'featureRequests';
  static const businessReports = 'businessReports';
  static const userReports = 'userReports';
  static const postReports = 'postReports';
  static const messageReports = 'messageReports';
  static const conversations = 'conversations';
  static const sessions = 'sessions';
  static const securityLog = 'securityLog';
  static const admins = 'admins';
}

/// Deal lifecycle values.
abstract final class DealStatus {
  static const pending = 'PENDING';
  static const accepted = 'ACCEPTED';
  static const active = 'ACTIVE';
  static const signing = 'SIGNING';
  static const completed = 'COMPLETED';
  static const declined = 'DECLINED';
  static const cancelled = 'CANCELLED';
  static const expired = 'EXPIRED';
  static const flagged = 'Flagged';

  static const clientWritable = <String>[pending, accepted, declined];

  static const filterTabs = <String>[
    'All',
    pending,
    accepted,
    active,
    completed,
    declined,
    expired,
  ];
}

/// Two-party agreement confirmation lifecycle.
abstract final class ConfirmationStatus {
  static const reviewTerms = 'REVIEW_TERMS';
  static const agreed = 'AGREED';
  static const confirmed = 'CONFIRMED';

  static const order = <String>[reviewTerms, agreed, confirmed];
}

/// Deal `currentStep` progress markers.
abstract final class DealStep {
  static const reviewTerms = 1;
  static const agreed = 2;
  static const confirmed = 3;
  static const completed = 4;
}

/// Exact reason literals accepted by the `fileDealDispute` callable.
abstract final class DisputeReasons {
  static const values = <String>[
    'Non-Delivery',
    'Quality Issue',
    'Terms Violation',
    'Fraud',
    'Communication Failure',
    'Payment Dispute',
    'Other',
  ];
}

/// Event types accepted by the `recordSecurityEvent` callable.
abstract final class SecurityEventTypes {
  static const values = <String>[
    'login',
    'logout',
    'sign_out_all',
    'password_changed',
    'email_changed',
    'security_question_set',
    'two_factor_enabled',
    'two_factor_disabled',
    'account_deletion_requested',
    'sensitive_action_performed',
    'session_revoked',
    'suspicious_activity_detected',
  ];
}

/// Default deal validity period: 30 days.
const int defaultDealTtlMs = 30 * 24 * 60 * 60 * 1000;

/// Cloud Functions region. `setGlobalOptions` pins every function to
/// `us-central1`, so the client must target it explicitly.
const String functionsRegion = 'us-central1';

/// Cloudinary delivery/upload configuration.
abstract final class CloudinaryConfig {
  static const cloudName = 'mgkl4otj';
  static const uploadPreset = 'dealbridge_media';

  static String uploadUrl(String resourceType) =>
      'https://api.cloudinary.com/v1_1/$cloudName/$resourceType/upload';

  static String deliveryUrl(String resourceType, String publicId) =>
      'https://res.cloudinary.com/$cloudName/$resourceType/upload/$publicId';
}

/// Cloudinary public-id folder prefixes. The `deleteCloudinaryMedia` callable
/// derives ownership from these segments, so they must match exactly.
abstract final class CloudinaryFolders {
  static String user(String uid) => 'dealbridge/users/$uid';
  static String business(String businessId) => 'dealbridge/businesses/$businessId';
  static String post() => 'dealbridge/posts/${DateTime.now().millisecondsSinceEpoch}';
  static String story(String uid) => 'dealbridge/stories/$uid';
  static const chatMedia = 'dealbridge/chat_media';
  static const support = 'dealbridge/support';
}

/// Business categories offered when creating or filtering businesses.
const List<String> businessCategories = <String>[
  'General',
  'Agriculture',
  'Construction',
  'Consulting',
  'Education',
  'Energy',
  'Finance',
  'Food & Beverage',
  'Health',
  'Hospitality',
  'IT & Software',
  'Logistics',
  'Manufacturing',
  'Media',
  'Mining',
  'Real Estate',
  'Retail',
  'Security',
  'Technology',
  'Transport',
  'Travel',
  'Wholesale',
];
