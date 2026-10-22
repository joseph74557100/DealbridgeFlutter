const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { onDocumentCreated, onDocumentWritten } = require("firebase-functions/v2/firestore");
const { onSchedule } = require("firebase-functions/v2/scheduler");
const admin = require("firebase-admin");

/**
 * Session and security management Cloud Functions.
 *
 * - validateSession: server-side session validation before sensitive actions
 * - recordSecurityEvent: logs security-relevant events (login, sign-out, etc.)
 * - detectSuspiciousActivity: scheduled function that scans for anomalies
 * - onSessionCreated: indexes sessions and checks for suspicious patterns
 */

const REAUTH_WINDOW_MS = 5 * 60 * 1000; // 5 minutes
const UNUSUAL_LOGIN_START_HOUR = 1;  // 1 AM
const UNUSUAL_LOGIN_END_HOUR = 5;    // 5 AM

/**
 * Checks whether a user has authenticated recently enough for a
 * sensitive action. Call this from any Cloud Function that should
 * require recent re-authentication.
 */
async function requireRecentAuth(uid) {
  const snapshot = await admin.firestore().collection("users").doc(uid).get();
  if (!snapshot.exists) {
    throw new HttpsError("not-found", "User document not found");
  }
  const data = snapshot.data();
  const lastReauth = data.lastReauthenticatedAt || 0;

  if (lastReauth === 0 || Date.now() - lastReauth > REAUTH_WINDOW_MS) {
    throw new HttpsError(
      "failed-precondition",
      "Recent authentication required. Please re-authenticate before performing this action."
    );
  }
}

/**
 * Callable: validateSession
 *
 * Called by the client before performing a sensitive action.
 * Verifies that the user's session is still valid and that
 * they have authenticated recently.
 */
exports.validateSession = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "Must be signed in");
  }

  const sessionId = request.data?.sessionId;
  if (!sessionId) {
    throw new HttpsError("invalid-argument", "Session ID required");
  }

  // Check session exists and is not revoked
  const sessionDoc = await admin
    .firestore()
    .collection("users")
    .doc(uid)
    .collection("sessions")
    .doc(sessionId)
    .get();

  if (!sessionDoc.exists) {
    throw new HttpsError("not-found", "Session not found or revoked");
  }

  // Check session version
  const userDoc = await admin.firestore().collection("users").doc(uid).get();
  const userData = userDoc.exists ? userDoc.data() : {};
  const currentVersion = userData.sessionVersion || 1;
  const sessionData = sessionDoc.data();
  const sessionVersion = sessionData.sessionVersion || 1;

  if (sessionVersion < currentVersion) {
    throw new HttpsError(
      "failed-precondition",
      "Session revoked. Please sign in again."
    );
  }

  // Update last active
  await admin
    .firestore()
    .collection("users")
    .doc(uid)
    .collection("sessions")
    .doc(sessionId)
    .update({ lastActive: Date.now() });

  return { valid: true, sessionVersion: currentVersion };
});

/**
 * Callable: recordSecurityEvent
 *
 * Logs a security-relevant event to the user's security log.
 * Used for tracking logins, sign-outs, password changes, etc.
 */
exports.recordSecurityEvent = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "Must be signed in");
  }

  const eventType = request.data?.eventType;
  const details = request.data?.details || {};

  if (!eventType) {
    throw new HttpsError("invalid-argument", "Event type required");
  }

  const validEvents = [
    "login",
    "logout",
    "sign_out_all",
    "password_changed",
    "email_changed",
    "security_question_set",
    "two_factor_enabled",
    "two_factor_disabled",
    "account_deletion_requested",
    "sensitive_action_performed",
    "session_revoked",
    "suspicious_activity_detected"
  ];

  if (!validEvents.includes(eventType)) {
    throw new HttpsError("invalid-argument", `Invalid event type: ${eventType}`);
  }

  await admin
    .firestore()
    .collection("users")
    .doc(uid)
    .collection("securityLog")
    .add({
      eventType,
      details,
      timestamp: admin.firestore.FieldValue.serverTimestamp(),
      ipAddress: request.rawRequest?.ip || "unknown",
      userAgent: request.rawRequest?.headers?.["user-agent"] || "unknown"
    });

  return { success: true };
});

/**
 * Callable: recordReauthentication
 *
 * Records that the user has recently re-authenticated (e.g. after
 * entering their password). This is checked before sensitive actions.
 */
exports.recordReauthentication = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "Must be signed in");
  }

  await admin
    .firestore()
    .collection("users")
    .doc(uid)
    .update({
      lastReauthenticatedAt: Date.now()
    });

  return { success: true };
});

/**
 * Callable: signOutDevice
 *
 * Revokes a specific device session. Cannot revoke the caller's
 * own session (use signOut for that).
 */
exports.signOutDevice = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "Must be signed in");
  }

  const targetSessionId = request.data?.sessionId;
  if (!targetSessionId) {
    throw new HttpsError("invalid-argument", "Session ID required");
  }

  const callerSessionId = request.data?.callerSessionId;
  if (targetSessionId === callerSessionId) {
    throw new HttpsError(
      "failed-precondition",
      "Cannot revoke your own active session. Use sign out instead."
    );
  }

  // Delete the target session
  const sessionRef = admin
    .firestore()
    .collection("users")
    .doc(uid)
    .collection("sessions")
    .doc(targetSessionId);

  const sessionDoc = await sessionRef.get();
  if (!sessionDoc.exists) {
    throw new HttpsError("not-found", "Session not found");
  }

  await sessionRef.delete();

  // Log the event
  await admin
    .firestore()
    .collection("users")
    .doc(uid)
    .collection("securityLog")
    .add({
      eventType: "session_revoked",
      details: {
        revokedSessionId: targetSessionId,
        deviceName: sessionDoc.data().deviceName || "Unknown"
      },
      timestamp: admin.firestore.FieldValue.serverTimestamp(),
      ipAddress: request.rawRequest?.ip || "unknown",
      userAgent: request.rawRequest?.headers?.["user-agent"] || "unknown"
    });

  return { success: true };
});

/**
 * Callable: revokeAllSessions
 *
 * Bumps the sessionVersion on the user document, which invalidates
 * all existing sessions. Used for "sign out all devices".
 */
exports.revokeAllSessions = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "Must be signed in");
  }

  const userRef = admin.firestore().collection("users").doc(uid);
  const userDoc = await userRef.get();
  const currentVersion = userDoc.exists ? (userDoc.data().sessionVersion || 1) : 1;
  const newVersion = currentVersion + 1;

  // Bump session version
  await userRef.update({ sessionVersion: newVersion });

  // Delete all session documents
  const sessionsSnapshot = await admin
    .firestore()
    .collection("users")
    .doc(uid)
    .collection("sessions")
    .get();

  const batch = admin.firestore().batch();
  sessionsSnapshot.docs.forEach((doc) => batch.delete(doc.ref));
  await batch.commit();

  // Log the event
  await admin
    .firestore()
    .collection("users")
    .doc(uid)
    .collection("securityLog")
    .add({
      eventType: "sign_out_all",
      details: { newSessionVersion: newVersion },
      timestamp: admin.firestore.FieldValue.serverTimestamp(),
      ipAddress: request.rawRequest?.ip || "unknown",
      userAgent: request.rawRequest?.headers?.["user-agent"] || "unknown"
    });

  return { success: true, newSessionVersion: newVersion };
});

/**
 * onSessionCreated: trigger when a new session document is written.
 * Logs the event and checks for suspicious patterns.
 */
exports.onSessionCreated = onDocumentWritten(
  "users/{uid}/sessions/{sessionId}",
  async (event) => {
    const { uid, sessionId } = event.params;
    const snapshot = event.data?.after;

    // Only process creates (not updates or deletes)
    if (!event.data?.before?.exists && snapshot?.exists) {
      const sessionData = snapshot.data();

      // Log the new session
      await admin
        .firestore()
        .collection("users")
        .doc(uid)
        .collection("securityLog")
        .add({
          eventType: "login",
          details: {
            sessionId,
            deviceName: sessionData.deviceName || "Unknown",
            platform: sessionData.platform || "Android",
            appVersion: sessionData.appVersion || ""
          },
          timestamp: admin.firestore.FieldValue.serverTimestamp(),
          ipAddress: sessionData.ipAddress || "unknown",
          userAgent: sessionData.userAgent || "unknown"
        });

      // Check for suspicious patterns
      await checkSuspiciousPatterns(uid, sessionId);
    }

    return null;
  }
);

/**
 * Checks for suspicious login patterns:
 * - Multiple logins from different locations in short time
 * - Unusual login time (e.g. 2 AM in user's local time)
 * - Excessive session count
 */
async function checkSuspiciousPatterns(uid, newSessionId) {
  try {
    const sessionsSnapshot = await admin
      .firestore()
      .collection("users")
      .doc(uid)
      .collection("sessions")
      .get();

    const sessions = sessionsSnapshot.docs.map((doc) => ({
      id: doc.id,
      ...doc.data()
    }));

    // Check for excessive sessions (more than 5 active sessions)
    if (sessions.length > 5) {
      await logSuspiciousActivity(uid, "excessive_sessions", {
        sessionCount: sessions.length,
        newSessionId
      });
    }

    // Check for rapid session creation (3+ sessions in 5 minutes)
    const fiveMinAgo = Date.now() - 5 * 60 * 1000;
    const recentSessions = sessions.filter(
      (s) => (s.loginTimestamp || s.lastActive || 0) > fiveMinAgo
    );
    if (recentSessions.length >= 3) {
      await logSuspiciousActivity(uid, "rapid_session_creation", {
        recentCount: recentSessions.length,
        newSessionId
      });
    }

    // Check for unusual login time (1 AM - 5 AM local time)
    // Use the new session's timezone if available, otherwise fall back to user profile
    const newSession = sessions.find(s => s.id === newSessionId);
    let userTimezone = newSession?.timezone || "UTC";

    // Try to get timezone from user profile if not in session
    if (userTimezone === "UTC") {
      const userDoc = await admin.firestore().collection("users").doc(uid).get();
      if (userDoc.exists) {
        userTimezone = userDoc.data().timezone || "UTC";
      }
    }

    // Calculate hour in user's timezone
    const now = new Date();
    const userHour = getHourInTimezone(now, userTimezone);

    if (userHour >= UNUSUAL_LOGIN_START_HOUR && userHour <= UNUSUAL_LOGIN_END_HOUR) {
      await logSuspiciousActivity(uid, "unusual_login_time", {
        hour: userHour,
        timezone: userTimezone,
        newSessionId
      });
    }
  } catch (error) {
    console.warn("Suspicious pattern check failed", { uid, error: error.message });
  }
}

/**
 * Gets the hour (0-23) in the specified timezone.
 * Uses Intl.DateTimeFormat for proper timezone handling.
 */
function getHourInTimezone(date, timezone) {
  try {
    // Use a formatter with the specified timezone
    const formatter = new Intl.DateTimeFormat('en-US', {
      timeZone: timezone,
      hour: 'numeric',
      hour12: false
    });
    return parseInt(formatter.format(date), 10);
  } catch (e) {
    // Fallback to UTC if timezone is invalid
    console.warn("Invalid timezone, falling back to UTC", { timezone, error: e.message });
    return date.getUTCHours();
  }
}

/**
 * Logs a suspicious activity event.
 */
async function logSuspiciousActivity(uid, type, details) {
  await admin
    .firestore()
    .collection("users")
    .doc(uid)
    .collection("securityLog")
    .add({
      eventType: "suspicious_activity_detected",
      details: { type, ...details },
      timestamp: admin.firestore.FieldValue.serverTimestamp(),
      severity: "warning"
    });
}

/**
 * Scheduled: detectSuspiciousActivity
 * Runs hourly to scan for suspicious patterns across all users.
 */
exports.detectSuspiciousActivity = onSchedule("every 1 hours", async () => {
  const oneHourAgo = Date.now() - 60 * 60 * 1000;
  const fiveMinAgo = Date.now() - 5 * 60 * 1000;

  try {
    // Find users with recent activity
    const usersSnapshot = await admin.firestore().collection("users").get();

    for (const userDoc of usersSnapshot.docs) {
      const uid = userDoc.id;

      // Check for users with too many security events in the last hour
      const securityLog = await admin
        .firestore()
        .collection("users")
        .doc(uid)
        .collection("securityLog")
        .where("timestamp", ">=", admin.firestore.Timestamp.fromDate(new Date(oneHourAgo)))
        .get();

      const eventTypes = securityLog.docs.map((doc) => doc.data().eventType);

      // Alert if multiple suspicious events in the last hour
      const suspiciousCount = eventTypes.filter(
        (type) => type === "suspicious_activity_detected"
      ).length;
      if (suspiciousCount >= 3) {
        console.warn("Multiple suspicious events detected", {
          uid,
          count: suspiciousCount
        });
      }
    }
  } catch (error) {
    console.warn("Scheduled suspicious activity scan failed", error.message);
  }
});

exports.requireRecentAuth = requireRecentAuth;
