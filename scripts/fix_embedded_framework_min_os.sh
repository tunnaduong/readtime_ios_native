#!/bin/bash
# Google Mobile Ads and UMP are static SDKs. Xcode embeds an empty stub of each only to carry the
# SDK's privacy manifest, and gives the stub the SDK's MinimumOSVersion of 100.0 — both in its
# Info.plist and in the binary. App Store Connect rejects that (ITMS-90208), so set both to the
# app's deployment target and re-sign the stub.
set -euo pipefail

FRAMEWORKS="${TARGET_BUILD_DIR}/${FRAMEWORKS_FOLDER_PATH}"
[ -d "$FRAMEWORKS" ] || exit 0

for framework in "$FRAMEWORKS"/*.framework; do
  [ -d "$framework" ] || continue
  name=$(basename "$framework" .framework)
  plist="$framework/Info.plist"
  binary="$framework/$name"
  changed=0

  if [ "$(/usr/libexec/PlistBuddy -c "Print :MinimumOSVersion" "$plist" 2>/dev/null || true)" = "100.0" ]; then
    /usr/libexec/PlistBuddy -c "Set :MinimumOSVersion ${IPHONEOS_DEPLOYMENT_TARGET}" "$plist"
    changed=1
  fi

  if [ -f "$binary" ] && xcrun vtool -show-build "$binary" 2>/dev/null | grep -q "minos 100.0"; then
    xcrun vtool -set-build-version ios "${IPHONEOS_DEPLOYMENT_TARGET}" "${SDK_VERSION}" -replace -output "$binary" "$binary"
    changed=1
  fi

  if [ "$changed" = 1 ]; then
    echo "Set minimum iOS ${IPHONEOS_DEPLOYMENT_TARGET} for ${name}.framework"
    if [ "${CODE_SIGNING_ALLOWED:-NO}" = "YES" ] && [ -n "${EXPANDED_CODE_SIGN_IDENTITY:-}" ]; then
      codesign --force --sign "${EXPANDED_CODE_SIGN_IDENTITY}" --preserve-metadata=identifier,entitlements,flags --timestamp=none "$framework"
    fi
  fi
done
