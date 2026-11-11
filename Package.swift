// swift-tools-version: 6.0
import PackageDescription

// Vellforge: one menu bar app, with each tool as a built-in add-on.
//
//   *Core          pure logic, no AppKit, unit tested
//   VellforgeKit   what the add-ons share: the AddOn protocol, permissions,
//                  the registry that starts and stops add-ons, legacy import
//   Snap/Scroll/Bar  one module per add-on
//   Vellforge      the app itself: menu bar icon, Settings, welcome, updates
let package = Package(
    name: "Vellforge",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0"),
    ],
    targets: [
        .target(name: "SnapCore"),
        .target(name: "ScrollCore"),
        .target(name: "BarCore"),

        .target(name: "VellforgeKit"),

        .target(name: "Snap", dependencies: ["SnapCore", "VellforgeKit"]),
        .target(name: "Scroll", dependencies: ["ScrollCore", "VellforgeKit"]),
        .target(name: "Bar", dependencies: ["BarCore", "VellforgeKit"]),

        .executableTarget(
            name: "Vellforge",
            dependencies: [
                "VellforgeKit", "Snap", "Scroll", "Bar",
                .product(name: "Sparkle", package: "Sparkle"),
            ]
        ),

        .testTarget(name: "SnapCoreTests", dependencies: ["SnapCore"]),
        .testTarget(name: "ScrollCoreTests", dependencies: ["ScrollCore"]),
        .testTarget(name: "BarCoreTests", dependencies: ["BarCore"]),
        .testTarget(name: "VellforgeKitTests", dependencies: ["VellforgeKit"]),
    ]
)
