# Android port — status

ReadTime is a native SwiftUI iOS app. The Android version in `android/` is a
separate **native Kotlin + Jetpack Compose** app that follows the same design,
data format, and wording, built from the Swift source as the specification.

An earlier attempt used the [Skip](https://skip.dev) transpiler to build Android
from the Swift sources. It produced a working APK but was dropped for being slow
to iterate on; all Skip files (`Package.swift`, the generated `Android/` Gradle
project, `Skip.env`, and the Swift-side shims) have been removed. The `#if !SKIP`
seams left in the Swift sources by commit `c2b4344` are untouched and harmless —
they only wrap iOS-only frameworks.

## Building

```bash
cd android && ANDROID_HOME=~/Library/Android/sdk gradle assembleDebug
adb install -r app/build/outputs/apk/debug/app-debug.apk
```

Min SDK 26, target/compile SDK 35, Kotlin 2.0, Compose BOM 2024.12, Material 3.

Publishing to Google Play: see [android/RELEASE.md](android/RELEASE.md).

## Layout

| Path | What's in it |
|---|---|
| `android/app/src/main/java/com/fatties/readtime/data/` | Models, JSON storage, the `ReadingStore`, reminders, cover cache, book search, CSV/JSON transfer |
| `.../ui/theme/` | The `readTime…` palette and Material 3 theme (light/dark/system) |
| `.../ui/components/` | Cards, covers, progress bars, section headers |
| `.../ui/screens/` | One file per screen: Home, Goals, CreateGoal, Library, AddBook, ReadingSession, Stats, Journal, Settings, ImportExport, Onboarding |
| `android/tools/import_strings.py` | Regenerates `res/values*/strings_catalog.xml` from `ReadTime/Localizable.xcstrings` |

### Data compatibility

`data/Models.kt` serialises with the same field names and value shapes as the
iOS `Codable` types — dates as seconds since Apple's 2001 reference date, ids as
uppercase UUID strings — so a JSON backup exported on iOS restores on Android and
vice versa. Data lives in `filesDir/ReadTime.json`; device preferences
(appearance, the session in progress) live in `SharedPreferences`.

### Localisation

All 366 strings and their Vietnamese, Spanish, Japanese and Simplified Chinese
translations are imported from the iOS string catalog by
`android/tools/import_strings.py`; resource names are derived from the English
text (`s_daily_goal`, `s_page_n_of_n`, …). Re-run it after editing the catalog.

## Differences from iOS

- **Reminders**: Android has no repeating "every Tuesday at 20:00" notification,
  so each reminder schedules the next one with WorkManager when it fires, and the
  app tops the schedule up on launch. Android 13+ asks for notification
  permission when the reminder is first turned on.
- **No iCloud**: the iCloud backup/restore section is gone. Export and import a
  backup file instead (Settings → Import & Export), which also moves data between
  iOS and Android.
- **Ads**: AdMob banners on the four tabs and an interstitial after a reading
  session, same as iOS. Unit ids default to Google's test ids; put the real ones in
  `android/local.properties` as `admobAppId`, `admobBannerUnitId` and
  `admobInterstitialUnitId`. There is no consent (UMP) or tracking prompt yet —
  add UMP before shipping to the EEA/UK.
- **Premium**: Google Play Billing, product id `com.fatties.readtime.premium`
  (queried as a subscription first, then a one-time purchase). It needs the product
  set up in Play Console and a build installed from a Play track; until then the
  paywall says Premium isn't available. Premium turns ads off.
- **Language**: picked inside the app (Settings → Language) with
  `AppCompatDelegate.setApplicationLocales`, which Android 13+ stores as a per-app
  language and older versions keep in app storage.
- **Widgets**: two home-screen widgets built with Glance — "Current Book" (cover,
  title, progress) and "Daily Goal" (minutes today, streak, the week's dots), the
  same two the iOS app ships. They read the same `ReadTime.json` the app writes and
  redraw whenever it changes; Android has no lock-screen widget equivalent to iOS's
  accessory families.
- **Launcher icon**: an adaptive icon generated from the iOS artwork
  (`android/tools/` has no script for it; the foreground PNGs live in `res/mipmap-*`,
  the purple background in `res/values/ic_launcher_background.xml`).
- **Not ported (yet)**: the CloudKit-backed roadmap screen and the app-icon picker
  (Android has no runtime launcher-icon API).
- Swipe actions on library rows are a long-press menu; iOS sheets are Compose
  bottom sheets or dialogs.

## Verification status

Checked on a Pixel 9 Pro API 30 emulator:

- Onboarding, demo content, and the Home tab render; the launcher icon is the
  adaptive one (round mask, purple background).
- AdMob's test banner loads at the top of Home.
- Both widgets work on the home screen, show the empty state with no books, and
  refresh themselves when the app saves.
- Language and appearance are changed from Settings and survive a restart.

Not yet exercised: Premium (needs the product in Play Console and a build
installed from a Play track), reminders firing on schedule, and CSV/backup
import-export.

### What to check first on a device

1. First launch shows onboarding; "Explore with Demo Content" fills the library.
2. Start a session from Home → Read Now, end it, save a page and a journal entry,
   and confirm the Goals Updated summary and the new activity on Home.
3. Add a book by searching (needs network), and by picking a cover photo.
4. Goals → New Goal → both flows, then check the week tracker and reminders.
5. Settings → Import & Export: export a backup, import a Goodreads CSV.
6. Switch the appearance between System/Light/Dark, and the system language to
   Vietnamese, to check the imported translations.
