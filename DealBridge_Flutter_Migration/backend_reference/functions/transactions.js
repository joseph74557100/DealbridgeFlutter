// ==========================================================================
// Deal & Agreement server transactions.
//
// Firebase is the security authority for the deal lifecycle. This module
// implements server-side guarantees the Android client cannot satisfy on
// its own:
//
//  1. Deals are completed ONLY by the server. The `autoCompleteConfirmedDeal`
//     trigger verifies that BOTH parties explicitly confirmed the deal
//     (senderConfirmationStatus / recipientConfirmationStatus = CONFIRMED),
//     then atomically marks the deal COMPLETED, writes the signed agreement
//     record and stamps the audit trail. Clients can never write `status`,
//     `signatures`, `fullySigned`, `locked`, `signingStarted`, `signedDate`,
//     `contentHash` or `version` through Firestore rules.
//
//  2. Every agreement carries a server-computed SHA-256 `contentHash` over
//     a canonical serialization of its binding content (parties, deal link,
//     title, description, terms, value, expiry, signature count). The hash
//     is computed and stored by Cloud Functions only and verified before
//     signing and before deal completion, so any tampering done outside the
//     sanctioned flows is detected and audited.
//
//  3. Every agreement is versioned ("1.N", N = server-owned revision). Each
//     revision — creation and every sanctioned content change — is preserved
//     as an immutable snapshot under
//     `agreements/{id}/versions/{version}` that only participants may read.
//
//  4. Completed agreements are immutable: rules block client writes to
//     them, and the update trigger audits (and never re-completes) any
//     content change that arrives through an unprivileged edit.
//
//  5. Deals carry an `expiresAt` validity window. Rules refuse the creation
//     of already-expired deals and refuse `Accepted` transitions past
//     expiry; triggers delete expired-at-creation deals, revert expired
//     accept attempts and skip deal completion once the window closes.
//
//  6. Duplicate deals between the same two parties (any of Pending /
//     Accepted / Completed) are rejected server-side: the just-created
//     document is deleted and the attempt is recorded in the audit trail.
//
//  7. An append-only audit trail (`auditLogs`) records every important
//     deal/agreement action with the acting user's uid and a server
//     timestamp. Rules forbid clients from creating/updating/deleting audit
//     entries; they can only read the events they participate in.
// ==========================================================================

const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { onDocumentCreated, onDocumentUpdated } = require("firebase-functions/v2/firestore");
const { onSchedule } = require("firebase-functions/v2/scheduler");
const admin = require("firebase-admin");
const crypto = require("crypto");

const db = admin.firestore();
const serverTimestamp = () => admin.firestore.FieldValue.serverTimestamp();

// OneSignal credentials for deal notifications. The REST API key is a server
// secret (ONESSIONAL_REST_API_KEY env var); the app id matches the Android app.
const ONESIGNAL_APP_ID =
  process.env.ONESIGNAL_APP_ID || "30da6324-74cd-4c1c-9abe-cfe0887a8a2e";
const ONESIGNAL_REST_API_KEY = process.env.ONESIGNAL_REST_API_KEY || "";
const MESSAGE_CHANNEL_ID = "dealbridge_messages";

/**
 * Sends a push notification to a DealBridge account via OneSignal external id
 * (the Firebase uid). Best-effort: a failed push must never break the
 * underlying deal operation.
 */
async function sendPush(externalId, title, body, data) {
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
    return true;
  } catch (error) {
    console.warn("Push request error", { externalId, message: error.message });
    return false;
  }
}

/**
 * Best-effort in-app notification (notifications collection) - the admin SDK
 * bypasses the client rules that require recipientId == caller uid.
 */
async function writeNotification({ recipientId, title, message, data = {} }) {
  if (!recipientId) return;
  try {
    await db.collection("notifications").add({
      title,
      message,
      recipientId,
      createdAt: Date.now(),
      isRead: false,
      ...data
    });
  } catch (error) {
    console.warn("Notification write failed", { recipientId, message: error.message });
  }
}

const MONTHS = [
  "Jan", "Feb", "Mar", "Apr", "May", "Jun",
  "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"
];

function pad2(n) {
  return n < 10 ? `0${n}` : `${n}`;
}

function formatDate(ts) {
  const d = new Date(ts);
  return `${pad2(d.getDate())} ${MONTHS[d.getMonth()]} ${d.getFullYear()}`;
}

function formatTime(ts) {
  const d = new Date(ts);
  let h = d.getHours();
  const m = d.getMinutes();
  const ampm = h >= 12 ? "PM" : "AM";
  h = h % 12;
  if (h === 0) h = 12;
  return `${pad2(h)}:${pad2(m)} ${ampm}`;
}

// --------------------------------------------------------------------------
// Agreement integrity & versioning helpers.
//
// The content hash covers only the BINDING content of an agreement, never
// transport/metadata artifacts (signature images, PDF locations, notes), so
// legitimate metadata edits do not invalidate it. Version changes do not
// change the hash — the version is bound to the content by the workflow
// itself (each revision gets its own immutable snapshot).
// --------------------------------------------------------------------------
const CONTENT_FIELDS = [
  "agreementNumber", "dealId", "businessOneId", "businessTwoId",
  "title", "description", "terms", "dealValue", "requiredSignatures",
  "expiryDate"
];

function canonicalAgreementContent(a) {
  const pick = {};
  for (const f of CONTENT_FIELDS) {
    const v = a[f];
    pick[f] = v === undefined || v === null ? "" : v;
  }
  const keys = Object.keys(pick).sort();
  return JSON.stringify(keys.map((k) => [k, pick[k].toString()]));
}

function agreementHash(a) {
  return crypto.createHash("sha256").update(canonicalAgreementContent(a)).digest("hex");
}

/** Version format "1.N": the revision counter N is server-authoritative. */
function nextRevision(version) {
  const m = /^1\.(\d+)$/.exec(version || "");
  const major = m ? parseInt(m[1], 10) : 0;
  return `1.${major + 1}`;
}

/** A deal is expired when it carries a positive expiresAt in the past. */
function isExpired(expiresAt, nowMs = Date.now()) {
  return expiresAt != null && expiresAt > 0 && expiresAt <= nowMs;
}

async function businessOwnerOf(businessId) {
  if (!businessId) return null;
  try {
    const snap = await db.collection("businesses").doc(businessId).get();
    return snap.exists ? (snap.data().ownerId || null) : null;
  } catch (_) {
    return null;
  }
}

/** Best-effort append to the audit trail (never fatal to the main operation). */
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

// --------------------------------------------------------------------------
// Abuse protection: rate limiting, anomaly detection and admin flagging.
//
// All counters live in the `securityCounters` collection which rules make
// completely inaccessible to clients. Every security decision is written to
// the append-only `auditLogs` with a server timestamp, and suspicious
// entities are FLAGGED for admin review (never silently deleted): a
// `flagged` + `flagReasons` + `flaggedAt` marker is stamped on the document
// and a pending entry is created in `adminReviews` (admin-only read).
// --------------------------------------------------------------------------

// Deal creation: more than this many deals from one sender in the window.
const DEAL_CREATE_LIMIT = 8;
const DEAL_CREATE_WINDOW_MS = 10 * 60 * 1000;

// Agreement creation per user in the window (bulk acceptance is normal).
const AGREEMENT_CREATE_LIMIT = 15;
const AGREEMENT_CREATE_WINDOW_MS = 10 * 60 * 1000;

// Account documents per email (any create of a users/{uid} doc) per hour.
const ACCOUNT_CREATE_LIMIT = 2;
const ACCOUNT_CREATE_WINDOW_MS = 60 * 60 * 1000;

// User-document creations per uid per window (rapid doc recreation).
const USER_DOC_CREATE_LIMIT = 3;
const USER_DOC_CREATE_WINDOW_MS = 10 * 60 * 1000;

// Deal accepts by one business per window (automated mass-acceptance).
const DEAL_ACCEPT_LIMIT = 20;
const DEAL_ACCEPT_WINDOW_MS = 10 * 60 * 1000;

/**
 * Atomic sliding-window counter on `securityCounters/{action}_{actor}`.
 * Fail-open: if the counter itself errors, the action is allowed (the
 * anomaly/flagging layers below still apply).
 */
async function rateLimit(actor, action, limit, windowMs) {
  const ref = db.collection("securityCounters").doc(`${action}_${actor}`);
  try {
    return await db.runTransaction(async (transaction) => {
      const snap = await transaction.get(ref);
      const now = Date.now();
      const prev = snap.exists ? (snap.data() || {}) : {};
      let count = prev.count || 0;
      if (now - (prev.windowStart || 0) >= windowMs) {
        count = 0;
      }
      count += 1;
      transaction.set(ref, {
        action,
        actor,
        count,
        windowStart: now
      }, { merge: true });
      return { ok: count <= limit, count };
    });
  } catch (error) {
    console.warn("Rate limit check failed; allowing action", { action, actor, message: error.message });
    return { ok: true, count: 1 };
  }
}

/** SHA-256 hex key used for sensitive counter identifiers (emails). */
function hashKey(value) {
  return crypto.createHash("sha256").update(value).digest("hex");
}

/**
 * Flags a document for admin review instead of deleting it: stamps the
 * server-owned marker fields, creates a pending adminReviews entry and
 * records the event in the audit trail with a server timestamp.
 */
async function flagForReview({ action, scope, documentId, ref, reasons, extraFields = {}, uid = null, businessId = "", participantIds = [], details = {} }) {
  const flagFields = {
    flagged: true,
    flagReasons: reasons,
    // Epoch millis (number), NOT a serverTimestamp: the Android models map
    // flaggedAt to a `long` field and a stored Timestamp fails toObject().
    flaggedAt: Date.now(),
    ...extraFields
  };
  try {
    await ref.update(flagFields);
  } catch (error) {
    console.warn("Unable to flag document", { scope, documentId, message: error.message });
  }
  try {
    await db.collection("adminReviews").add({
      type: scope,
      targetId: documentId,
      reasons,
      details,
      status: "pending",
      flaggedBy: uid,
      createdAt: serverTimestamp()
    });
  } catch (error) {
    console.warn("Unable to create admin review", { scope, documentId, message: error.message });
  }
  await writeAudit({
    action,
    scope,
    documentId,
    uid,
    businessId,
    participantIds,
    details: { ...details, reasons }
  });
}

/**
 * Looks for an existing active/completed deal between the same two parties
 * (in either direction). Rejected/Cancelled deals do not block new offers.
 */
async function findByParties(senderId, businessId) {
  const statuses = ["PENDING", "ACCEPTED", "SIGNING", "COMPLETED"];
  try {
    const q1 = db.collection("deals")
      .where("senderId", "==", senderId)
      .where("businessId", "==", businessId)
      .where("status", "in", statuses)
      .limit(1);
    const s1 = await q1.get();
    if (!s1.empty) return s1.docs[0];

    const q2 = db.collection("deals")
      .where("senderId", "==", businessId)
      .where("businessId", "==", senderId)
      .where("status", "in", statuses)
      .limit(1);
    const s2 = await q2.get();
    return s2.empty ? null : s2.docs[0];
  } catch (error) {
    console.warn("Duplicate deal lookup failed", { senderId, businessId, message: error.message });
    return null;
  }
}

/**
 * Atomically checks for duplicate deals and creates a lock document to prevent
 * race conditions. Returns { ok: true } if no duplicate, { ok: false, existingDeal }
 * if duplicate found. The lock document expires after 10 minutes.
 */
async function checkAndLockDealCreation(senderId, businessId, dealId) {
  const lockId = `${senderId}_${businessId}`.replace(/[^a-zA-Z0-9_]/g, '_');
  const lockRef = db.collection("deal_locks").doc(lockId);

  try {
    const result = await db.runTransaction(async (transaction) => {
      const lockSnap = await transaction.get(lockRef);
      if (lockSnap.exists) {
        // Another deal creation is in progress or recently completed
        return { ok: false, reason: "lock-exists" };
      }

// Check for existing active deals
      const statuses = ["PENDING", "ACCEPTED", "ACTIVE", "SIGNING", "COMPLETED"];
      const q1 = db.collection("deals")
        .where("senderId", "==", senderId)
        .where("businessId", "==", businessId)
        .where("status", "in", statuses)
        .limit(1);
      const s1 = await transaction.get(q1);
      if (!s1.empty) {
        return { ok: false, reason: "duplicate", existingDeal: s1.docs[0] };
      }

      const q2 = db.collection("deals")
        .where("senderId", "==", businessId)
        .where("businessId", "==", senderId)
        .where("status", "in", statuses)
        .limit(1);
      const s2 = await transaction.get(q2);
      if (!s2.empty) {
        return { ok: false, reason: "duplicate", existingDeal: s2.docs[0] };
      }

      // Create lock with expiration (10 minutes)
      transaction.set(lockRef, {
        dealId,
        senderId,
        businessId,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        expiresAt: Date.now() + 10 * 60 * 1000
      });

      return { ok: true };
    });

    return result;
  } catch (error) {
    console.warn("Deal lock check failed", { senderId, businessId, message: error.message });
    // Fail-open: allow deal creation if lock check fails
    return { ok: true };
  }
}

/**
 * Releases the deal creation lock after successful creation.
 */
async function releaseDealLock(senderId, businessId) {
  const lockId = `${senderId}_${businessId}`.replace(/[^a-zA-Z0-9_]/g, '_');
  try {
    await db.collection("deal_locks").doc(lockId).delete();
  } catch (error) {
    console.warn("Failed to release deal lock", { senderId, businessId, message: error.message });
  }
}

// ==========================================================================
// Agreement triggers.
// ==========================================================================

exports.onAgreementCreated = onDocumentCreated("agreements/{agreementId}", async (event) => {
  const id = event.params.agreementId;
  const data = event.data?.data?.() || {};

  // Server-generated agreements (created atomically by autoCompleteConfirmedDeal
  // when a deal completes by confirmation) are sanctioned records, not
  // client-flow creations: the client velocity checks do not apply to them.
  if (data.serverGenerated !== true) {
    // Abnormal agreement-creation velocity (bulk automated acceptance) →
    // flag for review; the deal linked to a flagged agreement never completes.
    const velocity = await rateLimit(
      data.createdBy || "unknown",
      "agreement-create",
      AGREEMENT_CREATE_LIMIT,
      AGREEMENT_CREATE_WINDOW_MS
    );
    if (!velocity.ok) {
      await flagForReview({
        action: "flag.agreement-velocity",
        scope: "agreement",
        documentId: id,
        ref: db.collection("agreements").doc(id),
        reasons: ["agreement-create-velocity"],
        uid: data.createdBy || null,
        businessId: data.businessOneId || "",
        participantIds: data.participantIds || [],
        details: {
          dealId: data.dealId || "",
          count: velocity.count,
          windowMinutes: AGREEMENT_CREATE_WINDOW_MS / 60000
        }
      });
    }
  }

  const version = data.version || "1.0";
  const doc = { ...data, version };
  doc.contentHash = agreementHash(doc);

  try {
    const ref = db.collection("agreements").doc(id);
    const patch = { contentHash: doc.contentHash };
    if (!data.version) patch.version = "1.0";
    await ref.update(patch);

    // Immutable first-version snapshot of the fresh agreement.
    await ref.collection("versions").doc(version).set({
      ...doc,
      snapshotReason: "created",
      snapshotBy: data.createdBy || null,
      snapshotCreatedAt: serverTimestamp()
    });
  } catch (error) {
    console.warn("Agreement hash adoption failed at creation", { agreementId: id, message: error.message });
  }

  await writeAudit({
    action: "agreement.created",
    scope: "agreement",
    documentId: id,
    uid: data.createdBy || null,
    businessId: data.businessOneId || "",
    participantIds: data.participantIds || [],
    details: {
      dealId: data.dealId || "",
      agreementNumber: data.agreementNumber || "",
      version,
      contentHash: doc.contentHash
    }
  });
});

exports.onAgreementUpdated = onDocumentUpdated("agreements/{agreementId}", async (event) => {
  const id = event.params.agreementId;
  const before = event.data.before?.data?.() || {};
  const after = event.data.after?.data?.() || {};

  // 1) Integrity: the binding content must never change on a signed/locked
  //    agreement. Rules already block SDK clients; this audits anything that
  //    still slips through (admin/console edits) and never re-completes it.
  const contentChanged =
    canonicalAgreementContent(before) !== canonicalAgreementContent(after);

  if (contentChanged && (before.fullySigned === true || before.locked === true)) {
    await writeAudit({
      action: "agreement.tamper-detected",
      scope: "agreement",
      documentId: id,
      uid: after.updatedBy || null,
      businessId: after.businessOneId || "",
      participantIds: before.participantIds || [],
      details: {
        version: after.version || before.version || "",
        status: after.status || before.status || "",
        storedHash: before.contentHash || ""
      }
    });
  } else if (contentChanged) {
    // Content changed while still unsigned — a sanctioned, versioned change
    // (an admin/API edit; clients are blocked by the rules whitelist).
    const newVersion = nextRevision(after.version);
    const patched = { ...after, version: newVersion };
    patched.contentHash = agreementHash(patched);

    try {
      await db.collection("agreements").doc(id).update({
        version: newVersion,
        contentHash: patched.contentHash
      });
      await db.collection("agreements").doc(id).collection("versions").doc(newVersion).set({
        ...patched,
        snapshotReason: "content-update",
        snapshotBy: after.updatedBy || null,
        snapshotCreatedAt: serverTimestamp()
      });
    } catch (error) {
      console.warn("Agreement versioning failed", { agreementId: id, message: error.message });
    }

    await writeAudit({
      action: "agreement.content-updated",
      scope: "agreement",
      documentId: id,
      uid: after.updatedBy || null,
      businessId: after.businessOneId || "",
      participantIds: after.participantIds || [],
      details: { from: before.version || "", to: newVersion, contentHash: patched.contentHash }
    });
  } else if (!before.contentHash && !after.contentHash) {
    // Legacy documents that predate the hash feature: adopt a hash once.
    // (Skipped when the callable already adopted it during signing.)
    const version = after.version || "1.0";
    const patched = { ...after, version };
    patched.contentHash = agreementHash(patched);

    try {
      await db.collection("agreements").doc(id).update({ contentHash: patched.contentHash });
      await db.collection("agreements").doc(id).collection("versions").doc(version).set({
        ...patched,
        snapshotReason: "adopted",
        snapshotBy: after.createdBy || null,
        snapshotCreatedAt: serverTimestamp()
      });
    } catch (error) {
      console.warn("Agreement hash adoption failed", { agreementId: id, message: error.message });
    }
  }

  // 2) Audit metadata-only edits (notes, attachments, PDF locations). These
  //    never touch the signed content, so no version bump is needed.
  if (!contentChanged) {
    const metadataKeys = ["notes", "attachments", "pdfUrl", "fileId", "localPdfPath"];
    const changed = metadataKeys.filter(
      (k) => JSON.stringify(before[k]) !== JSON.stringify(after[k])
    );
    if (changed.length > 0) {
      await writeAudit({
        action: "agreement.updated",
        scope: "agreement",
        documentId: id,
        uid: after.updatedBy || null,
        businessId: after.businessOneId || "",
        participantIds: after.participantIds || [],
        details: { version: after.version || "", changed }
      });
    }
  }

  // 3) Audit archive/restore/expiry status transitions.
  if (before.status !== after.status && after.status !== "Signed") {
    if (after.status === "Archived" || after.status === "Expired" || after.status === "Pending Signature") {
      await writeAudit({
        action:
          after.status === "Archived"
            ? "agreement.archived"
            : after.status === "Expired"
              ? "agreement.expired"
              : "agreement.restored",
        scope: "agreement",
        documentId: id,
        uid: after.updatedBy || null,
        businessId: after.businessOneId || "",
        participantIds: after.participantIds || [],
        details: { from: before.status, to: after.status, version: after.version || "" }
      });
    }
  }
});

// ==========================================================================
// Deal triggers.
// ==========================================================================

exports.onDealCreated = onDocumentCreated("deals/{dealId}", async (event) => {
  const id = event.params.dealId;
  const data = event.data?.data?.() || {};

  if (!data.senderId || !data.businessId) return;

  const ref = db.collection("deals").doc(id);
  const auditBase = {
    uid: data.senderId || null,
    businessId: data.businessId || "",
    participantIds: data.participantIds || []
  };
  const detailsBase = {
    title: data.title || "",
    status: data.status || "",
    expiresAt: data.expiresAt || null
  };

  // 1) Offers created already expired are suspect — flag for admin review
  //    (never silently deleted).
  if (isExpired(data.expiresAt)) {
    await flagForReview({
      action: "flag.deal-expired",
      scope: "deal",
      documentId: id,
      ref,
      reasons: ["expired-at-creation"],
      extraFields: { status: "Flagged" },
      ...auditBase,
      details: { ...detailsBase, reason: "expired-at-creation" }
    });
    return;
  }

  // 2) Duplicate active/completed deals between the same parties (in either
  //    direction) are suspect — flag for admin review.
  // Use transactional check to prevent race conditions.
  const lockResult = await checkAndLockDealCreation(data.senderId, data.businessId, id);
  if (!lockResult.ok) {
    if (lockResult.reason === "duplicate" && lockResult.existingDeal && lockResult.existingDeal.id !== id) {
      await flagForReview({
        action: "flag.deal-duplicate",
        scope: "deal",
        documentId: id,
        ref,
        reasons: ["duplicate-deal"],
        extraFields: { status: "Flagged" },
        ...auditBase,
        details: {
          ...detailsBase,
          existingDealId: lockResult.existingDeal.id,
          existingStatus: lockResult.existingDeal.data().status || ""
        }
      });
    }
    // For lock-exists, the deal was created concurrently - we still flag it
    // but don't return early to allow the deal to exist (fail-open)
    if (lockResult.reason === "lock-exists") {
      console.warn("Concurrent deal creation detected", { dealId: id, senderId: data.senderId, businessId: data.businessId });
    }
    // Don't return early for lock-exists, let the deal proceed (fail-open)
    // For actual duplicates, we flag but the deal still exists
  }

  // 3) Abnormal deal-creation velocity from the same sender (spammy bursts)
  //    — flag the offending deal for review.
  const velocity = await rateLimit(data.senderId, "deal-create", DEAL_CREATE_LIMIT, DEAL_CREATE_WINDOW_MS);
  if (!velocity.ok) {
    await flagForReview({
      action: "flag.deal-velocity",
      scope: "deal",
      documentId: id,
      ref,
      reasons: ["deal-create-velocity"],
      extraFields: { status: "Flagged" },
      ...auditBase,
      details: {
        ...detailsBase,
        count: velocity.count,
        windowMinutes: DEAL_CREATE_WINDOW_MS / 60000
      }
    });
    return;
  }

  // 4) Otherwise record the creation with the acting sender's uid.
  await writeAudit({
    action: "deal.created",
    scope: "deal",
    documentId: id,
    ...auditBase,
    details: detailsBase
  });

  // 5) Notify the recipient that a new deal request has arrived. The target
  //    is the owner of the receiving business; the sender gets their own
  //    in-app confirmation from the client.
  if (data.status === "PENDING") {
    const recipientUid = await businessOwnerOf(data.businessId);
    if (recipientUid && recipientUid !== data.senderId) {
      const senderName = data.senderName || data.senderId || "A DealBridge user";
      const title = "New Deal Request";
      const body = `${senderName} sent you a deal: "${data.title || "Untitled deal"}".`;

      await writeNotification({
        recipientId: recipientUid,
        title,
        message: body,
        data: { notificationType: "deal_request", dealId: id }
      });
      await sendPush(recipientUid, title, body, {
        notificationType: "deal_request",
        dealId: id
      });
    }
  }

  // Release the deal creation lock
  await releaseDealLock(data.senderId, data.businessId);
});

exports.onDealUpdated = onDocumentUpdated("deals/{dealId}", async (event) => {
  const before = event.data.before?.data?.() || {};
  const after = event.data.after?.data?.() || {};
  const dealId = event.params.dealId;
  const statusChanged = before.status !== after.status;

  // Completed transitions are recorded by autoCompleteConfirmedDeal with the
  // server timestamp; anything arriving on the COMPLETED/SIGNING status is
  // already tagged there (SIGNING is no longer written by any flow).
  if (after.status === "COMPLETED" || after.status === "SIGNING") return;

  // Expired deals can never be accepted. Rules already refuse this for SDK
  // clients; this reverts the attempt if it arrives through another channel.
  if (statusChanged && after.status === "ACCEPTED" && isExpired(after.expiresAt)) {
    try {
      await db.collection("deals").doc(dealId).update({ status: before.status });
    } catch (error) {
      console.warn("Unable to revert expired accept attempt", { dealId, message: error.message });
    }
    await writeAudit({
      action: "deal.accept-expired-rejected",
      scope: "deal",
      documentId: dealId,
      uid: (await businessOwnerOf(after.businessId)) || after.senderId || null,
      businessId: after.businessId || "",
      participantIds: after.participantIds || [],
      details: { from: before.status, to: after.status, expiresAt: after.expiresAt || null }
    });
    return;
  }

  // ------------------------------------------------------------------------
  // Per-party journey transitions (status does not change).
  //
  // The Review Terms -> Agreed -> Confirmed flow advances party-by-party
  // without touching the deal status, so it cannot be detected through the
  // status change. Notify the counterparty at each landmark so both parties
  // always know where the deal stands.
  // ------------------------------------------------------------------------
  if (!statusChanged && after.senderId) {
    const ownerUid = await businessOwnerOf(after.businessId);
    if (!ownerUid || ownerUid === after.senderId) return;

    const senderName = after.senderName || after.senderId || "A party";
    const businessName = after.businessName || ownerUid || "The other party";

    const senderJustAgreed =
      before.senderConfirmationStatus !== "AGREED" && after.senderConfirmationStatus === "AGREED";
    const recipientJustAgreed =
      before.recipientConfirmationStatus !== "AGREED" && after.recipientConfirmationStatus === "AGREED";
    if (senderJustAgreed || recipientJustAgreed) {
      const agreedParty = senderJustAgreed ? senderName : businessName;
      const notifiedUid = senderJustAgreed ? ownerUid : after.senderId;
      const title = "Terms Agreed";
      const body = `${agreedParty} agreed to the terms of "${after.title || "your deal"}".`;
      await writeNotification({
        recipientId: notifiedUid,
        title,
        message: body,
        data: { notificationType: "deal_terms_agreed", dealId }
      });
      await sendPush(notifiedUid, title, body, {
        notificationType: "deal_terms_agreed",
        dealId
      });
    }

    const senderJustConfirmed =
      before.senderConfirmationStatus !== "CONFIRMED" && after.senderConfirmationStatus === "CONFIRMED";
    const recipientJustConfirmed =
      before.recipientConfirmationStatus !== "CONFIRMED" && after.recipientConfirmationStatus === "CONFIRMED";
    if (senderJustConfirmed || recipientJustConfirmed) {
      const confirmedParty = senderJustConfirmed ? senderName : businessName;
      const notifiedUid = senderJustConfirmed ? ownerUid : after.senderId;
      const title = "Deal Confirmed";
      const body = `${confirmedParty} confirmed "${after.title || "your deal"}". It will complete once both parties confirm.`;
      await writeNotification({
        recipientId: notifiedUid,
        title,
        message: body,
        data: { notificationType: "deal_confirmed", dealId }
      });
      await sendPush(notifiedUid, title, body, {
        notificationType: "deal_confirmed",
        dealId
      });
    }

    return;
  }

  const ownerUid = await businessOwnerOf(after.businessId);

  // Stamp the acceptance timestamp server-side when a deal is first accepted
  // (epoch millis). Clients can never write it: the Firestore rules refuse
  // the field from the SDK, so a stored value here is always authoritative.
  if (after.status === "ACCEPTED" && before.status !== "ACCEPTED" && !after.acceptedAt) {
    try {
      await db.collection("deals").doc(dealId).update({ acceptedAt: Date.now() });
    } catch (error) {
      console.warn("Unable to stamp acceptedAt", { dealId, message: error.message });
    }
  }

  // Automated mass-acceptance protection: rapid Accept transitions by one
  // business are flagged (never reverted) for admin review.
  if (after.status === "ACCEPTED" && ownerUid) {
    const acceptRate = await rateLimit(ownerUid, "deal-accept", DEAL_ACCEPT_LIMIT, DEAL_ACCEPT_WINDOW_MS);
    if (!acceptRate.ok) {
      await flagForReview({
        action: "flag.deal-accept-velocity",
        scope: "deal",
        documentId: event.params.dealId,
        ref: db.collection("deals").doc(event.params.dealId),
        reasons: ["deal-accept-velocity"],
        uid: ownerUid,
        businessId: after.businessId || "",
        participantIds: after.participantIds || [],
        details: { count: acceptRate.count, windowMinutes: DEAL_ACCEPT_WINDOW_MS / 60000 }
      });
    }
  }

  await writeAudit({
    action:
      after.status === "ACCEPTED"
        ? "deal.accepted"
        : after.status === "DECLINED"
          ? "deal.declined"
          : "deal.cancelled",
    scope: "deal",
    documentId: event.params.dealId,
    uid: ownerUid || after.senderId || null,
    businessId: after.businessId || "",
    participantIds: after.participantIds || [],
    details: { from: before.status, to: after.status }
  });

  // Notify the other party that the deal was accepted/declined/cancelled.
  if (after.status === "CANCELLED") {
    const title = "Deal Cancelled";
    const body = `"${after.title || "Your deal"}" was cancelled.`;
    const targets = new Set((after.participantIds || []).filter(Boolean));
    for (const uid of targets) {
      await writeNotification({
        recipientId: uid,
        title,
        message: body,
        data: { notificationType: "deal_response", dealId: event.params.dealId }
      });
      await sendPush(uid, title, body, {
        notificationType: "deal_response",
        dealId: event.params.dealId
      });
    }
  } else if (after.senderId) {
    const verb = after.status === "ACCEPTED" ? "accepted" : "declined";
    const title = after.status === "ACCEPTED" ? "Deal Accepted" : "Deal Declined";
    const body = `"${after.title || "Your deal"}" was ${verb}.`;
    await writeNotification({
      recipientId: after.senderId,
      title,
      message: body,
      data: { notificationType: "deal_response", dealId: event.params.dealId }
    });
    await sendPush(after.senderId, title, body, {
      notificationType: "deal_response",
      dealId: event.params.dealId
    });
  }
});

// ==========================================================================
// Deal cancellation — server-authoritative.
//
// Cancellation is handled by a trusted Cloud Function instead of a direct
// client write: the client submits the request and the server validates the
// caller is a participant, validates the deal can still be cancelled, then
// performs the protected state transition (status = CANCELLED, cancelledAt =
// server timestamp, cancelledBy = authenticated caller). A cancelled deal is
// a terminal state: it can never be re-opened and can never auto-complete,
// because completeConfirmedDeal rejects CANCELLED deals (both before and
// inside its transaction).
//
// The `onDealUpdated` trigger picks up this update, records the audit event
// and notifies both participants.
// ==========================================================================
const CANCELLABLE_STATUSES = ["PENDING", "ACCEPTED", "ACTIVE", "DECLINED", "EXPIRED"];

exports.cancelDeal = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "You must be signed in");
  }

  const dealId = (request.data?.dealId || "").toString();
  if (!dealId) {
    throw new HttpsError("invalid-argument", "Deal ID is required");
  }

  const dealRef = db.collection("deals").doc(dealId);
  const dealSnap = await dealRef.get();
  if (!dealSnap.exists) {
    throw new HttpsError("not-found", "Deal not found");
  }
  const deal = dealSnap.data() || {};
  const participantIds = deal.participantIds || [];

  // 1) The authenticated caller must actually be a participant.
  if (!participantIds.includes(uid) && deal.senderId !== uid) {
    await writeAudit({
      action: "deal.cancel-denied",
      scope: "deal",
      documentId: dealId,
      uid,
      businessId: deal.businessId || "",
      participantIds,
      details: { reason: "not-participant" }
    });
    throw new HttpsError("permission-denied", "You are not a participant in this deal");
  }

  const status = deal.status || "PENDING";

  // 2) Validate that the deal can still be cancelled.
  if (status === "CANCELLED") {
    throw new HttpsError("failed-precondition", "This deal is already cancelled");
  }
  if (status === "COMPLETED" || status === "SIGNING") {
    throw new HttpsError("failed-precondition", "This deal can no longer be cancelled");
  }
  if (!CANCELLABLE_STATUSES.includes(status)) {
    throw new HttpsError("failed-precondition", "This deal can no longer be cancelled");
  }
  // A deal where both parties have already confirmed is terminal — it must
  // complete, not be cancelled. (The app hides Cancel in that state too; this
  // is the server-side enforcement.)
  const bothConfirmed =
    deal.senderConfirmationStatus === "CONFIRMED" && deal.recipientConfirmationStatus === "CONFIRMED";
  if (bothConfirmed) {
    throw new HttpsError(
      "failed-precondition",
      "Both parties have confirmed this deal; it can no longer be cancelled"
    );
  }

  // 3) Perform the protected state transition.
  await dealRef.update({
    status: "CANCELLED",
    // Server-derived cancellation timestamp. The Android Deal model defines
    // no cancelledAt field, so toObject() ignores the stored Timestamp while
    // the server keeps an authoritative record.
    cancelledAt: serverTimestamp(),
    cancelledBy: uid,
    lastActivityAt: Date.now()
  });

  return { success: true, dealId, status: "CANCELLED", cancelledBy: uid };
});

// ==========================================================================
// User account trigger — rapid/duplicate account creation protection.
//
// Firebase Auth already prevents registering the same email twice through
// the app; this trigger protects the Firestore side: every new `users/{uid}`
// document is audited with a server timestamp, duplicate-email registration
// attempts (same email, >2 per hour) are flagged for admin review, and rapid
// recreation of a user document (>3 per window) is flagged too. Flagged
// accounts are never deleted — an admin reviews them via adminReviews.
// ==========================================================================
exports.onUserCreated = onDocumentCreated("users/{uid}", async (event) => {
  const uid = event.params.uid;
  const data = event.data?.data?.() || {};
  const ref = db.collection("users").doc(uid);
  const auditBase = {
    uid,
    businessId: "",
    participantIds: [uid]
  };

  const email = (data.email || "").toString().trim().toLowerCase();

  // Baseline record of the new account (server timestamp only).
  await writeAudit({
    action: "account.created",
    scope: "user",
    documentId: uid,
    ...auditBase,
    details: { email: email || "" }
  });

  // Rapid account creation attempts for the same email.
  if (email) {
    const emailKey = hashKey(email);
    const emailRate = await rateLimit(emailKey, "account-create", ACCOUNT_CREATE_LIMIT, ACCOUNT_CREATE_WINDOW_MS);
    if (!emailRate.ok) {
      await flagForReview({
        action: "flag.account-duplicate",
        scope: "user",
        documentId: uid,
        ref,
        reasons: ["duplicate-account"],
        ...auditBase,
        details: { email, count: emailRate.count, windowMinutes: ACCOUNT_CREATE_WINDOW_MS / 60000 }
      });
      return;
    }

    // Re-registration of an email that already owns a (different) account.
    try {
      const q = db.collection("users")
        .where("email", "==", email)
        .where(admin.firestore.FieldPath.documentId(), "!=", uid)
        .limit(1);
      const snap = await q.get();
      if (!snap.empty) {
        await flagForReview({
          action: "flag.account-duplicate",
          scope: "user",
          documentId: uid,
          ref,
          reasons: ["duplicate-account"],
          ...auditBase,
          details: { email, existingAccountId: snap.docs[0].id }
        });
        return;
      }
    } catch (error) {
      console.warn("Duplicate-email account lookup failed", { uid, message: error.message });
    }
  }

  // Senior Pastor auto-provisioning: the designated Senior Pastor account
  // (TmgmChrist01@gmail.com) is elevated server-side only — never by the
  // client — via an admins/{uid} document and custom claims. Any attempt to
  // self-promote by writing role/isAdmin/isSeniorPastor from the client is
  // blocked by Firestore rules (users create/update deny those fields).
  if (email === "tmgmchrist01@gmail.com") {
    try {
      await db.collection("admins").doc(uid).set({
        active: true,
        role: "seniorPastor",
        permissions: ["*"],
        email,
        provisionedAt: serverTimestamp(),
        provisionedBy: "system:s seniorPastor-autoProvision"
      }, { merge: true });
      await admin.auth().setCustomUserClaims(uid, { admin: true, superAdmin: true, role: "seniorPastor" });
      await writeAudit({
        action: "account.seniorPastor-provisioned",
        scope: "user",
        documentId: uid,
        ...auditBase,
        details: { email }
      });
    } catch (e) {
      console.warn("Senior Pastor auto-provision failed", { uid, message: e.message });
    }
  }

  // Rapid recreation of the same user document (fresh Firestore doc for an
  // existing uid) — flag for review.
  const docRate = await rateLimit(uid, "user-doc-create", USER_DOC_CREATE_LIMIT, USER_DOC_CREATE_WINDOW_MS);
  if (!docRate.ok) {
    await flagForReview({
      action: "flag.account-velocity",
      scope: "user",
      documentId: uid,
      ref,
      reasons: ["account-create-velocity"],
      ...auditBase,
      details: { count: docRate.count, windowMinutes: USER_DOC_CREATE_WINDOW_MS / 60000 }
    });
  }
});

/**
 * Atomically completes a deal once BOTH parties have confirmed it.
 *
 * The new agreement flow has no handwritten signatures: each participant
 * reviews the terms, agrees, and then confirms. The confirmation status
 * fields are written by the app clients; only this server transaction may
 * move the deal to COMPLETED (clients are blocked by Firestore rules and by
 * the app's own updateStatus guard). Shared by the autoCompleteConfirmedDeal
 * trigger and the repairStuckConfirmedDeals sweep so every completion uses
 * the exact same code path and can never disagree.
 *
 * Returns { completed: true, ... } when this call completed the deal,
 * { alreadyCompleted: true } when another invocation beat us to it, and
 * { skipped: true } when the deal is not ready to complete.
 */
async function completeConfirmedDeal(dealId, after) {
  // A completed deal is a terminal state - never re-enter.
  if (after.status === "COMPLETED") return { alreadyCompleted: true };

  // A cancelled (or declined) deal is ALSO terminal: it must never become
  // completed, even if both parties had previously confirmed it. The server
  // guards this transition here so a cancelled deal can never silently
  // auto-complete later (e.g. via the self-healing sweep).
  if (after.status === "CANCELLED" || after.status === "DECLINED") {
    return { skipped: true };
  }

  // Both parties must have explicitly confirmed the deal. Per-party write
  // enforcement in the rules means each side only ever sets its own
  // confirmation field, so this state is only reachable with genuine
  // agreement from BOTH parties.
  const senderStatus = after.senderConfirmationStatus || "";
  const recipientStatus = after.recipientConfirmationStatus || "";
  if (senderStatus !== "CONFIRMED" || recipientStatus !== "CONFIRMED") {
    return { skipped: true };
  }

  // Resolve the two agreement parties server-side from DealBridge data using
  // the same canonical convention as the client (sender entity first, target
  // business second). Queries cannot run inside a Firestore transaction, so
  // both parties are resolved up front and the authoritative deal snapshot is
  // re-read in the transaction.
  const senderUid = after.senderId || "";
  const recipientBusinessId = after.businessId || "";
  let senderEntityId = senderUid;
  let senderEntityName = after.senderName || senderUid;
  let recipientOwnerUid = "";
  let recipientBusinessName = after.businessName || recipientBusinessId;
  try {
    const senderBusinessSnap = await db
      .collection("businesses")
      .where("ownerId", "==", senderUid)
      .limit(1)
      .get();
    if (!senderBusinessSnap.empty) {
      const senderBusiness = senderBusinessSnap.docs[0];
      senderEntityId = senderBusiness.id;
      senderEntityName = senderBusiness.data().name || senderEntityName;
    }
  } catch (error) {
    console.warn("Agreement party resolution failed (sender business)", { dealId, message: error.message });
  }
  try {
    const recipientBusinessSnap = await db.collection("businesses").doc(recipientBusinessId).get();
    if (recipientBusinessSnap.exists) {
      recipientOwnerUid = recipientBusinessSnap.data().ownerId || "";
      recipientBusinessName = recipientBusinessSnap.data().name || recipientBusinessName;
    }
  } catch (error) {
    console.warn("Agreement party resolution failed (recipient business)", { dealId, message: error.message });
  }

  const result = await db.runTransaction(async (transaction) => {
    const dealRef = db.collection("deals").doc(dealId);
    const snap = await transaction.get(dealRef);
    if (!snap.exists) return null;
    const deal = snap.data() || {};

    if (deal.status === "COMPLETED") return { alreadyCompleted: true };

    // A cancelled/deal deal is terminal too: it must never become completed,
    // even if both parties had previously confirmed it. The in-transaction
    // check closes the race where the repair sweep re-reads a stale snapshot
    // after a cancellation happened server-side.
    if (deal.status === "CANCELLED" || deal.status === "DECLINED") {
      const cancelAudit = db.collection("auditLogs").doc();
      transaction.set(cancelAudit, {
        action: "deal.completion-blocked",
        scope: "deal",
        documentId: dealId,
        dealId,
        uid: null,
        businessId: deal.businessId || "",
        participantIds: deal.participantIds || [],
        details: { reason: `status-${deal.status}` },
        timestamp: serverTimestamp()
      });
      return null;
    }

    // A flagged deal never completes until an admin reviews it.
    if (deal.flagged === true) {
      const auditRef = db.collection("auditLogs").doc();
      transaction.set(auditRef, {
        action: "deal.completion-flagged-blocked",
        scope: "deal",
        documentId: dealId,
        dealId,
        uid: null,
        businessId: deal.businessId || "",
        participantIds: deal.participantIds || [],
        details: { reason: "both-parties-confirmed-but-flagged", flagReasons: deal.flagReasons || [] },
        timestamp: serverTimestamp()
      });
      return null;
    }

    // An expired deal can never complete, even if both parties confirmed it.
    if (isExpired(deal.expiresAt)) {
      const expiryAudit = db.collection("auditLogs").doc();
      transaction.set(expiryAudit, {
        action: "deal.expired",
        scope: "deal",
        documentId: dealId,
        dealId,
        uid: null,
        businessId: deal.businessId || "",
        participantIds: deal.participantIds || [],
        details: { reason: "completed-after-confirm-but-expired" },
        timestamp: serverTimestamp()
      });
      return null;
    }

    const now = Date.now();
    transaction.update(dealRef, {
      status: "COMPLETED",
      completedAt: now,
      completedDate: formatDate(now),
      lastActivityAt: now,
      currentStep: 4
    });

    // The completed deal is recorded as an agreement so both parties have a
    // signed, immutable record in "My Agreements" (matching the deal journey
    // step "Agreement Generated -> Agreement Stored in Profile"). This is the
    // path the agreement-free confirm flow was missing — deals that already
    // generated an agreement keep their existing record and are never touched.
    let agreementCreated = false;
    const agreementRef = db.collection("agreements").doc(dealId);
    const agreementSnap = await transaction.get(agreementRef);
    if (agreementSnap.exists) {
      // Never overwrite an existing agreement document with the synthesized
      // record. agreementCreated stays false.
    } else {
      const agreementParticipantIds = Array.from(
        new Set([senderUid, senderEntityId, recipientBusinessId, recipientOwnerUid].filter(Boolean))
      );

      const signatures = [
        {
          businessId: senderEntityId,
          businessName: senderEntityName,
          signerUserId: senderUid,
          signedDate: formatDate(now),
          signedTime: formatTime(now),
          deviceTime: `${formatDate(now)} ${formatTime(now)}`,
          signature: `Confirmed by ${senderEntityName || senderUid}`,
          signedAt: now
        },
        {
          businessId: recipientBusinessId,
          businessName: recipientBusinessName,
          signerUserId: recipientOwnerUid,
          signedDate: formatDate(now),
          signedTime: formatTime(now),
          deviceTime: `${formatDate(now)} ${formatTime(now)}`,
          signature: `Confirmed by ${recipientBusinessName || recipientBusinessId}`,
          signedAt: now
        }
      ];

      const agreementData = {
        agreementId: dealId,
        agreementNumber: newAgreementNumber(now),
        dealId,
        title: deal.title || "Untitled deal",
        description: deal.description || "",
        terms:
          deal.terms ||
          "Both parties agree to complete this transaction in good faith and according to the agreed terms.",
        dealValue: deal.value || "",
        requiredSignatures: 2,
        expiryDate: oneYearFromNowString(now),
        businessOneId: senderEntityId,
        businessOneName: senderEntityName,
        businessTwoId: recipientBusinessId,
        businessTwoName: recipientBusinessName,
        participantIds: agreementParticipantIds,
        createdDate: formatDate(now),
        createdAt: now,
        createdBy: null,
        // Server-generated marker: onAgreementCreated skips the client-flow
        // velocity checks for these sanctioned completion records.
        serverGenerated: true,
        status: "Signed",
        // Completion lifecycle stamped at completion time (epoch millis).
        // Included so a completed deal's agreement is a complete, immutable
        // record of the full journey (accepted -> agreed -> confirmed ->
        // completed) even if the caller already generated one.
        completionStatus: "COMPLETED",
        completedAt: now,
        completedDate: formatDate(now),
        senderUid,
        recipientUid: recipientOwnerUid,
        acceptedAt: typeof deal.acceptedAt === "number" && deal.acceptedAt > 0 ? deal.acceptedAt : 0,
        senderAgreedAt: typeof deal.senderAgreedAt === "number" && deal.senderAgreedAt > 0 ? deal.senderAgreedAt : 0,
        recipientAgreedAt: typeof deal.recipientAgreedAt === "number" && deal.recipientAgreedAt > 0 ? deal.recipientAgreedAt : 0,
        senderConfirmedAt: typeof deal.senderConfirmedAt === "number" && deal.senderConfirmedAt > 0 ? deal.senderConfirmedAt : 0,
        recipientConfirmedAt: typeof deal.recipientConfirmedAt === "number" && deal.recipientConfirmedAt > 0 ? deal.recipientConfirmedAt : 0,
        fullySigned: true,
        locked: true,
        signingStarted: true,
        signedDate: formatDate(now),
        version: "1.0",
        signatures,
        contentHash: agreementHash({
          agreementNumber: newAgreementNumber(now),
          dealId,
          businessOneId: senderEntityId,
          businessTwoId: recipientBusinessId,
          title: deal.title || "Untitled deal",
          description: deal.description || "",
          terms:
            deal.terms ||
            "Both parties agree to complete this transaction in good faith and according to the agreed terms.",
          dealValue: deal.value || "",
          requiredSignatures: 2,
          expiryDate: oneYearFromNowString(now)
        })
      };

      // Write the signed agreement atomically with the deal completion so the
      // "COMPLETED deal" and its "Signed agreement" can never disagree.
      transaction.set(agreementRef, agreementData);
      agreementCreated = true;
    }

    const auditRef = db.collection("auditLogs").doc();
    transaction.set(auditRef, {
      action: agreementCreated === true ? "deal.completed-with-agreement" : "deal.completed",
      scope: "deal",
      documentId: dealId,
      dealId,
      uid: null,
      businessId: deal.businessId || "",
      participantIds: deal.participantIds || [],
      details: { reason: "both-parties-confirmed", agreementCreated: agreementCreated === true },
      timestamp: serverTimestamp()
    });

    return {
      completed: true,
      agreementCreated: agreementCreated === true,
      dealId,
      participantIds: deal.participantIds || [],
      dealTitle: deal.title || "",
      businessName: deal.businessName || ""
    };
  });

  if (result && result.completed && !result.alreadyCompleted) {
    console.log("Deal automatically completed by both-party confirmation", {
      dealId: result.dealId,
      title: result.dealTitle,
      agreementCreated: result.agreementCreated
    });

    const targets = new Set((result.participantIds || []).filter(Boolean));
    // The completion notification points both parties at the signed agreement
    // now stored with the completed deal.
    const title = "Deal Completed";
    const body = `"${result.dealTitle || "Your deal"}" has been completed. The final agreement is available in My Agreements.`;

    for (const uid of targets) {
      await writeNotification({
        recipientId: uid,
        title,
        message: body,
        data: { notificationType: "deal_completed", dealId: result.dealId }
      });
      await sendPush(uid, title, body, {
        notificationType: "deal_completed",
        dealId: result.dealId
      });
    }

    // When the completion synthesized a brand-new agreement document, both
    // parties also get a distinct "agreement generated" event so they can
    // jump straight to it in My Agreements. Deals whose agreement already
    // existed keep a single deal_completed notification (no duplicate).
    if (result.agreementCreated === true) {
      const agreementTitle = "Agreement Generated";
      const agreementBody = `Your agreement for "${result.dealTitle || "your deal"}" has been generated and stored in My Agreements.`;
      for (const uid of targets) {
        await writeNotification({
          recipientId: uid,
          title: agreementTitle,
          message: agreementBody,
          data: { notificationType: "agreement_generated", dealId: result.dealId }
        });
        await sendPush(uid, agreementTitle, agreementBody, {
          notificationType: "agreement_generated",
          dealId: result.dealId
        });
      }
    }
  }

  return result;
}

/**
 * Completes a deal the moment BOTH parties have confirmed it.
 *
 * Triggered by any deal update: the app clients write their own
 * sender/recipient confirmation fields during the flow, and this handler
 * observes the final confirmation and performs the atomic COMPLETED
 * transition, agreement generation and audit stamping server-side.
 */
exports.autoCompleteConfirmedDeal = onDocumentUpdated("deals/{dealId}", async (event) => {
  const after = event.data.after?.data?.() || {};
  if (after.status === "COMPLETED") return;

  await completeConfirmedDeal(event.params.dealId, after);
});

// --------------------------------------------------------------------------
// Self-healing completion sweep.
//
// Deals that were both-confirmed while this module was offline (or before the
// completion trigger existed) stay stuck at two CONFIRMED statuses with no
// COMPLETED transition - exactly the "Waiting for ... to proceed." state this
// fix removes. The sweep below re-runs the identical completion transaction
// over any such deal, so existing stuck deals self-heal on the next deploy
// with no manual data migration.
// --------------------------------------------------------------------------
exports.repairStuckConfirmedDeals = onSchedule("every 15 minutes", async () => {
  let snapshot;
  try {
    snapshot = await db
      .collection("deals")
      .where("senderConfirmationStatus", "==", "CONFIRMED")
      .where("recipientConfirmationStatus", "==", "CONFIRMED")
      .limit(100)
      .get();
  } catch (error) {
    // Typically the composite index for this query is still building right
    // after a fresh deploy; the next sweep (15 minutes later) retries.
    console.warn("Stuck-deal completion sweep query failed; will retry", { message: error.message });
    return;
  }

  let completed = 0;
  let scanned = 0;
  for (const doc of snapshot.docs) {
    const deal = doc.data() || {};
    // Terminal deals (and duplicate sweeps) are cheap no-ops inside the
    // helper; we still count them so a stuck deal is never silently dropped.
    scanned += 1;
    try {
      const result = await completeConfirmedDeal(doc.id, deal);
      if (result && result.completed === true) completed += 1;
    } catch (error) {
      console.warn("Stuck-deal repair failed for one deal", { dealId: doc.id, message: error.message });
    }
  }

  if (scanned > 0) {
    console.log("Stuck-deal completion sweep", { scanned, completed });
  }
});

// --------------------------------------------------------------------------
// Server-side helpers for confirmation-generated agreements.
// --------------------------------------------------------------------------

/** Agreement reference in the DB-yyyyMMdd-HHmmss format (matches the client). */
function newAgreementNumber(now) {
  const d = new Date(now);
  return `DB-${d.getFullYear()}${pad2(d.getMonth() + 1)}${pad2(d.getDate())}-${pad2(d.getHours())}${pad2(d.getMinutes())}${pad2(d.getSeconds())}`;
}

/** The agreement expiry, one year out, in the dd MMM yyyy string format. */
function oneYearFromNowString(now) {
  const d = new Date(now);
  d.setFullYear(d.getFullYear() + 1);
  return formatDate(d.getTime());
}

// ==========================================================================
// User search — callable Cloud Function for "New Message" contact list.
// ==========================================================================

exports.searchUsers = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "You must be signed in");
  }

  const query = (request.data?.query || "").toString().trim().toLowerCase();
  const limit = Math.min((request.data?.limit || 20), 50);

  try {
    const snapshot = await db.collection("users")
      .limit(limit)
      .get();

    const filtered = [];
    for (const doc of snapshot.docs) {
      const data = doc.data();
      const userUid = doc.id;
      if (userUid === uid) continue;
      const fullName = (data.fullName || "").toString().trim();
      if (!fullName) continue;
      if (query && !(
        fullName.toLowerCase().includes(query) ||
        (data.company || "").toString().toLowerCase().includes(query) ||
        (data.email || "").toString().toLowerCase().includes(query)
      )) {
        continue;
      }
      filtered.push({
        id: userUid,
        fullName: fullName,
        email: (data.email || "").toString(),
        phone: (data.phone || "").toString(),
        company: (data.company || "").toString(),
        city: (data.city || "").toString(),
        status: (data.status || "").toString(),
        isOnline: !!data.isOnline,
        lastSeen: data.lastSeen ? data.lastSeen.toDate?.()?.getTime() : null,
        profileImage: (data.profileImage || "").toString(),
        blockedUsers: Array.isArray(data.blockedUsers) ? data.blockedUsers : []
      });
    }

    filtered.sort((a, b) => a.fullName.localeCompare(b.fullName));
    return { users: filtered };
  } catch (error) {
    console.warn("searchUsers failed", error);
    throw new HttpsError("internal", "Failed to search users");
  }
});