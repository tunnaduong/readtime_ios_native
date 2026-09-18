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
    // macOS is required here even though this app never ships for macOS:
    // Skip Fuse's own dependencies (SkipFuseUI, the skipstone plugin)
    // declare a macOS minimum, and `swift build` compiles this target
    // natively for the host (macOS, on Skip's own CI/local dev flow) as
    // part of its normal build — the actual Android build is a separate
    // step (`skip gradle -p Android/ assemble`, per Skip's docs). That
    // means genuinely iOS-only SwiftUI APIs used in this file (some
    // toolbar placements, `navigationBarTitleDisplayMode`, etc.) need
    // `#if !os(macOS)` guards, not just `#if os(iOS)` ones — see those
    // call sites below.
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "ReadTime", type: .dynamic, targets: ["ReadTime"]),
    ],
    dependencies: [
        .package(url: "https://source.skip.tools/skip.git", from: "1.0.0"),
        // SkipFuseUI (not SkipUI/skip-ui, which is for Skip's other, Lite
        // transpile mode): CI's Android cross-compile failed with "no such
        // module 'SwiftUI'" using skip-ui — SkipUI's own package built fine
        // standalone (libSkipUI.so), it just doesn't map `import SwiftUI`
        // onto itself for a Fuse app the way SkipFuseUI does.
        .package(url: "https://github.com/skiptools/skip-fuse-ui.git", from: "1.0.0"),
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
                .product(name: "SkipFuseUI", package: "skip-fuse-ui"),
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
