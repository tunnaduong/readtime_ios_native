// swift-tools-version: 5.9
// Skip (https://skip.dev) package that transpiles the ReadTime SwiftUI sources to an
// Android (Kotlin/Compose) app in Android/. The iOS app still builds from ReadTimeNative.xcodeproj.
import PackageDescription

let package = Package(
    name: "readtime",
    defaultLocalization: "en",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "ReadTime", type: .dynamic, targets: ["ReadTime"]),
    ],
    dependencies: [
        .package(url: "https://github.com/skiptools/skip.git", from: "1.9.10"),
        .package(url: "https://github.com/skiptools/skip-ui.git", from: "1.0.0"),
    ],
    targets: [
        .target(
            name: "ReadTime",
            dependencies: [.product(name: "SkipUI", package: "skip-ui")],
            path: "ReadTime",
            exclude: ["Info.plist", "InfoPlist.xcstrings", "PrivacyInfo.xcprivacy", "ReadTime.entitlements", "Config", "Settings.bundle", "Assets.xcassets"],
            resources: [.process("Resources"), .process("Localizable.xcstrings")],
            plugins: [.plugin(name: "skipstone", package: "skip")]
        ),
    ]
)
