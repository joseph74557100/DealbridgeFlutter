// ==========================================================================
// Business Ratings — server-authoritative rating aggregation.
//
// Clients write individual rating documents into
// `businesses/{businessId}/ratings/{raterId}_{dealId}`. Every write is
// validated by Firestore rules (only after a COMPLETED deal). The parent
// business document's `rating` (average) and `ratingCount` fields are
// recomputed HERE on every create/update/delete so no client can ever
// influence the displayed average directly.
// ==========================================================================

const { onDocumentWritten } = require("firebase-functions/v2/firestore");
const admin = require("firebase-admin");

const db = admin.firestore();

exports.onRatingWritten = onDocumentWritten(
  "businesses/{businessId}/ratings/{ratingId}",
  async (event) => {
    const { businessId } = event.params;

    try {
      const snap = await db
        .collection("businesses")
        .doc(businessId)
        .collection("ratings")
        .get();

      let sum = 0;
      let count = 0;
      snap.forEach((doc) => {
        const stars = Number(doc.data().stars) || 0;
        if (stars >= 1 && stars <= 5) {
          sum += stars;
          count += 1;
        }
      });

      const average = count > 0 ? Math.round((sum / count) * 10) / 10 : 0;

      await db.collection("businesses").doc(businessId).update({
        rating: average,
        ratingCount: count
      });

      console.log("Business rating aggregate updated", {
        businessId,
        average,
        count,
        eventId: event.id
      });
    } catch (error) {
      console.warn("Rating aggregate update failed", {
        businessId,
        message: error.message
      });
    }
  }
);