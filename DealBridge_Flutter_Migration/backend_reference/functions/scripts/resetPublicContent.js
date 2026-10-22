/*
 * DealBridge — Public Content Reset (one-shot admin script)
 * ==========================================================
 * Gives the platform a fresh start for PUBLIC content only:
 *   - newsfeed/            ALL posts + their comments subcollections
 *   - stories/             ALL stories
 *   - businesses/          ALL businesses (public/business discovery data)
 *   - promotions/          ALL promotional content
 *
 * It NEVER touches private/user data: users, profiles, personalChats,
 * deals, agreements, notifications, auditLogs, adminReviews,
 * securityCounters, verificationRequests, reports, sessions, etc.
 *
 * The app has no seeding code, so once these documents are gone they do
 * not come back: on the next launch with an internet connection the app's
 * snapshot listeners sync the (now empty) collections, replacing any
 * locally cached copy. Users can then create new businesses, posts and
 * stories normally — nothing here changes how features work.
 *
 * Usage (run from the functions directory, node 20, firebase-admin v12):
 *
 *   1. Download a service account key for the project:
 *      Project Settings -> Service accounts -> Generate new private key
 *      (save it as serviceAccountKey.json next to this script)
 *
 *   2. Install dependencies once (or use the same install you deploy with):
 *      npm install
 *
 *   3. DRY RUN first — prints how many documents exist, deletes nothing:
 *      GOOGLE_APPLICATION_CREDENTIALS=serviceAccountKey.json \
 *        node scripts/resetPublicContent.js
 *
 *   4. Execute the reset when you are ready:
 *      GOOGLE_APPLICATION_CREDENTIALS=serviceAccountKey.json \
 *        node scripts/resetPublicContent.js --yes
 *
 *   5. (Optional) Restrict to specific collections:
 *      ... node scripts/resetPublicContent.js --yes --only=newsfeed,stories
 *
 * Deleting is the deliberate, irreversible step: keep the dry-run output
 * to confirm the counts are what you expect before passing --yes.
 */

const admin = require("firebase-admin");
const fs = require("fs");
const path = require("path");

// ---------------------------------------------------------------- config

// Public collections that are being reset. `newsfeed` is deleted
// recursively so every post AND its comments subcollection is removed.
const COLLECTIONS = {
  newsfeed: "Newsfeed posts (+ comments)",
  stories: "Stories",
  businesses: "Businesses (public discovery)",
  promotions: "Promotional content"
};

// Collections that are NEVER touched by this script, listed for clarity.
const NEVER_TOUCHED = [
  "users", "personalChats", "deals", "agreements", "notifications",
  "auditLogs", "adminReviews", "securityCounters", "verificationRequests",
  "supportRequests", "problemReports", "businessReports", "userReports",
  "featureRequests", "adminConfig"
];

// ---------------------------------------------------------------- helpers

function parseArgs(argv) {
  const yes = argv.includes("--yes");
  const onlyIndex = argv.indexOf("--only");
  let only = null;
  if (onlyIndex !== -1 && argv[onlyIndex + 1]) {
    only = argv[onlyIndex + 1].split(",").map((s) => s.trim()).filter(Boolean);
  }
  return { yes, only };
}

function resolveCredentials(argv) {
  const envKey = process.env.GOOGLE_APPLICATION_CREDENTIALS;
  const scriptDir = __dirname;
  const nearby = path.join(scriptDir, "serviceAccountKey.json");
  const candidates = [envKey, nearby].filter(Boolean);
  for (const candidate of candidates) {
    if (fs.existsSync(candidate)) return candidate;
  }
  return null;
}

async function countDocs(db, name) {
  try {
    const snapshot = await db.collection(name).count().get();
    return snapshot.data().count;
  } catch (_) {
    // Fallback for very large collections or emulators without aggregates.
    const snapshot = await db.collection(name).get();
    return snapshot.size;
  }
}

function human(n) {
  return `${n} document${n === 1 ? "" : "s"}`;
}

async function main() {
  const { yes, only } = parseArgs(process.argv.slice(2));

  const selected = only || Object.keys(COLLECTIONS);

  const keyFile = resolveCredentials(process.argv);
  if (!keyFile) {
    console.error(
      "No service account key found.\n" +
      "Set GOOGLE_APPLICATION_CREDENTIALS to your service account JSON, or\n" +
      "place serviceAccountKey.json next to this script."
    );
    process.exit(1);
  }

  try {
    admin.initializeApp({
      credential: admin.credential.cert(keyFile)
    });
  } catch (error) {
    console.error("Failed to initialize Firebase Admin SDK:", error.message);
    process.exit(1);
  }
  const db = admin.firestore();
  db.settings({ ignoreUndefinedProperties: true });

  console.log("DealBridge public content reset\n");

  if (!yes) {
    console.log("DRY RUN — nothing will be deleted.\n");
  } else {
    console.log("WARNING: deleting. This is irreversible.\n");
  }

  console.log("Collections to reset:");
  for (const name of selected) {
    if (COLLECTIONS[name]) {
      console.log(`  - ${name}  (${COLLECTIONS[name]})`);
    }
  }
  console.log("\nNEVER touched (private/user data stays intact):");
  for (const name of NEVER_TOUCHED) {
    console.log(`  - ${name}`);
  }
  console.log("");

  let total = 0;
  for (const name of selected) {
    if (!COLLECTIONS[name]) {
      console.warn(`  Skipping unknown collection "${name}".`);
      continue;
    }
    const count = await countDocs(db, name);
    total += count;
    console.log(`  ${name}: ${human(count)}`);
  }
  console.log(`  TOTAL PUBLIC CONTENT: ${human(total)}\n`);

  if (!yes) {
    console.log("Dry run complete. Re-run with --yes to delete.");
    process.exit(0);
  }

  if (total === 0) {
    console.log("Nothing to delete — all public collections are already empty.");
    process.exit(0);
  }

  for (const name of selected) {
    if (!COLLECTIONS[name]) continue;
    console.log(`Deleting ${name} ...`);
    // recursiveDelete removes every document AND any nested subcollection
    // (e.g. newsfeed/{postId}/comments), in batches, until the path is empty.
    await db.recursiveDelete(db.collection(name));
  }

  console.log("\nVerifying ...");
  let remaining = 0;
  for (const name of selected) {
    const count = await countDocs(db, name);
    remaining += count;
    console.log(`  ${name}: ${human(count)} remaining`);
  }

  if (remaining === 0) {
    console.log(
      "\nDone. Public content is cleared — DealBridge now starts fresh.\n" +
      "Existing accounts, chats, deals, agreements and profiles are untouched.\n" +
      "Users can now create new businesses, posts and stories normally."
    );
    process.exit(0);
  }
  console.error(
    `\nAttention: ${human(remaining)} documents could not be deleted.\n` +
    "Large collections delete in background batches; re-run this script\n" +
    "after a minute to finish the job."
  );
  process.exit(1);
}

main().catch((error) => {
  console.error("Reset failed:", error);
  process.exit(1);
});