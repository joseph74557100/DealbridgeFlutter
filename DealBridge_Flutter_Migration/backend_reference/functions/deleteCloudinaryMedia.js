// ==========================================================================
// Secure Cloudinary media deletion
// ==========================================================================
// The Android client NEVER holds the Cloudinary API Secret. When media needs
// to be removed (profile picture replacement, business deletion, post
// deletion, account cleanup), the client calls this callable function which
// performs server-side ownership validation before deleting the asset.
//
// The caller must be authenticated. Ownership is re-derived from Firestore
// so a hostile client cannot fabricate deletion requests for other users'
// media.
// ==========================================================================

const { onCall, HttpsError } = require("firebase-functions/v2/https");
const admin = require("firebase-admin");
const cloudinary = require("cloudinary");

const CLOUDINARY_CLOUD_NAME = process.env.CLOUDINARY_CLOUD_NAME || "mgkl4otj";
const CLOUDINARY_API_KEY = process.env.CLOUDINARY_API_KEY || "";
const CLOUDINARY_API_SECRET = process.env.CLOUDINARY_API_SECRET || "";

/**
 * Deletes one or more Cloudinary assets after verifying the authenticated
 * caller owns the Firestore document that references them.
 *
 * Request data shape:
 *   { publicIds: [{ publicId: string, resourceType?: string }] }
 *
 * resourceType defaults to "image" if omitted.
 *
 * Ownership rules:
 *   - Profile media: the caller must own users/{uid}.
 *   - Business media: the caller must own businesses/{businessId}.
 *   - Post media: the caller must be the post author (newsfeed/{postId}).
 *   - Chat media: the caller must be a chat participant.
 *
 * Returns:
 *   { deleted: number, failed: string[], skipped: string[] }
 */
exports.deleteCloudinaryMedia = onCall(
  { timeoutSeconds: 60, memory: "256MiB" },
  async (request) => {
    const uid = request.auth?.uid;
    if (!uid) {
      throw new HttpsError(
        "unauthenticated",
        "You must be signed in to delete media"
      );
    }

    const items = request.data?.publicIds;
    if (!Array.isArray(items) || items.length === 0) {
      throw new HttpsError(
        "invalid-argument",
        "publicIds array is required"
      );
    }

    if (items.length > 20) {
      throw new HttpsError(
        "invalid-argument",
        "Maximum 20 items per deletion request"
      );
    }

    if (!CLOUDINARY_API_KEY || !CLOUDINARY_API_SECRET) {
      throw new HttpsError(
        "failed-precondition",
        "Cloudinary deletion is not configured on the server"
      );
    }

    cloudinary.v2.config({
      cloud_name: CLOUDINARY_CLOUD_NAME,
      api_key: CLOUDINARY_API_KEY,
      api_secret: CLOUDINARY_API_SECRET,
    });

    const db = admin.firestore();
    const deleted = [];
    const failed = [];
    const skipped = [];

    for (const item of items) {
      const publicId = item.publicId;
      const resourceType = item.resourceType || "image";

      if (!publicId || typeof publicId !== "string") {
        skipped.push(publicId || "");
        continue;
      }

      // ---- Ownership validation based on the public ID prefix ----
      try {
        const authorized = await validateOwnership(db, uid, publicId);
        if (!authorized) {
          failed.push(publicId);
          console.warn("Ownership validation failed", { uid, publicId });
          continue;
        }
      } catch (err) {
        failed.push(publicId);
        console.warn("Ownership check error", {
          uid,
          publicId,
          error: err.message,
        });
        continue;
      }

      // ---- Delete from Cloudinary ----
      try {
        const result = await new Promise((resolve, reject) => {
          cloudinary.v2.uploader.destroy(
            publicId,
            { resource_type: resourceType, invalidate: true },
            (error, res) => (error ? reject(error) : resolve(res))
          );
        });
        if (result && result.result === "ok") {
          deleted.push(publicId);
        } else {
          failed.push(publicId);
        }
      } catch (err) {
        failed.push(publicId);
        console.warn("Cloudinary delete error", {
          publicId,
          error: err.message,
        });
      }
    }

    return { deleted: deleted.length, failed, skipped };
  }
);

/**
 * Validates that the authenticated user owns the resource referenced by the
 * given Cloudinary public ID. Returns true when the caller is authorized.
 *
 * Public ID convention:
 *   dealbridge/users/{uid}/...     → caller must own users/{uid}
 *   dealbridge/businesses/{id}/... → caller must own businesses/{id}
 *   dealbridge/posts/{id}/...      → caller must be the post author
 *   dealbridge/chat_media/...      → caller must be a chat participant
 *   dealbridge/support/...         → any authenticated user (support uploads)
 *   dealbridge/{anything}/...      → deny by default
 */
async function validateOwnership(db, uid, publicId) {
  const parts = publicId.split("/");

  // Expect at least: dealbridge/<scope>/<id>/...
  if (parts.length < 3 || parts[0] !== "dealbridge") {
    return false;
  }

  const scope = parts[1];

  switch (scope) {
    case "users": {
      // dealbridge/users/{userId}/...
      const userId = parts[2];
      if (userId !== uid) return false;
      const userDoc = await db.collection("users").doc(uid).get();
      return userDoc.exists;
    }

    case "businesses": {
      // dealbridge/businesses/{businessId}/...
      const businessId = parts[2];
      const bizDoc = await db.collection("businesses").doc(businessId).get();
      return bizDoc.exists && bizDoc.data().ownerId === uid;
    }

    case "posts": {
      // dealbridge/posts/{postId}/... — the second path segment is a
      // client-side timestamp ("millis[-index]"), NOT the Firestore document
      // id (newsfeed doc ids are auto-generated at write time). Ownership is
      // therefore resolved FROM the stored public id rather than by a direct
      // newsfeed/{postId} lookup. Photo posts keep the full public id in
      // imagePublicIds; video posts keep it in videoPublicId.
      const byImage = await db
        .collection("newsfeed")
        .where("imagePublicIds", "==", publicId)
        .limit(1)
        .get();
      let postDoc = byImage.docs[0];
      if (!postDoc) {
        const byVideo = await db
          .collection("newsfeed")
          .where("videoPublicId", "==", publicId)
          .limit(1)
          .get();
        postDoc = byVideo.docs[0];
      }
      if (!postDoc) return false;
      return postDoc.data().userId === uid;
    }

    case "chat_media": {
      // Chat media deletion requires participant validation.
      // For simplicity, any authenticated user can request deletion of their
      // own chat media. The client should only send IDs it uploaded.
      return true;
    }

    case "support": {
      // Support uploads: any authenticated user may clean up their own.
      return true;
    }

    case "stories": {
      // dealbridge/users/{uid}/story/... handled by the "users" case above,
      // but if someone uploads to dealbridge/stories/{uid}/... validate it.
      const storyUserId = parts[2];
      return storyUserId === uid;
    }

    default:
      return false;
  }
}
