# ReadTime Native

Native iOS app written in SwiftUI. It mirrors the supplied Figma visual system while using iOS-native navigation, controls, Dynamic Type, notifications, and Swift Charts.

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

## Premium

The paywall shows a free trial button when `PurchaseManager.premiumProductID` is an auto-renewable subscription with a free-trial introductory offer in App Store Connect. A one-time (non-consumable) product works too, without the trial.

## Widgets

`ReadTimeWidgets` is an app extension with two Home Screen widgets:

- **Current Book** (small, medium) — cover, title, progress bar and page count.
- **Daily Goal** (small, medium, plus Lock Screen circular and rectangular) — today's minutes against the goal, the streak, and this week at a glance.

Both targets share data through the app group `group.com.fatties.readtime`: `ReadTime/SharedModels.swift` is compiled into each, and the reading data and cached covers live in the group container. Data saved by earlier versions is copied over on first launch. `ReadingStore.save()` calls `WidgetCenter.reloadAllTimelines()`, so widgets follow the app straight away.

Note: `scripts/generate_xcode_project.rb` predates the Swift package, the widget target and the current bundle ID — regenerating the project from it would drop them. Edit `ReadTimeNative.xcodeproj` directly, or update the script first.
