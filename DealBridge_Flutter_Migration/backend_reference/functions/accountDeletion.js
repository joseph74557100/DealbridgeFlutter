// ==========================================================================
// Account deletion (Google Play account-deletion requirement)
// ==========================================================================
// The authenticated caller's uid (`context.auth.uid`) is the ONLY deletion
// target; a client-supplied uid is never trusted, so one user can never
// delete another user's data.
//
// Deletion policy:
//  - Personal data (profile, sessions, saved businesses, follows, own
//    conversations, notifications, revenue, stories, support submissions,
//    verification requests) is deleted.
//  - Signed agreements are NEVER deleted. They are legal records: the
//    document and its PDF are preserved and only the deleted account's
//    identity references are anonymized.
//  - Active transaction records (deals) and shared conversation history are
//    anonymized rather than destroyed, so other participants keep their
//    records.
//  - A business owned by the deleted account is deleted ONLY when it has no
//    deals, agreements, chats or other-user references. Otherwise it is
//    retained and reported for admin attention.
//  - Media uploaded to Cloudinary is deleted best-effort (the API secret only
//    ever exists server-side). Signed agreement PDFs/signatures are exempt.
//  - The Firebase Auth account is deleted LAST, only after the server-side
//    cleanup succeeds. A failed cleanup aborts without deleting the account.
// ==========================================================================

const { onCall, HttpsError } = require("firebase-functions/v2/https");
const admin = require("firebase-admin");
const cloudinary = require("cloudinary");

const ONESIGNAL_APP_ID =
  process.env.ONESIGNAL_APP_ID || "30da6324-74cd-4c1c-9abe-cfe0887a8a2e";
const ONESIGNAL_REST_API_KEY = process.env.ONESIGNAL_REST_API_KEY || "";

const CLOUDINARY_CLOUD_NAME = process.env.CLOUDINARY_CLOUD_NAME || "mgkl4otj";
const CLOUDINARY_API_KEY = process.env.CLOUDINARY_API_KEY || "";
const CLOUDINARY_API_SECRET = process.env.CLOUDINARY_API_SECRET || "";

/** Fetches every document matching a query, paginating past the 500-doc cap. */
async function queryAll(query) {
  const docs = [];
  let last = null;
  for (;;) {
    const q = last ? query.limit(400).startAfter(last) : query.limit(400);
    const snapshot = await q.get();
    if (snapshot.empty) break;
    docs.push(...snapshot.docs);
    last = snapshot.docs[snapshot.docs.length - 1];
    if (snapshot.docs.length < 400) break;
  }
  return docs;
}

/** Commits delete/set (merge) operations in Firestore batches of <= 400. */
async function commitOps(ops) {
  for (let i = 0; i < ops.length; i += 400) {
    const batch = admin.firestore().batch();
    ops.slice(i, i + 400).forEach((op) => {
      if (op.type === "delete") batch.delete(op.ref);
      else if (op.type === "set") batch.set(op.ref, op.data, { merge: true });
    });
    await batch.commit();
  }
}

/** Extracts the public id + resource type from a Cloudinary delivery URL. */
function parseCloudinaryUrl(url) {
  if (!url || !url.includes("res.cloudinary.com")) return null;
  const clean = url.split("?")[0];
  const match = clean.match(/\/upload\/(?:v\d+\/)?(.+)$/);
  if (!match) return null;
  const resourceType = clean.includes("/video/upload/")
    ? "video"
    : clean.includes("/raw/upload/")
      ? "raw"
      : "image";
  // DealBridge public ids never contain dots; only the trailing format suffix
  // is stripped, which is safe for every asset this app uploads.
  const publicId = match[1].replace(/\.[a-zA-Z0-9]{2,5}$/, "");
  return { publicId, resourceType };
}

async function deleteCloudinaryAssets(urls, report) {
  if (!urls || urls.size === 0) {
    report.cloudinary = "none";
    return;
  }
  if (!CLOUDINARY_API_KEY || !CLOUDINARY_API_SECRET) {
    report.cloudinary = "skipped (CLOUDINARY_API_KEY/SECRET not configured)";
    report.cloudinaryFailed = [];
    return;
  }
  cloudinary.v2.config({
    cloud_name: CLOUDINARY_CLOUD_NAME,
    api_key: CLOUDINARY_API_KEY,
    api_secret: CLOUDINARY_API_SECRET
  });

  const failed = [];
  for (const url of urls) {
    const parsed = parseCloudinaryUrl(url);
    if (!parsed) continue;
    try {
      const result = await new Promise((resolve, reject) => {
        cloudinary.v2.uploader.destroy(
          parsed.publicId,
          { resource_type: parsed.resourceType, invalidate: true },
          (error, res) => (error ? reject(error) : resolve(res))
        );
      });
      if (!result || result.result !== "ok") failed.push(url);
    } catch (_) {
      failed.push(url);
    }
  }
  report.cloudinaryDeleted = urls.size - failed.length;
  report.cloudinaryFailed = failed;
  report.cloudinary = "done";
}

/** Deletes the OneSignal user record (all subscriptions) for an external id. */
async function deleteOneSignalUser(uid, report) {
  if (!ONESIGNAL_REST_API_KEY) {
    report.onesignal = "skipped (ONESIGNAL_REST_API_KEY not configured)";
    return;
  }
  try {
    const response = await fetch(
      `https://api.onesignal.com/apps/${ONESIGNAL_APP_ID}/users/by/external_id/${encodeURIComponent(uid)}`,
      {
        method: "DELETE",
        headers: {
          Authorization: `Bearer ${ONESIGNAL_REST_API_KEY}`
        }
      }
    );
    report.onesignal = response.ok ? "deleted" : `failed (HTTP ${response.status})`;
  } catch (_) {
    report.onesignal = "failed (network error)";
  }
}

/**
 * True when a business owned by the deleted account must be retained because
 * other users or active transactions depend on it. Retained businesses are
 * reported for admin attention instead of being destroyed.
 */
async function businessHasActiveRecords(businessId, ownerUid) {
  const [agreements, deals, businessThreads, legacyMessages, conversations] =
    await Promise.all([
      admin
        .firestore()
        .collection("agreements")
        .where("participantIds", "array-contains", businessId)
        .limit(1)
        .get(),
      admin
        .firestore()
        .collection("deals")
        .where("businessId", "==", businessId)
        .limit(1)
        .get(),
      admin
        .firestore()
        .collection("businessChats")
        .where("participantIds", "array-contains", businessId)
        .limit(1)
        .get(),
      admin
        .firestore()
        .collection("chats")
        .doc(businessId)
        .collection("messages")
        .limit(1)
        .get(),
      admin
        .firestore()
        .collection("conversations")
        .where("businessId", "==", businessId)
        .limit(401)
        .get()
    ]);

  if (!agreements.empty || !deals.empty || !businessThreads.empty || !legacyMessages.empty) {
    return true;
  }
  // Any other user who keeps a conversation referencing this business means
  // deleting the business would break their inbox.
  for (const conversation of conversations.docs) {
    const userId = conversation.data().userId;
    if (userId && userId !== ownerUid) return true;
  }
  return false;
}

/**
 * True when the given uid is a configured admin (admin custom-claim OR listed
 * in the adminConfig/admins.adminUids document). Used to gate the
 * admin-only `adminDeleteUser` callable.
 */
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
    // Fall through to the adminConfig document check.
  }
  try {
    const cfg = await admin.firestore().collection("adminConfig").doc("admins").get();
    if (cfg.exists) {
      const uids = cfg.data().adminUids || [];
      if (uids.includes(uid)) return true;
    }
  } catch (_) {
    // Fall through to the live admins document check.
  }
  // Live admins/{uid} document with active == true. No hard-coded UIDs.
  try {
    const doc = await admin.firestore().collection("admins").doc(uid).get();
    if (doc.exists && doc.data().active === true) return true;
  } catch (_) {
    // Fall through.
  }
  return false;
}

/**
 * Core deletion pipeline shared by the self-serve `deleteAccount` callable
 * and the admin-driven `adminDeleteUser` callable.
 *
 * Safe and idempotent: every query tolerates already-deleted documents,
 * commits run in bounded batches, missing documents are no-ops, and a retry
 * resumes where a previous run stopped.
 */
async function runCleanup(uid) {
    const db = admin.firestore();
    const userDocRef = db.collection("users").doc(uid);
    const userDoc = await userDocRef.get();
    const userData = userDoc.exists ? userDoc.data() : {};
    const report = {
      success: true,
      deleted: [],
      anonymized: [],
      retained: [],
      requiresAdminAttention: [],
      cloudinaryDeleted: 0,
      cloudinaryFailed: [],
      cloudinary: "none",
      onesignal: "skipped"
    };
    const mediaUrls = new Set();
    const ops = [];

    // ------------------------------------------------------------------
    // 1. Profile + per-user subcollections.
    // ------------------------------------------------------------------
    if (userData.profileImage) mediaUrls.add(userData.profileImage);
    if (userData.coverImage) mediaUrls.add(userData.coverImage);

    for (const sub of [
      "savedBusinesses",
      "followedUsers",
      "sessions",
      "savedPosts"
    ]) {
      const subDocs = await queryAll(db.collection(`users/${uid}/${sub}`));
      subDocs.forEach((d) => ops.push({ type: "delete", ref: d.ref }));
    }
    ops.push({ type: "delete", ref: db.doc(`users/${uid}`) });
    report.deleted.push(`users/${uid}`);

    // ------------------------------------------------------------------
    // 2. Owned businesses: decide which to delete vs retain.
    // ------------------------------------------------------------------
    const ownedBusinesses = await queryAll(
      db.collection("businesses").where("ownerId", "==", uid)
    );
    const retainedIds = new Set();
    const deletableIds = [];

    for (const businessSnap of ownedBusinesses) {
      const businessId = businessSnap.id;
      if (await businessHasActiveRecords(businessId, uid)) {
        retainedIds.add(businessId);
        report.retained.push(`businesses/${businessId}`);
        report.requiresAdminAttention.push(`businesses/${businessId}`);
      } else {
        deletableIds.push(businessId);
      }
    }

    // ------------------------------------------------------------------
    // 3. Delete the safe-to-delete businesses and their content.
    // ------------------------------------------------------------------
    for (const businessId of deletableIds) {
      const businessSnap = await db.doc(`businesses/${businessId}`).get();
      const businessData = businessSnap.exists ? businessSnap.data() : {};
      if (businessData.logoUrl) mediaUrls.add(businessData.logoUrl);
      if (businessData.promoVideoUrl) mediaUrls.add(businessData.promoVideoUrl);
      (businessData.gallery || []).forEach((url) => mediaUrls.add(url));

      // Newsfeed posts + comments for the business.
      const posts = await queryAll(
        db.collection("newsfeed").where("businessId", "==", businessId)
      );
      for (const post of posts) {
        const postData = post.data() || {};
        (postData.imageUrls || []).forEach((url) => mediaUrls.add(url));
        if (postData.videoUrl) mediaUrls.add(postData.videoUrl);
        const comments = await queryAll(db.collection(`newsfeed/${post.id}/comments`));
        comments.forEach((c) => ops.push({ type: "delete", ref: c.ref }));
        ops.push({ type: "delete", ref: post.ref });
      }

      // Promotions for the business.
      const promotions = await queryAll(
        db.collection("promotions").where("businessId", "==", businessId)
      );
      for (const promotion of promotions) {
        const promoData = promotion.data() || {};
        if (promoData.imageUrl) mediaUrls.add(promoData.imageUrl);
        ops.push({ type: "delete", ref: promotion.ref });
      }

      // Legacy chat messages + presence under chats/{businessId}.
      const legacyMessages = await queryAll(
        db.collection(`chats/${businessId}/messages`)
      );
      for (const message of legacyMessages) {
        const messageData = message.data() || {};
        if (messageData.mediaUrl && messageData.senderId === uid) {
          mediaUrls.add(messageData.mediaUrl);
        }
        ops.push({ type: "delete", ref: message.ref });
      }
      const legacyPresence = await queryAll(
        db.collection(`chats/${businessId}/presence`)
      );
      legacyPresence.forEach((p) => ops.push({ type: "delete", ref: p.ref }));

      // Business-to-business chat threads involving the business. A deletable
      // business should never have threads (that would retain it), but this
      // cleans up defensively if one slips through.
      const threads = await queryAll(
        db.collection("businessChats").where("participantIds", "array-contains", businessId)
      );
      for (const thread of threads) {
        const messages = await queryAll(
          db.collection(`businessChats/${thread.id}/messages`)
        );
        messages.forEach((m) => {
          if (m.data().mediaUrl) mediaUrls.add(m.data().mediaUrl);
          ops.push({ type: "delete", ref: m.ref });
        });
        const threadPresence = await queryAll(
          db.collection(`businessChats/${thread.id}/presence`)
        );
        threadPresence.forEach((p) => ops.push({ type: "delete", ref: p.ref }));
        ops.push({ type: "delete", ref: thread.ref });
      }

      ops.push({ type: "delete", ref: db.doc(`businesses/${businessId}`) });
      report.deleted.push(`businesses/${businessId}`);
    }

    // ------------------------------------------------------------------
    // 4. Personal chat threads (one-to-one). Preserve the conversation for
    //    the other participant and anonymize this account's identity.
    // ------------------------------------------------------------------
    const orphanedMessagePaths = new Set();
    const personalThreads = await queryAll(
      db.collection("personalChats").where("participantIds", "array-contains", uid)
    );
    for (const thread of personalThreads) {
      const threadData = thread.data() || {};
      const participantIds = threadData.participantIds || [];
      const otherId = participantIds.find((id) => id && id !== uid);
      const otherExists = otherId
        ? (await db.doc(`users/${otherId}`).get()).exists
        : false;

      if (!otherExists) {
        // The other participant no longer exists: the thread is orphaned, so
        // delete it entirely.
        const messages = await queryAll(
          db.collection(`personalChats/${thread.id}/messages`)
        );
        for (const message of messages) {
          const messageData = message.data() || {};
          if (messageData.senderId === uid && messageData.mediaUrl) {
            mediaUrls.add(messageData.mediaUrl);
          }
          orphanedMessagePaths.add(message.ref.path);
          ops.push({ type: "delete", ref: message.ref });
        }
        ops.push({ type: "delete", ref: thread.ref });
        report.deleted.push(`personalChats/${thread.id}`);
      } else if (participantIds.includes(uid)) {
        // Keep the thread for the other participant but remove the deleted
        // account's identity everywhere it appears: the participant list, the
        // stored display names, the last-sender stamp and the per-user unread
        // counters, so no personal information about the deleted account
        // survives in the thread.
        const update = {
          participantIds: participantIds.map((id) => (id === uid ? "deleted" : id))
        };
        if (threadData.participantNames && typeof threadData.participantNames === "object") {
          update.participantNames = { ...threadData.participantNames };
          if (update.participantNames[uid]) update.participantNames[uid] = "Deleted User";
        }
        if (threadData.lastSenderId === uid) update.lastSenderId = "deleted";
        if (threadData.unreadCounts && typeof threadData.unreadCounts === "object") {
          update.unreadCounts = { ...threadData.unreadCounts };
          delete update.unreadCounts[uid];
        }
        ops.push({ type: "set", ref: thread.ref, data: update });
        report.anonymized.push(`personalChats/${thread.id}`);
      }
    }

    // ------------------------------------------------------------------
    // 5. Chat messages sent by / addressed to / involving this account, across
    //    ALL chat scopes (legacy chats/{businessId}, businessChats,
    //    personalChats). Other participants keep their history; the deleted
    //    account's identity and media are removed.
    // ------------------------------------------------------------------
    const messageUpdates = new Map();

    /** Queues every Cloudinary asset a message may reference. */
    function collectMessageMedia(messageData) {
      if (messageData.mediaUrl) mediaUrls.add(messageData.mediaUrl);
      if (messageData.videoUrl) mediaUrls.add(messageData.videoUrl);
      (messageData.attachmentUrls || []).forEach((url) => mediaUrls.add(url));
    }

    /**
     * Anonymizes one message wherever the deleted account appears (sender,
     * receiver, participant list, read/delivery receipts and reactions).
     * Multiple queries can surface the same message, so updates are merged per
     * document path instead of overwritten.
     */
    function anonymizeMessageForDeletedUser(ref, messageData) {
      if (orphanedMessagePaths.has(ref.path)) return;
      if (!messageData) return;

      let update = messageUpdates.get(ref.path);
      if (!update) {
        update = { ...messageData };
        messageUpdates.set(ref.path, update);
      }

      if (update.senderId === uid) {
        collectMessageMedia(update);
        update.senderId = "deleted";
        update.senderName = "Deleted User";
        if (update.mediaUrl) update.mediaUrl = "";
        if (update.videoUrl) update.videoUrl = "";
        if (Array.isArray(update.attachmentUrls)) update.attachmentUrls = [];
      }
      if (update.receiverId === uid) update.receiverId = "deleted";
      if (Array.isArray(update.participantIds) && update.participantIds.includes(uid)) {
        update.participantIds = update.participantIds.map((id) =>
          id === uid ? "deleted" : id
        );
      }
      if (Array.isArray(update.readBy) && update.readBy.includes(uid)) {
        update.readBy = update.readBy.filter((id) => id !== uid);
      }
      if (Array.isArray(update.deliveredTo) && update.deliveredTo.includes(uid)) {
        update.deliveredTo = update.deliveredTo.filter((id) => id !== uid);
      }
      if (update.reactions && typeof update.reactions === "object") {
        const next = {};
        for (const emoji of Object.keys(update.reactions)) {
          if (!Array.isArray(update.reactions[emoji])) continue;
          const ids = update.reactions[emoji].filter((id) => id !== uid);
          if (ids.length) next[emoji] = ids;
        }
        update.reactions = next;
      }
    }

    const messageQueries = [
      db.collectionGroup("messages").where("senderId", "==", uid),
      db.collectionGroup("messages").where("receiverId", "==", uid),
      // Covers messages where the deleted account is only a participant, e.g.
      // the owner of a business stamped into a legacy chats/{businessId} thread.
      db.collectionGroup("messages").where("participantIds", "array-contains", uid)
    ];
    for (const query of messageQueries) {
      const messages = await queryAll(query);
      for (const message of messages) {
        anonymizeMessageForDeletedUser(message.ref, message.data() || {});
      }
    }

    for (const [path, update] of messageUpdates) {
      ops.push({ type: "set", ref: db.doc(path), data: update });
    }

    // ------------------------------------------------------------------
    // 6. Deals. Delete cancelled/rejected deals entirely; keep active
    //    (PENDING/ACCEPTED) records for the other party anonymized so they
    //    don't show the deleted user but the deal remains for the other party.
    // ------------------------------------------------------------------
    const deals = await queryAll(
      db.collection("deals").where("participantIds", "array-contains", uid)
    );
    for (const deal of deals) {
      const dealData = deal.data() || {};
      const status = dealData.status || "Pending";
      const businessStillExists = dealData.businessId
        ? (await db.doc(`businesses/${dealData.businessId}`).get()).exists
        : false;

      // Cancelled deals are terminal — delete them so neither user sees them
      if (status === "CANCELLED") {
        ops.push({ type: "delete", ref: deal.ref });
        report.deleted.push(`deals/${deal.id}`);
      }
      // Rejected deals delete
      else if (status === "Rejected" || !businessStillExists) {
        ops.push({ type: "delete", ref: deal.ref });
        report.deleted.push(`deals/${deal.id}`);
      }
      // Keep active records for the other party, anonymizing the deleted user
      else {
        ops.push({
          type: "set",
          ref: deal.ref,
          data: {
            senderId: dealData.senderId === uid ? "deleted" : dealData.senderId,
            participantIds: (dealData.participantIds || []).map((id) =>
              id === uid ? "deleted" : id
            ),
            accountDeleted: true
          }
        });
        report.retained.push(`deals/${deal.id}`);
      }
    }

    // ------------------------------------------------------------------
    // 7. Agreements. Legal records: NEVER deleted. The PDF and signatures are
    //    preserved; only the deleted account's identity references are
    //    anonymized.
    // ------------------------------------------------------------------
    const agreements = await queryAll(
      db.collection("agreements").where("participantIds", "array-contains", uid)
    );
    for (const agreement of agreements) {
      const agreementData = agreement.data() || {};
      const update = {
        participantIds: (agreementData.participantIds || []).map((id) =>
          id === uid ? "deleted" : id
        )
      };
      if (agreementData.businessOneId === uid) update.businessOneId = "deleted";
      if (agreementData.businessTwoId === uid) update.businessTwoId = "deleted";
      const signatures = (agreementData.signatures || []).map((sig) => {
        if (sig && sig.signerUserId === uid) return { ...sig, signerUserId: "deleted" };
        return sig;
      });
      if (signatures.length) update.signatures = signatures;
      ops.push({ type: "set", ref: agreement.ref, data: update });
      report.retained.push(`agreements/${agreement.id}`);
    }

    // ------------------------------------------------------------------
    // 8. Stories, comments, promotions for deleted businesses (above),
    //    revenue, notifications, conversations, support submissions,
    //    verification requests and chat presence.
    // ------------------------------------------------------------------
    const stories = await queryAll(
      db.collection("stories").where("userId", "==", uid)
    );
    for (const story of stories) {
      const storyData = story.data() || {};
      if (storyData.imageUrl) mediaUrls.add(storyData.imageUrl);
      ops.push({ type: "delete", ref: story.ref });
      report.deleted.push(`stories/${story.id}`);
    }

    // Newsfeed posts authored directly by the user (social posts). Posts that
    // belong to a retained business are left intact.
    const userPosts = await queryAll(
      db.collection("newsfeed").where("userId", "==", uid)
    );
    for (const post of userPosts) {
      if (retainedIds.has(post.data().businessId || "")) continue;
      const postData = post.data() || {};
      (postData.imageUrls || []).forEach((url) => mediaUrls.add(url));
      if (postData.videoUrl) mediaUrls.add(postData.videoUrl);
      const comments = await queryAll(db.collection(`newsfeed/${post.id}/comments`));
      comments.forEach((c) => ops.push({ type: "delete", ref: c.ref }));
      ops.push({ type: "delete", ref: post.ref });
      report.deleted.push(`newsfeed/${post.id}`);
    }

    const myComments = await queryAll(
      db.collectionGroup("comments").where("userId", "==", uid)
    );
    for (const comment of myComments) {
      if (retainedIds.has(comment.data().businessId || "")) continue;
      ops.push({ type: "delete", ref: comment.ref });
    }

    const revenueDocs = await queryAll(
      db.collection("revenue").where("ownerId", "==", uid)
    );
    revenueDocs.forEach((r) => ops.push({ type: "delete", ref: r.ref }));

    const notifications = await queryAll(
      db.collection("notifications").where("recipientId", "==", uid)
    );
    notifications.forEach((n) => ops.push({ type: "delete", ref: n.ref }));

    // Likes/reactions created by the deleted account on OTHER users' posts.
    // The posts belong to other users and are preserved; only the deleted
    // user's like document (keyed by their uid) is removed.
    const myLikes = await queryAll(
      db.collectionGroup("likes").where(admin.firestore.FieldPath.documentId(), "==", uid)
    );
    myLikes.forEach((l) => ops.push({ type: "delete", ref: l.ref }));

    const conversations = await queryAll(
      db.collection("conversations").where("userId", "==", uid)
    );
    conversations.forEach((c) => ops.push({ type: "delete", ref: c.ref }));

    const supportRequests = await queryAll(
      db.collection("supportRequests").where("userId", "==", uid)
    );
    for (const request of supportRequests) {
      if (request.data().attachmentUrl) mediaUrls.add(request.data().attachmentUrl);
      ops.push({ type: "delete", ref: request.ref });
    }

    const problemReports = await queryAll(
      db.collection("problemReports").where("userId", "==", uid)
    );
    for (const problemDoc of problemReports) {
      if (problemDoc.data().screenshotUrl) mediaUrls.add(problemDoc.data().screenshotUrl);
      ops.push({ type: "delete", ref: problemDoc.ref });
    }

    const featureRequests = await queryAll(
      db.collection("featureRequests").where("userId", "==", uid)
    );
    featureRequests.forEach((r) => ops.push({ type: "delete", ref: r.ref }));

    const businessReports = await queryAll(
      db.collection("businessReports").where("reportedBy", "==", uid)
    );
    businessReports.forEach((r) => ops.push({ type: "delete", ref: r.ref }));

    const userReports = await queryAll(
      db.collection("userReports").where("reportedBy", "==", uid)
    );
    userReports.forEach((r) => ops.push({ type: "delete", ref: r.ref }));

    const postReports = await queryAll(
      db.collection("postReports").where("reportedBy", "==", uid)
    );
    postReports.forEach((r) => ops.push({ type: "delete", ref: r.ref }));

    const messageReports = await queryAll(
      db.collection("messageReports").where("reportedBy", "==", uid)
    );
    messageReports.forEach((r) => ops.push({ type: "delete", ref: r.ref }));

    const verificationRequests = await queryAll(
      db.collection("verificationRequests").where("ownerId", "==", uid)
    );
    verificationRequests.forEach((r) => ops.push({ type: "delete", ref: r.ref }));

    // Chat presence documents that reference this account.
    const presenceDocs = await queryAll(
      db.collectionGroup("presence").where("uid", "==", uid)
    );
    presenceDocs.forEach((p) => ops.push({ type: "delete", ref: p.ref }));

    // ------------------------------------------------------------------
    // 9. Commit all Firestore changes BEFORE touching auth/notifications so a
    //    failed cleanup never leaves an account without its data. The
    //    operation is idempotent, so a retry resumes where it stopped.
    // ------------------------------------------------------------------
    await commitOps(ops);

    // ------------------------------------------------------------------
    // 10. Clean up OneSignal and Cloudinary (best-effort, never fatal), then
    //     delete the Firebase Auth account last.
    // ------------------------------------------------------------------
    await deleteOneSignalUser(uid, report);
    await deleteCloudinaryAssets(mediaUrls, report);

    await admin.auth().deleteUser(uid);

    console.log("Account deleted", { uid, report });
    return report;
}

/**
 * Self-serve account deletion for the currently signed-in user (Google Play
 * account-deletion requirement). The caller's uid is the ONLY deletion
 * target; a client-supplied uid is never trusted, so one user can never
 * delete another user's data.
 */
exports.deleteAccount = onCall(
  { timeoutSeconds: 540, memory: "512MiB" },
  async (request) => {
    const uid = request.auth?.uid;
    if (!uid) {
      throw new HttpsError(
        "unauthenticated",
        "You must be signed in to delete your account"
      );
    }

    // Require recent re-authentication for account deletion.
    const userDoc = await admin.firestore().collection("users").doc(uid).get();
    const userData = userDoc.exists ? userDoc.data() : {};
    const lastReauth = userData.lastReauthenticatedAt || 0;
    const REAUTH_WINDOW_MS = 5 * 60 * 1000; // 5 minutes
    if (lastReauth === 0 || Date.now() - lastReauth > REAUTH_WINDOW_MS) {
      throw new HttpsError(
        "failed-precondition",
        "Recent authentication required. Please re-authenticate before deleting your account."
      );
    }

    return runCleanup(uid);
  }
);

/**
 * Admin-driven deletion of another user's account and all data owned by that
 * user (profile, businesses, posts, comments, saved content, notifications,
 * and other user-owned records — see runCleanup for the full policy).
 *
 * The caller MUST be a configured admin (custom claim or the
 * adminConfig/admins document). The client only submits the target uid; the
 * trusted backend performs the entire cleanup, so a hostile client can never
 * delete another user's data through Firestore directly.
 */
exports.adminDeleteUser = onCall(
  { timeoutSeconds: 540, memory: "512MiB" },
  async (request) => {
    const callerUid = request.auth?.uid;
    if (!callerUid) {
      throw new HttpsError(
        "unauthenticated",
        "You must be signed in to manage users"
      );
    }
    if (!(await isAdminUser(callerUid))) {
      throw new HttpsError(
        "permission-denied",
        "Only administrators can delete users"
      );
    }

    const targetUid = (request.data?.uid || "").toString();
    if (!targetUid) {
      throw new HttpsError("invalid-argument", "A user uid to delete is required");
    }
    if (targetUid === callerUid) {
      throw new HttpsError(
        "invalid-argument",
        "Admins cannot delete their own account through this flow; use your profile's Delete Account instead."
      );
    }

    const result = await runCleanup(targetUid);
    console.log("Admin deleted user", { byAdmin: callerUid, target: targetUid });
    return result;
  }
);
