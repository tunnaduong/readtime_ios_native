# Releasing ReadTime on Google Play

Everything here is done from this machine except the Play Console steps, which
need your Google account — sign in and click through those yourself.

## 1. Create the upload key (once)

```bash
cd android
keytool -genkeypair -v -keystore upload-keystore.jks -keyalg RSA -keysize 2048 \
        -validity 10000 -alias upload
```

`keytool` asks for the password itself — nothing needs to be typed into a file.

Then tell the build where the key is, either by exporting the values:

```bash
export READTIME_KEYSTORE=upload-keystore.jks
export READTIME_KEYSTORE_PASSWORD='…'
export READTIME_KEY_ALIAS=upload
export READTIME_KEY_PASSWORD='…'
```

or by copying `keystore.properties.example` to `android/keystore.properties` and
filling in the four values. Both the keystore and that file are git-ignored. Keep
a backup of the keystore: losing it means you cannot update the app under the same
upload key (Play App Signing lets Google reset it, but that is a support ticket).

**A release build with no key configured comes out unsigned**, and Gradle prints a
warning saying so. It never falls back to the debug key, because Play rejects
debug-signed uploads — that is what "Bạn đã tải lên APK hoặc Android App Bundle đã
được ký ở chế độ gỡ lỗi" means. For local testing, install the debug build.

## 2. Fill in the real service IDs

`android/local.properties` (git-ignored):

```
admobAppId=ca-app-pub-…~…
admobBannerUnitId=ca-app-pub-…/…
admobInterstitialUnitId=ca-app-pub-…/…
```

These must be the **Android** app's ids from AdMob — the ones in
`ReadTime/Config/ReadTime.xcconfig` belong to the iOS app. Without them the build
uses Google's test ids, which show "Test Ad" and earn nothing.

Still missing before an EEA/UK release: the UMP consent form that the iOS app
shows (`ReadTime/Ads/AdManager.swift`). Android needs its own
`com.google.android.ump` integration.

## 3. Set the version

In `android/app/build.gradle.kts`:

```kotlin
versionCode = 1      // must increase with every upload
versionName = "1.0"  // what people see
```

## 4. Build the bundle

```bash
cd android && gradle bundleRelease
```

The result is `app/build/outputs/bundle/release/app-release.aab`.

## 5. Play Console

1. **Create the app** — package name `com.fatties.readtime`, free, app category
   Books & Reference.
2. **Internal testing** → create a release → upload the `.aab` → add yourself as a
   tester and install from the opt-in link. Do this before production: Premium
   only works for a build that came from a Play track.
3. **Store listing** — title, short and full description, and graphics: a 512×512
   icon, a 1024×500 feature graphic, and at least two phone screenshots. The iOS
   App Store copy under `ReadTime/` and the screenshots in `website/` are a
   starting point.
4. **Privacy policy** — `website/privacy.html` in this repo needs to be published
   at a public URL and linked here.
5. **Data safety** — declare what the app actually does: book searches and cover
   downloads go to Google Books, Open Library and the cover hosts; AdMob collects
   the advertising ID and device data. Reading data itself stays on the device.
6. **Content rating** and **target audience** questionnaires.
7. **In-app product** — create `com.fatties.readtime.premium` (subscription or
   one-time, matching the iOS product) and activate it, otherwise the paywall
   reports that Premium isn't available.

## 6. Keep it updated

Raise `versionCode`, rebuild, upload. `python3 android/tools/import_strings.py`
re-imports translations whenever `ReadTime/Localizable.xcstrings` changes.
