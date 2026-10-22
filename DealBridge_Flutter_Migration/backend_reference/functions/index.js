const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { onDocumentCreated } = require("firebase-functions/v2/firestore");
const { setGlobalOptions } = require("firebase-functions/v2");
const admin = require("firebase-admin");
const crypto = require("crypto");
const cloudinary = require("cloudinary");

admin.initializeApp();

// Pin the deployment region so every onCall/onDocument/onSchedule handler in
// this codebase is served from the SAME region the Android client targets
// (FirebaseFunctions.getInstance(FirebaseApp, "us-central1")). Defaults are
// us-central1 on both sides, but making it explicit prevents a silent
// region/project mismatch that surfaces to callers as 401/unknown API.
setGlobalOptions({ region: "us-central1" });

// OneSignal credentials. The REST API key is a server-side secret and must be
// provided via the ONESIGNAL_REST_API_KEY environment variable when deploying
// (`firebase functions:secrets:set ONESIGNAL_REST_API_KEY`). The app id is the
// same value already embedded in the Android client. Do NOT commit secrets.
// Warn (don't throw) when the key is missing so deploys without push still
// work; throw only on the critical send path if ever required.
if (!process.env.ONESIGNAL_REST_API_KEY) console.warn("ONESIGNAL_REST_API_KEY is not set; push notifications will be skipped.");
const ONESIGNAL_APP_ID =
  process.env.ONESIGNAL_APP_ID || "30da6324-74cd-4c1c-9abe-cfe0887a8a2e";
const ONESIGNAL_REST_API_KEY = process.env.ONESIGNAL_REST_API_KEY || "";

function messagePreview(message) {
  switch (message.type) {
    case "voice":
      return "🎤 Voice message";
    case "image":
      return "📷 Photo";
    case "video":
      return "🎬 Video";
    case "pdf":
      return "📄 Document";
    case "agreement":
      return "📑 Agreement document";
    case "deal":
      return "📊 Deal";
    case "location":
      return "📍 Location";
    case "contact":
      return "👤 Contact card";
    default:
      return (message.text || "").slice(0, 200);
  }
}

/**
 * Resolves the display name of a DealBridge user from their public profile.
 * The client-supplied name on the message is not trusted as the source of
 * truth; the profile is authoritative. Falls back to the stamped name and
 * finally to a neutral label.
 */
async function resolveUserDisplayName(uid, fallback) {
  if (!uid) return fallback;
  try {
    const snapshot = await admin.firestore().collection("users").doc(uid).get();
    const fullName = (snapshot.exists ? snapshot.data().fullName : "") || "";
    if (fullName.trim()) return fullName.trim().split(" ")[0] || fullName.trim();
  } catch (_) {
    // Fall through to the fallback.
  }
  if (fallback && fallback.trim() && fallback !== "You") return fallback;
  return "New message";
}

/**
 * Resolves the authoritative name of a business (used as the notification
 * title for business-to-business messages).
 */
async function resolveBusinessName(businessId, fallback) {
  if (!businessId) return fallback || "Business";
  try {
    const snapshot = await admin.firestore().collection("businesses").doc(businessId).get();
    const name = (snapshot.exists ? snapshot.data().name : "") || "";
    if (name.trim()) return name.trim();
  } catch (_) {
    // Fall through to the fallback.
  }
  if (fallback && fallback.trim()) return fallback;
  return "Business";
}

/**
 * Android notification channel used for all DealBridge message pushes. The
 * channel itself is created by the Android app ("DealBridge Messages"), so the
 * Cloud Function only has to reference its id in the payload.
 */
const MESSAGE_CHANNEL_ID = "dealbridge_messages";

/**
 * Sends a push notification to a DealBridge account.
 *
 * The recipient is targeted by OneSignal *external id* (the Firebase uid),
 * which is what `OneSignal.login(uid)` associates on the device. That covers
 * every device the account is signed into and makes logout clean: when a user
 * signs out, `OneSignal.logout()` removes the association so that device stops
 * receiving pushes for the account.
 *
 * Everything that could fail is swallowed: a failed push must never break the
 * chat write that triggered it.
 */
async function sendOneSignal(externalId, title, body, data) {
  if (!externalId) return false;
  if (!ONESIGNAL_REST_API_KEY) {
    console.warn("Push skipped: ONESIGNAL_REST_API_KEY is not configured");
    return false;
  }

  try {
    const response = await fetch("https://api.onesignal.com/notifications", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Basic ${ONESIGNAL_REST_API_KEY}`
      },
      body: JSON.stringify({
        app_id: ONESIGNAL_APP_ID,
        include_aliases: { external_id: [externalId] },
        target_channel: "push",
        android_channel_id: MESSAGE_CHANNEL_ID,
        headings: { en: title },
        contents: { en: body },
        data
      })
    });
    if (!response.ok) {
      console.warn("Push request failed", { externalId, status: response.status });
      return false;
    }
    console.log("Push request successful", {
      externalId,
      type: data.notificationType,
      messageId: data.messageId,
      conversationId: data.conversationId
    });
    return true;
  } catch (error) {
    console.warn("Push request error", { externalId, message: error.message });
    return false;
  }
}

/**
 * Per-account message notification preferences, stored on `users/{uid}`.
 * The Android settings screen writes these; both default to enabled.
 */
async function notificationSettingsOf(uid) {
  if (!uid) return { personalMessagesEnabled: true, businessMessagesEnabled: true };
  const snapshot = await admin.firestore().collection("users").doc(uid).get();
  const settings = snapshot.exists ? snapshot.data().notificationSettings || {} : {};
  return {
    personalMessagesEnabled: settings.personalMessagesEnabled !== false,
    businessMessagesEnabled: settings.businessMessagesEnabled !== false
  };
}

/**
 * Resolves the thread participants, preferring the stamped message copy and
 * falling back to the thread document (authoritative).
 */
async function participantsOf(collectionName, threadId, message) {
  if (message.participantIds && message.participantIds.length >= 2) {
    return message.participantIds.filter(Boolean);
  }
  const snapshot = await admin
    .firestore()
    .doc(`${collectionName}/${threadId}`)
    .get();
  const data = snapshot.exists ? snapshot.data() : {};
  return (data.participantIds || []).filter(Boolean);
}

/**
 * Atomically marks a message as notified so Cloud Function retries never
 * produce a duplicate push. Returns true when the push should be sent.
 */
async function claimMessage(messageRef) {
  return admin.firestore().runTransaction(async (transaction) => {
    const snapshot = await transaction.get(messageRef);
    if (snapshot.exists && snapshot.data().pushNotified) return false;
    transaction.set(
      messageRef,
      {
        pushNotified: true,
        pushNotifiedAt: admin.firestore.FieldValue.serverTimestamp()
      },
      { merge: true }
    );
    return true;
  });
}

/**
 * Sends a push notification to the owner of the business that received a
 * company-to-company chat message.
 */
exports.onBusinessChatMessage = onDocumentCreated(
  "businessChats/{threadId}/messages/{messageId}",
  async (event) => {
    const snapshot = event.data;
    if (!snapshot) return;
    const message = snapshot.data();
    if (!message || message.deleted) return;

    const { threadId, messageId } = event.params;
    const messageRef = admin.firestore().doc(`businessChats/${threadId}/messages/${messageId}`);

    try {
      const participants = participantsOf("businessChats", threadId, message);
      const senderId = message.senderId;
      if (!senderId || !participants.includes(senderId)) return;

      const recipientBusinessId = participants.find((id) => id !== senderId);
      if (!recipientBusinessId) return;

      // Recipient must be a real business, and the sender must represent a
      // real business too. Never trust the client for these ids; everything
      // is cross-checked against the businesses collection.
      const [recipientBusiness, senderBusiness] = await Promise.all([
        admin.firestore().collection("businesses").doc(recipientBusinessId).get(),
        admin.firestore().collection("businesses").doc(senderId).get()
      ]);
      if (!recipientBusiness.exists || !senderBusiness.exists) return;

      const ownerUid = recipientBusiness.data().ownerId;
      if (!ownerUid) return;

      // Never notify a user about a message their own business sent (e.g. a
      // chat between two businesses owned by the same account).
      if (senderBusiness.data().ownerId === ownerUid) return;

      const settings = await notificationSettingsOf(ownerUid);
      if (!settings.businessMessagesEnabled) return;

      if (!(await claimMessage(messageRef))) return;

      const senderBusinessName = await resolveBusinessName(
        senderId,
        message.senderName || "Business"
      );

      console.log("Push notification recipient resolved", {
        threadId,
        messageId,
        recipientUid: ownerUid,
        recipientBusinessId
      });

      await sendOneSignal(
        ownerUid,
        `🏢 ${senderBusinessName}`,
        messagePreview(message),
        {
          notificationType: "business_message",
          scope: "business",
          messageId,
          conversationId: threadId,
          threadId,
          senderId,
          recipientId: recipientBusinessId,
          businessId: recipientBusinessId,
          dealId: message.dealId || "",
          timestamp: message.timestamp || 0,
          type: message.type || "text"
        }
      );
    } catch (error) {
      console.warn("Business chat push skipped", { threadId, messageId }, error.message);
    }
  }
);

/**
 * Sends a push notification for a new one-to-one personal chat message.
 */
exports.onPersonalChatMessage = onDocumentCreated(
  "personalChats/{threadId}/messages/{messageId}",
  async (event) => {
    const snapshot = event.data;
    if (!snapshot) return;
    const message = snapshot.data();
    if (!message || message.deleted) return;

    const { threadId, messageId } = event.params;
    const messageRef = admin.firestore().doc(`personalChats/${threadId}/messages/${messageId}`);

    try {
      const participants = await participantsOf("personalChats", threadId, message);
      const senderId = message.senderId;
      if (!senderId || !participants.includes(senderId)) return;

      const recipientId = participants.find((id) => id !== senderId);
      if (!recipientId) return;

      // The recipient must be a real, existing account. Reading their profile
      // also gives us their per-account notification preferences below.
      const recipientSnapshot = await admin
        .firestore()
        .collection("users")
        .doc(recipientId)
        .get();
      if (!recipientSnapshot.exists) return;

      const settings = await notificationSettingsOf(recipientId);
      if (!settings.personalMessagesEnabled) return;

      if (!(await claimMessage(messageRef))) return;

      const senderName = await resolveUserDisplayName(senderId, message.senderName);

      console.log("Push notification recipient resolved", {
        threadId,
        messageId,
        recipientUid: recipientId
      });

      await sendOneSignal(
        recipientId,
        `💬 ${senderName}`,
        messagePreview(message),
        {
          notificationType: "personal_message",
          scope: "personal",
          messageId,
          conversationId: threadId,
          threadId,
          senderId,
          recipientId,
          businessId: "",
          dealId: message.dealId || "",
          timestamp: message.timestamp || 0,
          type: message.type || "text"
        }
      );
    } catch (error) {
      console.warn("Personal chat push skipped", { threadId, messageId }, error.message);
    }
  }
);

const SECURITY_ANSWER_SALT =
  process.env.SECURITY_ANSWER_SALT || "dealbridge-security-v1";

if (!process.env.SECURITY_ANSWER_SALT) {
  console.warn("SECURITY_ANSWER_SALT is not set; using the default salt. Set a strong secret to protect security-answer hashes.");
}

// Rate limits for the unauthenticated password-reset flow. These endpoints
// accept only an email address (and, for resetPassword, a security answer),
// so without limits an attacker could brute-force the answer for a victim's
// account. Counters live in the securityCounters collection, keyed by email.
const RESET_QUESTION_RATE_LIMIT = 8;
const RESET_PASSWORD_RATE_LIMIT = 5;
const RESET_RATE_WINDOW_MS = 10 * 60 * 1000;

function normalizeAnswer(answer) {
  return answer.trim().replace(/\s+/g, " ").toLowerCase();
}

function hashSecurityAnswer(answer) {
  return crypto
    .createHash("sha256")
    .update(`${SECURITY_ANSWER_SALT}:${normalizeAnswer(answer)}`)
    .digest("hex");
}

async function getUserByEmail(email) {
  try {
    return await admin.auth().getUserByEmail(email);
  } catch (error) {
    throw new HttpsError("not-found", "No account found with this email");
  }
}

/**
 * Sliding-window rate limiter persisted in securityCounters. Throws
 * resource-exhausted when `limit` attempts are exceeded within `windowMs`.
 * Callers swallow non-HttpsError failures (e.g. transient write errors) so a
 * rate-limit hiccup can never block a legitimate action.
 */
async function enforceRateLimit(key, limit, windowMs, actor) {
  const ref = admin.firestore().collection("securityCounters").doc(key);
  await admin.firestore().runTransaction(async (transaction) => {
    const snap = await transaction.get(ref);
    const now = Date.now();
    const prev = snap.exists ? (snap.data() || {}) : {};
    let count = prev.count || 0;
    if (now - (prev.windowStart || 0) >= windowMs) count = 0;
    count += 1;
    transaction.set(
      ref,
      { action: key, actor: actor || "", count, windowStart: now },
      { merge: true }
    );
    if (count > limit) {
      throw new HttpsError(
        "resource-exhausted",
        "Too many attempts. Please try again later."
      );
    }
  });
}

async function getSecurityData(uid) {
  const snapshot = await admin.firestore().collection("users").doc(uid).get();
  const data = snapshot.exists ? snapshot.data() : {};
  return {
    question: data.securityQuestion || null,
    answerHash: data.securityAnswerHash || null
  };
}

exports.saveSecurityQuestion = onCall(async (request) => {
  const uid = request.auth?.uid;

  if (!uid) {
    throw new HttpsError(
      "unauthenticated",
      "You must be signed in to set a security question"
    );
  }

  // Rate limit: max 3 security question changes per user per 10 minutes
  const SECURITY_QUESTION_RATE_LIMIT = 3;
  const SECURITY_QUESTION_WINDOW_MS = 10 * 60 * 1000;
  const rateRef = admin.firestore().collection("securityCounters").doc(`security-question_${uid}`);
  try {
    await admin.firestore().runTransaction(async (transaction) => {
      const snap = await transaction.get(rateRef);
      const now = Date.now();
      const prev = snap.exists ? (snap.data() || {}) : {};
      let count = prev.count || 0;
      if (now - (prev.windowStart || 0) >= SECURITY_QUESTION_WINDOW_MS) {
        count = 0;
      }
      count += 1;
      transaction.set(rateRef, {
        action: "security-question",
        actor: uid,
        count,
        windowStart: now
      }, { merge: true });
      if (count > SECURITY_QUESTION_RATE_LIMIT) {
        throw new HttpsError("resource-exhausted", "Too many security question changes. Please try again later.");
      }
    });
  } catch (error) {
    if (error instanceof HttpsError) throw error;
    console.warn("Rate limit check failed; allowing action", { action: "security-question", actor: uid, message: error.message });
  }

  const question = request.data?.question?.toString().trim();
  const answer = request.data?.answer?.toString();

  if (!question || !answer) {
    throw new HttpsError(
      "invalid-argument",
      "Security question and answer are required"
    );
  }

  if (answer.length < 2) {
    throw new HttpsError(
      "invalid-argument",
      "Security answer must be at least 2 characters"
    );
  }

  await admin
    .firestore()
    .collection("users")
    .doc(uid)
    .set(
      {
        securityQuestion: question,
        securityAnswerHash: hashSecurityAnswer(answer)
      },
      { merge: true }
    );

  return { success: true };
});

exports.getResetQuestion = onCall(async (request) => {
  const email = request.data?.email?.toString().trim().toLowerCase();

  if (!email) {
    throw new HttpsError("invalid-argument", "Email is required");
  }

  // Unauthenticated endpoint: rate-limit per email before doing anything else
  // so the security question cannot be ground out for a victim's account.
  try {
    await enforceRateLimit(`reset-question_${email}`, RESET_QUESTION_RATE_LIMIT, RESET_RATE_WINDOW_MS, "anonymous");
  } catch (error) {
    if (error instanceof HttpsError) throw error;
    console.warn("Rate limit check failed; allowing getResetQuestion", { email, message: error.message });
  }

  const user = await getUserByEmail(email);
  const { question } = await getSecurityData(user.uid);

  if (!question) {
    throw new HttpsError(
      "failed-precondition",
      "This account does not have a security question set up"
    );
  }

  return { question };
});

exports.resetPassword = onCall(async (request) => {
  const email = request.data?.email?.toString().trim().toLowerCase();
  const answer = request.data?.answer?.toString();
  const newPassword = request.data?.newPassword?.toString();

  if (!email || !answer || !newPassword) {
    throw new HttpsError(
      "invalid-argument",
      "Missing email, security answer or new password"
    );
  }

  if (newPassword.length < 6) {
    throw new HttpsError(
      "invalid-argument",
      "Password must be at least 6 characters"
    );
  }

  // Unauthenticated endpoint: strict per-email attempt limit so the security
  // answer cannot be brute-forced into a password reset.
  try {
    await enforceRateLimit(`reset-password_${email}`, RESET_PASSWORD_RATE_LIMIT, RESET_RATE_WINDOW_MS, "anonymous");
  } catch (error) {
    if (error instanceof HttpsError) throw error;
    console.warn("Rate limit check failed; allowing resetPassword", { email, message: error.message });
  }

  const user = await getUserByEmail(email);
  const { question, answerHash } = await getSecurityData(user.uid);

  if (!question || !answerHash) {
    throw new HttpsError(
      "failed-precondition",
      "This account does not have a security question set up"
    );
  }

  if (hashSecurityAnswer(answer) !== answerHash) {
    throw new HttpsError("unauthenticated", "Incorrect security answer");
  }

  await admin.auth().updateUser(user.uid, { password: newPassword });

  return { success: true };
});

const { deleteAccount, adminDeleteUser } = require("./accountDeletion");
exports.deleteAccount = deleteAccount;
exports.adminDeleteUser = adminDeleteUser;

// Deal & agreement security: server-verified deal completion, the triggered
// agreement lifecycle and the append-only audit trail.
const {
  onAgreementUpdated,
  onDealCreated,
  onDealUpdated,
  onAgreementCreated,
  onUserCreated,
  autoCompleteConfirmedDeal,
  repairStuckConfirmedDeals,
  cancelDeal,
  searchUsers
} = require("./transactions");

exports.onAgreementUpdated = onAgreementUpdated;
exports.onDealCreated = onDealCreated;
exports.onDealUpdated = onDealUpdated;
exports.onAgreementCreated = onAgreementCreated;
exports.onUserCreated = onUserCreated;
exports.autoCompleteConfirmedDeal = autoCompleteConfirmedDeal;
exports.repairStuckConfirmedDeals = repairStuckConfirmedDeals;
exports.cancelDeal = cancelDeal;
exports.searchUsers = searchUsers;

// Business trust score, verification and deal dispute systems.
const {
  processVerificationRequest,
  rejectVerificationRequest,
  onDealCompletedRecalculateTrust,
  fileDealDispute,
  resolveDealDispute
} = require("./trustAndDisputes");

exports.processVerificationRequest = processVerificationRequest;
exports.rejectVerificationRequest = rejectVerificationRequest;
exports.onDealCompletedRecalculateTrust = onDealCompletedRecalculateTrust;
exports.fileDealDispute = fileDealDispute;
exports.resolveDealDispute = resolveDealDispute;

// Session management, security event logging and suspicious activity detection.
const {
  validateSession,
  recordSecurityEvent,
  recordReauthentication,
  signOutDevice,
  revokeAllSessions,
  onSessionCreated,
  detectSuspiciousActivity
} = require("./sessions");

exports.validateSession = validateSession;
exports.recordSecurityEvent = recordSecurityEvent;
exports.recordReauthentication = recordReauthentication;
exports.signOutDevice = signOutDevice;
exports.revokeAllSessions = revokeAllSessions;
exports.onSessionCreated = onSessionCreated;
exports.detectSuspiciousActivity = detectSuspiciousActivity;

// Business ratings — recomputes the parent business's rating/ratingCount on
// every rating write (validated client-side by Firestore rules first).
const {
  onRatingWritten
} = require("./ratings");

exports.onRatingWritten = onRatingWritten;

// Chat media cleanup — removes temporary transfer files from Cloudinary
// after recipients have downloaded them locally.
const {
  cleanupOldChatMedia,
  markMediaDelivered
} = require("./cleanupChatMedia");

exports.cleanupOldChatMedia = cleanupOldChatMedia;
exports.markMediaDelivered = markMediaDelivered;

// Secure Cloudinary media deletion — validates ownership before deleting
// assets. The Android client calls this when replacing or removing media.
const {
  deleteCloudinaryMedia
} = require("./deleteCloudinaryMedia");

exports.deleteCloudinaryMedia = deleteCloudinaryMedia;
