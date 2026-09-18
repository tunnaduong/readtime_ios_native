// swift-tools-version: 5.9
import PackageDescription

// Adds Skip's Android transpilation to the existing app without moving any
// existing iOS source files: the target's `path` points straight at the
// current `ReadTime/` folder (which `ReadTimeNative.xcodeproj` still owns and
// builds independently for iOS). See README.md "Android (Skip)" for setup —
// this file alone isn't enough to build for Android; it needs the Skip CLI
// and Android SDK, which aren't available in every environment.
let package = Package(
    name: "ReadTimeNative",
    defaultLocalization: "en",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "ReadTime", type: .dynamic, targets: ["ReadTime"]),
    ],
    dependencies: [
        .package(url: "https://source.skip.tools/skip.git", from: "1.0.0"),
        .package(url: "https://source.skip.tools/skip-ui.git", from: "1.0.0"),
        .package(url: "https://source.skip.tools/skip-fuse.git", from: "1.0.0"),
        // Cross-platform purchases: wraps StoreKit on iOS and Play Billing on
        // Android behind one API, so PurchaseManager's Android branch doesn't
        // need to hand-roll Play Billing's Kotlin API. Needs a RevenueCat
        // account/API keys — see README.md "Android (Skip)".
        .package(url: "https://source.skip.dev/skip-revenue.git", "0.0.0"..<"2.0.0"),
    ],
    targets: [
        .target(
            name: "ReadTime",
            dependencies: [
                .product(name: "SkipUI", package: "skip-ui"),
                .product(name: "SkipFuse", package: "skip-fuse"),
                .product(name: "SkipRevenue", package: "skip-revenue"),
            ],
            path: "ReadTime",
            exclude: [
                "Assets.xcassets",
                "Config",
                "Info.plist",
                "InfoPlist.xcstrings",
                "Localizable.xcstrings",
                "PrivacyInfo.xcprivacy",
                "ReadTime.entitlements",
                "Settings.bundle",
            ],
            resources: [
                .process("Resources"),
            ],
            plugins: [.plugin(name: "skipstone", package: "skip")]
        ),
        .testTarget(
            name: "ReadTimeTests",
            dependencies: [
                "ReadTime",
                .product(name: "SkipTest", package: "skip"),
            ],
            path: "Tests/ReadTimeTests",
            plugins: [.plugin(name: "skipstone", package: "skip")]
        ),
    ]
)
