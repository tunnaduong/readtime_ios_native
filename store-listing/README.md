# Store listing assets

- `feature-graphic.png` — Google Play feature graphic, 1024 × 500.
- `screenshots/` — six phone screenshots, 1080 × 1920, each with a caption above the phone.
- `raw/` — the plain simulator captures (iPhone 17, 1206 × 2622) the screenshots are built from.

## Regenerate

Capture the raw screens from a Debug build on a booted simulator (demo library, no ads):

```sh
xcrun simctl launch booted com.fatties.readtime -demoContent YES -disableAds YES -screen home
xcrun simctl io booted screenshot store-listing/raw/home.png
```

Repeat for `goals`, `library`, `stats`, `session` and `journal`, then compose:

```sh
swift store-listing/compose.swift store-listing/raw store-listing ReadTime/Assets.xcassets/AppIcon.appiconset/AppIcon.png
```

Captions live at the top of `compose.swift`.
