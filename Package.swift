// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FineTune",
    platforms: [
        .macOS("15.4")
    ],
    products: [
        .executable(name: "FineTune", targets: ["FineTune"])
    ],
    dependencies: [
        .package(url: "https://github.com/wadetregaskis/FluidMenuBarExtra", exact: "1.5.1"),
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", exact: "2.4.0"),
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.8.1")
    ],
    targets: [
        .executableTarget(
            name: "FineTune",
            dependencies: [
                .product(name: "FluidMenuBarExtra", package: "FluidMenuBarExtra"),
                .product(name: "KeyboardShortcuts", package: "KeyboardShortcuts"),
                .product(name: "Sparkle", package: "Sparkle")
            ],
            path: "FineTune",
            exclude: [
                "Info.plist",
                "FineTune.entitlements",
                "Assets.xcassets"
            ],
            swiftSettings: [
                .define("ENABLE_TCC_SPI"),
                .enableUpcomingFeature("DisableOutwardActorInference"),
                .enableUpcomingFeature("GlobalActorIsolatedTypesUsability"),
                .enableUpcomingFeature("InferIsolatedConformances"),
                .enableUpcomingFeature("InferSendableFromCaptures"),
                .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
                .enableUpcomingFeature("MemberImportVisibility")
            ],
            linkerSettings: [
                .linkedFramework("IOBluetooth"),
                .linkedFramework("AudioToolbox"),
                .linkedFramework("CoreAudio"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("ServiceManagement"),
                .linkedFramework("UserNotifications"),
                .linkedFramework("JavaScriptCore"),
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])
            ]
        )
    ]
)
