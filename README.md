# ReadTime Native

Native iOS app written in SwiftUI. It mirrors the supplied Figma visual system while using iOS-native navigation, controls, Dynamic Type, notifications, and Swift Charts.

## Android port status (branch `dhphuc`)

This branch adds the groundwork to build ReadTime for Android with [Skip](https://skip.dev) — see "Android (Skip)" below for the full breakdown. Short version:

**Done:**
- Skip package scaffolding (`Package.swift`, `Skip.env`, `ReadTime/Skip/skip.yml`, `Tests/`) added on top of the existing Xcode project, without moving any files — iOS build is unaffected.
- Every iOS-only framework (CloudKit, StoreKit, GoogleMobileAds, PhotosUI, WidgetKit, Swift Charts, UMP, ATT) isolated behind `#if !SKIP … #else … #endif` in `ReadTime/ReadTimeApp.swift`.
- CloudKit kept as the backend on both platforms: Android talks to the same public database over CloudKit **Web Services** (`CloudKitWebService`), so `RoadmapStore` (voting/suggestions) and `ReferralReport` (onboarding source) are implemented for real, not stubbed.
- Stats charts have a working plain-bar Compose-friendly fallback (Swift Charts doesn't transpile).
- AdMob + UMP Gradle dependencies declared in `skip.yml`.
- CI (`.github/workflows/android-debug-apk.yml`) builds a debug APK and publishes it to the `prerelease-android` branch.

**Not done / stubbed (see the status table below for detail):**
- Premium purchases (`PurchaseManager`) — stub message, no Play Billing wired up yet. `skip-revenue`/RevenueCat was tried first but dropped: its package manifest requires Swift tools-version 6.1, which CI's toolchain couldn't resolve ("`'skip-revenue' contains incompatible tools version (6.1.0)`").
- AdMob ads (`AdManager`) — SDK calls not wired up, no ads render on Android yet.
- Cover photo picker — stub message, needs Android's Photo Picker.
- Personal iCloud backup — falls back to local-only storage on Android (needs a Sign-in-with-Apple flow for CloudKit's private database).
- Home/Lock Screen widgets — out of scope, no Android equivalent.
- **Nothing here has been built end-to-end yet.** Written without a Swift toolchain, Skip CLI, or Android SDK available locally — real CI runs are the only feedback loop so far, and each fix has come from reading the actual CI failure (the legacy Android SDK `tools` package, then the `skip-revenue` tools-version mismatch). `CloudKitWebService`'s request signing in particular has two untested implementations (CryptoKit for iOS, `java.security` for Android) that still need verifying once the build gets that far.

**CI:** `.github/workflows/android-debug-apk.yml` builds a debug APK on every push to `dhphuc`/`main` (and on manual dispatch) and publishes it two ways: as a normal workflow artifact, and committed to the `prerelease-android` branch at `prerelease/ReadTime-debug.apk` (with a short README noting the source commit) so there's always one stable link to the latest build.

## Included flows

- A four-tab Home, Goals, Library, and Stats experience
- Book status, current-page progress, and a timed reading session
- Reading goals, automatic progress calculations, and daily local reminders
- Reading journal entries saved after a session
- Weekly reading and genre statistics

## Run

Open `ReadTimeNative.xcodeproj` in Xcode, choose an iPhone simulator, and run the `ReadTimeNative` scheme.

## Configuration

Local secrets are kept out of source control in `ReadTime/Config/Secrets.xcconfig` (git-ignored). To set it up on a new machine:

```sh
cp ReadTime/Config/Secrets.example.xcconfig ReadTime/Config/Secrets.xcconfig
```

Then fill in the values:

- `GOOGLE_BOOKS_API_KEY` — optional key for book search. Create it in Google Cloud Console (APIs & Services → Credentials), enable the Books API, and restrict the key to the Books API and the bundle ID `com.fatties.readtime`. Without a key, search uses Google's keyless quota and falls back to Open Library.

- `ADMOB_APP_ID`, `ADMOB_INTERSTITIAL_UNIT_ID`, `ADMOB_BANNER_UNIT_ID`, `ADMOB_APP_OPEN_UNIT_ID` — optional overrides for Google AdMob. `ReadTime/Config/ReadTime.xcconfig` ships with Google's test IDs; set your real IDs there (or here) before release.

The app builds without `Secrets.xcconfig`; `ReadTime/Config/ReadTime.xcconfig` only includes it when present.

## Ads

Adaptive AdMob banners sit at the top of the Home, Goals, Library, and Stats tabs, and between Recent Activities and the reading journal on Home (they take no space until an ad loads). An app open ad covers the screen when the app returns from the background (at most once a minute; also on a cold start if it loads within 5 seconds). An AdMob interstitial plays after the user taps **Finish Session** (the session is saved first; the Goals Updated screen follows once the ad closes). Premium users never see ads. If no ad is loaded yet, the summary shows immediately. After onboarding, the app asks Google's User Messaging Platform for consent where required (EEA, UK), then shows Apple's App Tracking Transparency prompt; ads only load once consent allows it, and are non-personalized if tracking is declined.

## Backend (CloudKit)

The Roadmap and the onboarding "Where did you hear about ReadTime?" answer are stored in the CloudKit **public database** of `iCloud.com.fatties.readtime`. There is no server to run: CloudKit comes with the Apple Developer account, and the storage it needs here is far inside the free tier.

`CloudKit/schema.ckdb` holds the record types and indexes:

- `FeatureRequest` — `title`, `details`, `status` (`inReview`/`planned`/`inProgress`/`completed`), `listed`. Only `listed = 1` shows in the app.
- `Vote` — `featureName`. One record per reader and feature; the record ID makes double votes impossible.
- `ReferralAnswer` — `source`, `appVersion`. Written once per device, readable only by its creator and by you in the CloudKit Console.

Import it once per environment:

```bash
xcrun cktool save-token --type management
```

```bash
xcrun cktool import-schema --team-id 62H5L8QDTS --container-id iCloud.com.fatties.readtime --environment development --file CloudKit/schema.ckdb
```

Create the management token at [CloudKit Console](https://icloud.developer.apple.com) → Tokens. Before release, run the same import with `--environment production`.

Add roadmap items in the CloudKit Console as `FeatureRequest` records with `listed = 1`. Reader suggestions arrive with `listed = 0`; set it to 1 to publish them. Onboarding answers are in the `ReferralAnswer` records — query them in the console to see where readers come from.

## Android (Skip)

The app is being ported to Android with [Skip](https://skip.dev), which transpiles this same SwiftUI source (`ReadTime/ReadTimeApp.swift`, `ReadTime/SharedModels.swift`) to Kotlin/Jetpack Compose, so the iOS and Android apps share one codebase. `Package.swift` adds Skip on top of the existing `ReadTimeNative.xcodeproj` without moving any files — the iOS app keeps building exactly as before.

Several frameworks iOS uses have no Android build (CloudKit, StoreKit, GoogleMobileAds, PhotosUI, WidgetKit, Swift Charts, UserMessagingPlatform, AppTrackingTransparency). Each type that depends on one is wrapped in `#if !SKIP … #else … #endif` in `ReadTimeApp.swift`, with an Android-side implementation (or a clearly marked stub) in the `#else` branch.

### CloudKit on Android

There's no CloudKit SDK for Android, but Apple's **CloudKit Web Services** is a plain HTTPS API, so the Android build talks to the *same* `iCloud.com.fatties.readtime` public database as iOS instead of a separate backend. This is implemented in `CloudKitWebService` (top of `ReadTimeApp.swift`, under `#if SKIP`), and used by the Android branches of `RoadmapStore` and `ReferralReport`.

- It authenticates with a CloudKit Console **Server-to-Server Key** (Console → your container → Tokens → Server-to-Server Keys), not a signed-in Apple ID — Android has no iCloud account to sign in with. Put the Key ID and PEM private key in `CloudKitServerKeyID` / `CloudKitServerPrivateKey` Info.plist entries (same pattern as the AdMob unit IDs), sourced from a git-ignored secrets file — **never commit the private key**.
- One-vote-per-install is enforced with a random UUID generated on first launch (`CloudKitWebService.installID`) in place of the Apple ID CloudKit normally uses.
- Only the **public** database is reachable this way. Personal backup (`CloudBackup`, which uses iCloud key-value storage today) would need the **private** database, which requires a Web Auth Token from a "Sign in with Apple" flow — not implemented; `CloudBackup` currently falls back to local-only storage on Android.
- **Unverified**: this repo has no Swift/Skip toolchain available to build with, so the request signing has neither compiled nor run. `CloudKitWebService.sign(message:privateKeyPEM:)` has two branches: `P256.Signing` (CryptoKit) for iOS, unchanged; and, for Android, a direct `java.security.Signature`/`java.security.KeyFactory` call ("SHA256withECDSA") using Skip's documented "fully-qualified Kotlin/Java call" and "platform value wrapper" (`.kotlin()`) patterns. Confirm both the ECDSA call and the `Data`/`ByteArray` conversion compile once a real Skip build is available — the exact reverse-conversion initializer (`Data(platformValue:)`) is a best guess, not confirmed against Skip's source.

### Premium purchases on Android

`PurchaseManager`'s Android branch is currently a stub (`buyPremium()` just shows "Premium isn't available on Android yet."). [`skip-revenue`](https://skip.dev/docs/modules/skip-revenue/) (wraps RevenueCat, one Swift API for StoreKit + Play Billing) was tried first, but its package manifest requires Swift tools-version 6.1, and CI's dependency resolution failed with:

```
'skip-revenue' contains incompatible tools version (6.1.0)
```

Two ways forward once someone's actually iterating on this in a real environment:
1. Re-add `.package(url: "https://source.skip.dev/skip-revenue.git", ...)` to `Package.swift` once the toolchain in use supports Swift 6.1 (may just need a newer Xcode/CI image).
2. Or implement Play Billing directly against `PurchaseManager`'s Android branch using Skip's documented fully-qualified Kotlin/Java call pattern (`#if SKIP`) — more code, but no external dependency version constraint.

Either way it needs a matching product configured (RevenueCat dashboard + Play Store product, or a raw Play Console product) for `PurchaseManager.premiumProductID`.

### What's stubbed vs. implemented for Android

| Area | Status |
|---|---|
| CloudKit (Roadmap, referral answer) | Implemented over CloudKit Web Services — needs the server-to-server key added and a real build to verify |
| Reading data, goals, journal, stats | Unchanged — pure Swift/SwiftUI, transpiles as-is |
| Personal iCloud backup | Stubbed to local-only storage; needs Sign in with Apple + CloudKit private DB |
| Premium purchases (`PurchaseManager`) | Stubbed; `skip-revenue` dropped due to a Swift tools-version mismatch (see above) — needs Play Billing wired in directly, or `skip-revenue` re-added once that's resolved |
| Ads (`AdManager`, `AdBanner`) | Stubbed (no ads render); AdMob + UMP Android Gradle dependencies are declared in `ReadTime/Skip/skip.yml`, but the SDK calls themselves (callback-heavy) aren't wired up yet |
| Cover photo picker (`AddBookView`) | Stubbed; needs Android's Photo Picker via `ActivityResultContracts.PickVisualMedia` |
| Stats trend/genre charts | Working plain-bar fallback (Swift Charts doesn't transpile); swap for a Compose chart later if needed |
| Home/Lock Screen widgets | Out of scope — Android has no WidgetKit equivalent (would need Glance) |

### Building for Android

Not runnable in this environment (no Swift toolchain, Android SDK, or Skip CLI installed here) — CI (`.github/workflows/android-debug-apk.yml`) is the only place this has actually been exercised so far. To build locally once you have the prerequisites:

```sh
brew install skiptools/skip/skip   # Skip CLI (macOS + Xcode required)
skip android run                   # transpiles and launches on an emulator
```

Also needed, none of which exist in this repo yet:
- The Skip CLI's own prerequisites (Xcode, Android Studio/SDK, a configured Android emulator or device).
- `CloudKitServerKeyID` / `CloudKitServerPrivateKey` (see above).
- Real AdMob Android ad unit IDs (reuse the ones in `ReadTime/Config/ReadTime.xcconfig` once ads are wired up) and an `admobAppId` value.
- A resolution for premium purchases (see above).

## Premium

The paywall shows a free trial button when `PurchaseManager.premiumProductID` is an auto-renewable subscription with a free-trial introductory offer in App Store Connect. A one-time (non-consumable) product works too, without the trial.

## Widgets

`ReadTimeWidgets` is an app extension with two Home Screen widgets:

- **Current Book** (small, medium) — cover, title, progress bar and page count.
- **Daily Goal** (small, medium, plus Lock Screen circular and rectangular) — today's minutes against the goal, the streak, and this week at a glance.

Both targets share data through the app group `group.com.fatties.readtime`: `ReadTime/SharedModels.swift` is compiled into each, and the reading data and cached covers live in the group container. Data saved by earlier versions is copied over on first launch. `ReadingStore.save()` calls `WidgetCenter.reloadAllTimelines()`, so widgets follow the app straight away.

Note: `scripts/generate_xcode_project.rb` predates the Swift package, the widget target and the current bundle ID — regenerating the project from it would drop them. Edit `ReadTimeNative.xcodeproj` directly, or update the script first.
