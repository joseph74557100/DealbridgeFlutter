# DealBridge Flutter Migration Starter

This archive was generated from the uploaded Kotlin DealBridge project. It is a **Flutter migration starter**, not a claim that every Kotlin feature has already been ported or tested. It includes an Android Flutter app foundation, Firebase sign-in, a Firestore-backed Deals view, core project structure, and a `backend_reference/` copy of the existing Firebase rules/configuration and Cloud Functions source for review.

## Preserve your existing backend
- Firebase project: `dealbridge-5183`
- Android application ID: `com.example.dealbridge`
- Firestore collections and existing rules are retained as reference files under `backend_reference/`.
- No deployment or billing setup is performed by this project.
- The Flutter app reads deals for the signed-in user using `participantIds` and does not write completion states.

## Important workflow note
The uploaded Kotlin code still contains the older agreement confirmation / auto-completion lifecycle. Your latest product decision is recipient accepts or declines, with trusted backend processing completion and agreement generation. This starter intentionally does not pretend the existing Cloud Functions already implement that new workflow. Review and approve backend changes separately before enabling deal actions in Flutter.

## Build on Android
1. Install Flutter SDK and ensure `flutter --version` works.
2. Extract this archive.
3. From the `DealBridge_Flutter_Migration` folder run:
   ```sh
   flutter pub get
   flutter run
   ```
4. If Android Gradle complains about SDK versions, use the Flutter SDK's recommended Android setup. This generated Gradle setup uses the Flutter plugin DSL.

The Android `google-services.json` is copied from the uploaded project to `android/app/google-services.json`. Keep it private enough for your project and do not publish service-account credentials. Firebase client config is not a substitute for Firestore security rules.

## What is in this starter
- Email/password sign-in and account creation using Firebase Auth
- Authenticated shell with Home, Deals, Businesses, Messages and Profile navigation
- Firestore deals list scoped to `participantIds` containing the authenticated UID
- Tolerant deal field parsing and status display
- Project organization for adding feature repositories/screens incrementally
- Existing rules, indexes, Firebase config and Cloud Functions copied as backend references
- Selected Kotlin model/repository source snapshots and inventory for parity review

## Not yet ported
The full Kotlin project has many features (business editing and discovery, chats and media, posts/stories, push notifications, verification/admin, disputes, agreement PDF viewing/downloads, settings and Cloudinary uploads). These must be migrated and tested feature-by-feature. This starter does not claim feature parity yet.
