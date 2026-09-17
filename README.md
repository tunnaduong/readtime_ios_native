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
