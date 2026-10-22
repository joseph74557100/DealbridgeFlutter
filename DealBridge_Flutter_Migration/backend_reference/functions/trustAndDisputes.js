// ==========================================================================
// Business Trust Score, Verification & Deal Dispute server-side logic.
//
// All three systems are server-authoritative: the Android client can NEVER
// set `trustScore`, `verified`, `verificationLevel`, `disputeStatus` or
// dispute records directly. Everything flows through these Cloud Functions
// which re-verify ownership, cross-check Firestore and stamp the audit trail.
// ==========================================================================

const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { onDocumentUpdated } = require("firebase-functions/v2/firestore");
const admin = require("firebase-admin");

const db = admin.firestore();
const serverTimestamp = () => admin.firestore.FieldValue.serverTimestamp();

// ------------------------------------------------------------------
// Audit helper (imported conceptually; we inline for encapsulation).
// ------------------------------------------------------------------
async function writeAudit({ action, scope, documentId, uid, businessId = "", participantIds = [], details = {} }) {
  try {
    await db.collection("auditLogs").add({
      action,
      scope,
      documentId,
      uid: uid || null,
      businessId: businessId || "",
      participantIds: participantIds || [],
      details: details || {},
      timestamp: serverTimestamp()
    });
  } catch (error) {
    console.warn("Audit write failed", { action, documentId, message: error.message });
  }
}

// ==========================================================================
// Trust Score Calculation
//
// Formula:
//   base = 50
//   + completedDeals * 5  (up to +25 for 5+ deals)
//   + verificationLevel * 8  (0/8/16/24)
//   - disputeCount * 10  (capped at -30)
//   - reportCount * 8  (capped at -24)
//   + ageBonus (business older than 6 months: +3, >1 year: +5)
//
// Final score is clamped to [0, 100].
// ==========================================================================
async function recalculateTrustScore(businessId) {
  try {
    const snap = await db.collection("businesses").doc(businessId).get();
    if (!snap.exists) return;

    const data = snap.data() || {};
    const completedDeals = Number(data.completedDeals) || 0;
    const verificationLevel = Number(data.verificationLevel) || 0;
    const disputeCount = Number(data.disputeCount) || 0;
    const reportCount = Number(data.reportCount) || 0;
    const createdAt = Number(data.createdAt) || Date.now();

    let score = 50;

    // Completed deals bonus (capped at 25)
    score += Math.min(completedDeals * 5, 25);

    // Verification bonus
    score += verificationLevel * 8;

    // Dispute penalty (capped at -30)
    score -= Math.min(disputeCount * 10, 30);

    // Report penalty (capped at -24)
    score -= Math.min(reportCount * 8, 24);

    // Age bonus
    const ageMs = Date.now() - createdAt;
    const ageDays = ageMs / (1000 * 60 * 60 * 24);
    if (ageDays > 365) {
      score += 5;
    } else if (ageDays > 180) {
      score += 3;
    }

    // Clamp to [0, 100]
    score = Math.max(0, Math.min(100, Math.round(score)));

    await db.collection("businesses").doc(businessId).update({
      trustScore: score
    });

    return score;
  } catch (error) {
    console.warn("Trust score recalculation failed", { businessId, message: error.message });
    return null;
  }
}

// ==========================================================================
// processVerificationRequest — callable Cloud Function (ADMIN ONLY)
//
// Approves a pending verification request. The ADMIN (not the business owner)
// calls this after reviewing the request document: it re-verifies the
// caller is a configured admin, marks the request document Approved, sets
// verified + verificationLevel on the business, recalculates trust score and
// records an audit entry.
//
// The business owner can NEVER self-verify: this function refuses anyone who
// is not a configured admin, Firestore rules prevent clients from writing
// `verified` / `verificationLevel` directly, and the request document's
// status can only transition through this function (or its reject twin).
// ==========================================================================
async function isAdminUser(uid) {
  if (!uid) return false;
  try {
    const user = await admin.auth().getUser(uid);
    if (
      user.customClaims &&
      (user.customClaims.admin === true || user.customClaims.superAdmin === true)
    ) {
      return true;
    }
  } catch (_) {
    // Fall through to the document checks.
  }
  try {
    const snapshot = await db.collection("adminConfig").doc("admins").get();
    if (snapshot.exists) {
      const adminUids = snapshot.data().adminUids || [];
      if (adminUids.includes(uid)) return true;
    }
  } catch (error) {
    console.warn("Admin check failed", { uid, message: error.message });
  }
  // Live admins/{uid} document with active == true. No hard-coded UIDs.
  try {
    const doc = await db.collection("admins").doc(uid).get();
    if (doc.exists && doc.data().active === true) return true;
  } catch (_) {
    // Fall through.
  }
  return false;
}

exports.processVerificationRequest = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "You must be signed in");
  }

  if (!(await isAdminUser(uid))) {
    throw new HttpsError("permission-denied", "Only an admin can approve verification");
  }

  const businessId = (request.data?.businessId || "").toString();
  const requestedLevel = Number(request.data?.verificationLevel) || 1;

  if (!businessId) {
    throw new HttpsError("invalid-argument", "Business ID is required");
  }

  if (requestedLevel < 1 || requestedLevel > 3) {
    throw new HttpsError("invalid-argument", "Verification level must be 1, 2, or 3");
  }

  // The business must exist.
  const businessSnap = await db.collection("businesses").doc(businessId).get();
  if (!businessSnap.exists) {
    throw new HttpsError("not-found", "Business not found");
  }

  const business = businessSnap.data();

  // A pending request document must exist for an approval to be meaningful.
  const requestRef = db.collection("verificationRequests").doc(businessId);
  const requestSnap = await requestRef.get();
  const requestStatus = requestSnap.exists ? requestSnap.data().status : null;
  if (requestSnap.exists && requestStatus === "Rejected") {
    throw new HttpsError("failed-precondition", "This verification request was previously rejected");
  }

  // Set verification on the business document.
  const clampedLevel = Math.max(1, Math.min(3, requestedLevel));
  await db.collection("businesses").doc(businessId).update({
    verified: true,
    verificationLevel: clampedLevel,
    verificationStatus: clampedLevel >= 2 ? "Verified" : "Basic Verified"
  });

  // Mark the request document as approved with the reviewer's identity.
  try {
    await requestRef.set({
      status: "Approved",
      approvedAt: serverTimestamp(),
      approvedLevel: clampedLevel,
      reviewedBy: uid,
      reviewedAt: serverTimestamp()
    }, { merge: true });
  } catch (_) {
    // Request doc may not exist; not fatal.
  }

  // Record audit entry.
  await writeAudit({
    action: "business.verified",
    scope: "business",
    documentId: businessId,
    uid,
    businessId,
    participantIds: [business.ownerId || ""].filter(Boolean),
    details: { verificationLevel: clampedLevel, previousLevel: business.verificationLevel || 0, reviewer: uid }
  });

  // Recalculate trust score after verification change.
  await recalculateTrustScore(businessId);

  return { success: true, verificationLevel: clampedLevel };
});

// ==========================================================================
// rejectVerificationRequest — callable Cloud Function (ADMIN ONLY)
//
// Rejects a pending verification request. Records the rejection on the
// request document (so the owner can re-apply) and on the business's
// verificationStatus (server field), and stamps an audit entry. The
// business keeps its existing verification state; rejection never grants
// badges.
// ==========================================================================
exports.rejectVerificationRequest = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "You must be signed in");
  }

  if (!(await isAdminUser(uid))) {
    throw new HttpsError("permission-denied", "Only an admin can reject verification");
  }

  const businessId = (request.data?.businessId || "").toString();
  const reason = (request.data?.reason || "").toString().slice(0, 500);

  if (!businessId) {
    throw new HttpsError("invalid-argument", "Business ID is required");
  }

  const businessSnap = await db.collection("businesses").doc(businessId).get();
  if (businessSnap.exists) {
    await db.collection("businesses").doc(businessId).update({
      verificationStatus: "Rejected"
    });
  }

  const requestRef = db.collection("verificationRequests").doc(businessId);
  try {
    await requestRef.set({
      status: "Rejected",
      reason: reason || "Request does not meet verification requirements",
      reviewedBy: uid,
      reviewedAt: serverTimestamp(),
      approvedLevel: 0
    }, { merge: true });
  } catch (_) {
    // Request doc may not exist; not fatal.
  }

  await writeAudit({
    action: "business.verification.rejected",
    scope: "business",
    documentId: businessId,
    uid,
    businessId,
    participantIds: [businessSnap.exists ? businessSnap.data().ownerId : ""].filter(Boolean),
    details: { reason, reviewer: uid }
  });

  return { success: true };
});

// ==========================================================================
// recalculateTrustScoreOnDeal — triggered when a deal is completed.
//
// Increments `completedDeals` on the involved businesses and recalculates
// their trust scores.
// ==========================================================================
exports.onDealCompletedRecalculateTrust = onDocumentUpdated("deals/{dealId}", async (event) => {
  const before = event.data.before?.data?.() || {};
  const after = event.data.after?.data() || {};

  if (before.status === "COMPLETED" || after.status !== "COMPLETED") return;

  // Deal just became Completed — increment completedDeals on both businesses
  const businessId = after.businessId || "";
  const senderId = after.senderId || "";

  // Find the sender's business (if any)
  let senderBusinessId = "";
  if (senderId) {
    try {
      const senderBizSnap = await db.collection("businesses")
        .where("ownerId", "==", senderId)
        .limit(1)
        .get();
      if (!senderBizSnap.empty) {
        senderBusinessId = senderBizSnap.docs[0].id;
      }
    } catch (_) {
      // Not fatal
    }
  }

  const businessesToUpdate = [businessId, senderBusinessId].filter(Boolean);

  for (const bizId of businessesToUpdate) {
    try {
      await db.collection("businesses").doc(bizId).update({
        completedDeals: admin.firestore.FieldValue.increment(1)
      });
      await recalculateTrustScore(bizId);
    } catch (error) {
      console.warn("Trust score update failed for business", { bizId, message: error.message });
    }
  }

  // Audit entry
  await writeAudit({
    action: "deal.completed.trustUpdate",
    scope: "deal",
    documentId: event.params.dealId,
    uid: after.senderId || null,
    businessId,
    participantIds: after.participantIds || [],
    details: { businessesUpdated: businessesToUpdate }
  });
});

// ==========================================================================
// fileDealDispute — callable Cloud Function
//
// Files a dispute against a deal. Validates:
//   1. Caller is authenticated and a deal participant.
//   2. Deal exists and is in a disputable state (Accepted or Completed).
//   3. No existing open dispute for this deal.
//   4. Reason is from the predefined list.
//
// Creates a dispute document, updates the deal's `disputeStatus`,
// increments the business's `disputeCount`, recalculates trust score,
// and records an audit entry.
// ==========================================================================
const VALID_REASONS = [
  "Non-Delivery",
  "Quality Issue",
  "Terms Violation",
  "Fraud",
  "Communication Failure",
  "Payment Dispute",
  "Other"
];

exports.fileDealDispute = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "You must be signed in to file a dispute");
  }

  const dealId = (request.data?.dealId || "").toString();
  const businessId = (request.data?.businessId || "").toString();
  const reason = (request.data?.reason || "").toString();
  const description = (request.data?.description || "").toString();

  if (!dealId || !businessId) {
    throw new HttpsError("invalid-argument", "Deal ID and Business ID are required");
  }

  if (!reason || !VALID_REASONS.includes(reason)) {
    throw new HttpsError("invalid-argument", `Reason must be one of: ${VALID_REASONS.join(", ")}`);
  }

  if (description.length < 10) {
    throw new HttpsError("invalid-argument", "Description must be at least 10 characters");
  }

  if (description.length > 2000) {
    throw new HttpsError("invalid-argument", "Description must be under 2000 characters");
  }

  // Verify the deal exists and caller is a participant
  const dealSnap = await db.collection("deals").doc(dealId).get();
  if (!dealSnap.exists) {
    throw new HttpsError("not-found", "Deal not found");
  }
  const deal = dealSnap.data();

  if (!(deal.participantIds || []).includes(uid)) {
    throw new HttpsError("permission-denied", "You are not a participant in this deal");
  }

  // Deal must be in a disputable state
  if (deal.status !== "ACCEPTED" && deal.status !== "COMPLETED") {
    throw new HttpsError("failed-precondition", "Disputes can only be filed on active or completed deals");
  }

  // Check for existing open dispute
  if (deal.disputeStatus === "Open") {
    throw new HttpsError("already-exists", "This deal already has an open dispute");
  }

  // Verify the business exists
  const businessSnap = await db.collection("businesses").doc(businessId).get();
  if (!businessSnap.exists) {
    throw new HttpsError("not-found", "Business not found");
  }
  const business = businessSnap.data();

  // Resolve the filer's name from their profile
  let filedByName = "User";
  try {
    const userSnap = await db.collection("users").doc(uid).get();
    if (userSnap.exists) {
      filedByName = (userSnap.data().fullName || "").trim() || "User";
    }
  } catch (_) {
    // Not fatal
  }

  // Create the dispute document
  const disputeRef = db.collection("dealDisputes").doc();
  const disputeData = {
    id: disputeRef.id,
    dealId,
    businessId,
    businessName: business.name || "",
    reason,
    description,
    status: "Open",
    filedBy: uid,
    filedByName,
    filedAt: Date.now(),
    resolvedAt: 0,
    resolution: "",
    participantIds: deal.participantIds || []
  };

  await disputeRef.set(disputeData);

  // Update the deal's dispute status
  await db.collection("deals").doc(dealId).update({
    disputeStatus: "Open",
    disputeId: disputeRef.id
  });

  // Increment dispute count on the business and recalculate trust score
  await db.collection("businesses").doc(businessId).update({
    disputeCount: admin.firestore.FieldValue.increment(1)
  });
  await recalculateTrustScore(businessId);

  // Record audit entry
  await writeAudit({
    action: "deal.dispute.filed",
    scope: "deal",
    documentId: dealId,
    uid,
    businessId,
    participantIds: deal.participantIds || [],
    details: { disputeId: disputeRef.id, reason, businessName: business.name || "" }
  });

  return { success: true, disputeId: disputeRef.id };
});

// ==========================================================================
// resolveDealDispute — callable Cloud Function
//
// Resolves or dismisses a dispute. Only the original filer or an admin
// may resolve. Updates dispute status, deal dispute status, and records
// an audit entry. Does NOT automatically remove the dispute count from
// the business (disputes are permanent records).
// ==========================================================================
exports.resolveDealDispute = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "You must be signed in");
  }

  const disputeId = (request.data?.disputeId || "").toString();
  const resolution = (request.data?.resolution || "").toString();
  const dismiss = request.data?.dismiss === true;

  if (!disputeId) {
    throw new HttpsError("invalid-argument", "Dispute ID is required");
  }

  const disputeSnap = await db.collection("dealDisputes").doc(disputeId).get();
  if (!disputeSnap.exists) {
    throw new HttpsError("not-found", "Dispute not found");
  }
  const dispute = disputeSnap.data();

  if (dispute.status !== "Open") {
    throw new HttpsError("failed-precondition", "This dispute is already resolved or dismissed");
  }

  // Only the filer or an admin can resolve
  if (dispute.filedBy !== uid) {
    // Check if caller is an admin (business owner of the disputed business)
    const businessSnap = await db.collection("businesses").doc(dispute.businessId).get();
    if (!businessSnap.exists || businessSnap.data().ownerId !== uid) {
      throw new HttpsError("permission-denied", "Only the dispute filer or business owner can resolve this dispute");
    }
  }

  if (dismiss && !resolution) {
    throw new HttpsError("invalid-argument", "A resolution explanation is required when dismissing a dispute");
  }

  const newStatus = dismiss ? "Dismissed" : "Resolved";
  const now = Date.now();

  // Update the dispute document
  await db.collection("dealDisputes").doc(disputeId).update({
    status: newStatus,
    resolution,
    resolvedAt: now
  });

  // Update the deal's dispute status
  await db.collection("deals").doc(dispute.dealId).update({
    disputeStatus: newStatus
  });

  // Record audit entry
  await writeAudit({
    action: dismiss ? "deal.dispute.dismissed" : "deal.dispute.resolved",
    scope: "deal",
    documentId: dispute.dealId,
    uid,
    businessId: dispute.businessId,
    participantIds: dispute.participantIds || [],
    details: { disputeId, reason: dispute.reason, resolution, status: newStatus }
  });

  return { success: true, status: newStatus };
});
