# Releasing ReadTime on Google Play

Everything here is done from this machine except the Play Console steps, which
need your Google account — sign in and click through those yourself.

## 1. Create the upload key (once)

```bash
cd android
keytool -genkeypair -v -keystore upload-keystore.jks -keyalg RSA -keysize 2048 \
        -validity 10000 -alias upload
```

Then copy `keystore.properties.example` to `android/keystore.properties` and fill
in the four values. Both files are git-ignored — keep a backup of the keystore
somewhere safe; losing it means you can never update the app under the same key
unless Play App Signing is enabled (it is, for new apps, so the upload key can be
reset by Google support).

Without `keystore.properties` a release build is signed with the debug key so it
can still be installed locally. Play rejects debug-signed uploads.

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
