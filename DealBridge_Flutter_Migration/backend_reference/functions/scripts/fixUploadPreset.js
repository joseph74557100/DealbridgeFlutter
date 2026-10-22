/*
 * DealBridge — Fix Cloudinary Upload Preset (one-shot admin script)
 * =================================================================
 * Disables Amazon Rekognition Auto Tagging on the "dealbridge_media"
 * upload preset. This fixes the HTTP 420 error:
 *   "You don't have an active subscription for Rekognition Auto Tagging"
 *
 * The preset is an UNSIGNED preset used by the Android client for all
 * media uploads (profile images, business logos, posts, chat media).
 *
 * Prerequisites:
 *   - CLOUDINARY_API_KEY and CLOUDINARY_API_SECRET must be set in the
 *     Firebase Functions environment, or passed as env vars:
 *       CLOUDINARY_API_KEY=xxx CLOUDINARY_API_SECRET=yyy node scripts/fixUploadPreset.js
 *
 * Usage (run from the functions directory, node 20):
 *
 *   1. DRY RUN (default) — shows current preset config, changes nothing:
 *        CLOUDINARY_API_KEY=xxx CLOUDINARY_API_SECRET=yyy \
 *          node scripts/fixUploadPreset.js
 *
 *   2. Execute the fix:
 *        CLOUDINARY_API_KEY=xxx CLOUDINARY_API_SECRET=yyy \
 *          node scripts/fixUploadPreset.js --yes
 */

const cloudinary = require("cloudinary");

const CLOUD_NAME = process.env.CLOUDINARY_CLOUD_NAME || "mgkl4otj";
const API_KEY = process.env.CLOUDINARY_API_KEY || "";
const API_SECRET = process.env.CLOUDINARY_API_SECRET || "";
const UPLOAD_PRESET = "dealbridge_media";

function parseArgs(argv) {
  return argv.includes("--yes");
}

async function main() {
  const yes = parseArgs(process.argv.slice(2));

  if (!API_KEY || !API_SECRET) {
    console.error(
      "ERROR: CLOUDINARY_API_KEY and CLOUDINARY_API_SECRET must be set.\n\n" +
      "Option 1 — Pass them as environment variables:\n" +
      "  CLOUDINARY_API_KEY=xxx CLOUDINARY_API_SECRET=yyy \\\n" +
      "    node scripts/fixUploadPreset.js --yes\n\n" +
      "Option 2 — Set them in Firebase Functions config:\n" +
      "  firebase functions:secrets:set CLOUDINARY_API_KEY\n" +
      "  firebase functions:secrets:set CLOUDINARY_API_SECRET\n" +
      "  Then read from process.env in this script."
    );
    process.exit(1);
  }

  cloudinary.v2.config({
    cloud_name: CLOUD_NAME,
    api_key: API_KEY,
    api_secret: API_SECRET,
  });

  console.log(`Fixing upload preset "${UPLOAD_PRESET}" on cloud "${CLOUD_NAME}"\n`);

  // Step 1: Read current preset
  console.log("Current preset configuration:");
  try {
    const preset = await cloudinary.v2.api.upload_preset(UPLOAD_PRESET);
    console.log(JSON.stringify(preset, null, 2));
    console.log("");

    if (preset.categorization) {
      console.log(`  categorization = ${preset.categorization}  ← THIS CAUSES HTTP 420`);
    }
    if (preset.auto_tagging) {
      console.log(`  auto_tagging = ${preset.auto_tagging}  ← THIS CAUSES HTTP 420`);
    }
    if (preset.detection) {
      console.log(`  detection = ${preset.detection}  ← potential Rekognition trigger`);
    }
    console.log("");
  } catch (error) {
    console.error(`Failed to read preset "${UPLOAD_PRESET}":`, error.message);
    console.error("Make sure the preset exists in the Cloudinary console.");
    process.exit(1);
  }

  if (!yes) {
    console.log("DRY RUN — no changes made. Re-run with --yes to apply the fix.\n");
    process.exit(0);
  }

  // Step 2: Update preset to remove all Rekognition / auto-tagging settings
  console.log("Updating preset to disable Rekognition Auto Tagging ...");

  const updates = {
    unique_filename: false,
    overwrite: false,
    resource_type: "auto",
    // Explicitly clear any Rekognition / categorization settings:
    categorization: "",
    auto_tagging: "",
    detection: "",
    faces: "",
    facial_attributes: "",
    ocr: "",
    viagra: "",
    moderations: "",
  };

  try {
    const result = await cloudinary.v2.api.update_upload_preset(UPLOAD_PRESET, updates);
    console.log("Preset updated successfully.\n");
    console.log("Updated preset configuration:");
    console.log(JSON.stringify(result, null, 2));

    // Verify
    const verify = await cloudinary.v2.api.upload_preset(UPLOAD_PRESET);
    console.log("\nVerification — key fields:");
    console.log(`  categorization = "${verify.categorization || "(empty)"}"`);
    console.log(`  auto_tagging = "${verify.auto_tagging || "(empty)"}"`);
    console.log(`  detection = "${verify.detection || "(empty)"}"`);
    console.log(`  unsigned = ${verify.unsigned}`);

    if (verify.categorization || verify.auto_tagging || verify.detection) {
      console.error("\nWARNING: Some Rekognition settings are still active!");
      console.error("You may need to disable them manually in the Cloudinary Console:");
      console.error(`  https://console.cloudinary.com/${CLOUD_NAME}/upload/presets`);
      process.exit(1);
    }

    console.log("\nDone. The upload preset no longer triggers Rekognition.");
    console.log("Test an upload from the Android app — you should get HTTP 200.");
  } catch (error) {
    console.error("Failed to update preset:", error.message);
    console.error("\nYou may need to disable Rekognition manually in the Cloudinary Console:");
    console.error(`  https://console.cloudinary.com/${CLOUD_NAME}/upload/presets`);
    process.exit(1);
  }
}

main().catch((error) => {
  console.error("Script failed:", error);
  process.exit(1);
});
