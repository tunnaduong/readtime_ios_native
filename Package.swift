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
        // TODO(android): re-add "https://source.skip.dev/skip-revenue.git" for
        // cross-platform purchases once the toolchain here can resolve it —
        // its manifest requires Swift tools-version 6.1, which was
        // incompatible with the toolchain CI resolved against ("'skip-revenue'
        // contains incompatible tools version (6.1.0)"). Dropped for now so
        // dependency resolution (and the Android build) can proceed;
        // PurchaseManager's Android branch is back to a stub in the meantime.
    ],
    targets: [
        .target(
            name: "ReadTime",
            dependencies: [
                .product(name: "SkipUI", package: "skip-ui"),
                .product(name: "SkipFuse", package: "skip-fuse"),
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
