const { onSchedule } = require("firebase-functions/v2/scheduler");
const admin = require("firebase-admin");
const cloudinary = require("cloudinary");

// NOTE: The default Firebase app is initialized in index.js before this module
// is required. Calling admin.initializeApp() here too would throw
// "The default Firebase app already exists", breaking every exported function
// on cold start. Reuse the app initialized in index.js.
const CLOUDINARY_CLOUD_NAME = process.env.CLOUDINARY_CLOUD_NAME || "";
const CLOUDINARY_API_KEY = process.env.CLOUDINARY_API_KEY || "";
const CLOUDINARY_API_SECRET = process.env.CLOUDINARY_API_SECRET || "";

// Configure Cloudinary for admin operations (delete)
if (CLOUDINARY_CLOUD_NAME && CLOUDINARY_API_KEY && CLOUDINARY_API_SECRET) {
  cloudinary.v2.config({
    cloud_name: CLOUDINARY_CLOUD_NAME,
    api_key: CLOUDINARY_API_KEY,
    api_secret: CLOUDINARY_API_SECRET
  });
}

/**
 * Scheduled function to clean up old temporary chat media from Cloudinary.
 *
 * This runs daily and deletes chat media files that are older than 7 days.
 * The assumption is that by then, all recipients have downloaded the media
 * to their local devices.
 *
 * Security: Only deletes files in the chat_media/ folder on Cloudinary.
 */
exports.cleanupOldChatMedia = onSchedule("every 24 hours", async (event) => {
  if (!CLOUDINARY_API_KEY || !CLOUDINARY_API_SECRET) {
    console.warn("Cloudinary credentials not configured, skipping cleanup");
    return;
  }

  try {
    const sevenDaysAgo = Date.now() - 7 * 24 * 60 * 60 * 1000;

    // Search for old chat media resources
    // Cloudinary search API for unsigned uploads in dealbridge/chat_media/ folder
    const result = await cloudinary.v2.search
      .expression("(folder:dealbridge/chat_media OR folder:chat_media) AND created_at<=" + new Date(sevenDaysAgo).toISOString())
      .sort_by("created_at", "asc")
      .max_results(500)
      .execute();

    const resources = result.resources || [];
    console.log(`Found ${resources.length} old chat media files to clean up`);

    if (resources.length === 0) return;

    // Delete resources in batches
    const publicIds = resources.map(r => r.public_id);
    const resourceType = resources[0]?.resource_type || "image";

    if (publicIds.length > 0) {
      const deleteResult = await cloudinary.v2.api.delete_resources(publicIds, {
        resource_type: resourceType
      });

      console.log("Cleanup complete", {
        deleted: Object.keys(deleteResult.deleted || {}).length,
        not_found: Object.keys(deleteResult.not_found || {}).length
      });
    }
  } catch (error) {
    console.error("Chat media cleanup failed:", error.message);
  }
});

/**
 * Callable function to mark a chat media as delivered.
 * This can be called by the client after successfully downloading media.
 * For now it's a no-op since we use time-based cleanup, but it provides
 * an API hook for future optimization.
 */
const { onCall, HttpsError } = require("firebase-functions/v2/https");

exports.markMediaDelivered = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "Must be signed in");
  }

  const { messageId, mediaUrl } = request.data || {};
  if (!messageId || !mediaUrl) {
    throw new HttpsError("invalid-argument", "messageId and mediaUrl required");
  }

  // For now, just log it. In the future, we could track delivery status
  // and clean up immediately after both parties have downloaded.
  console.log("Media delivered", { uid, messageId, mediaUrl: mediaUrl.substring(0, 100) });

  return { success: true };
});
