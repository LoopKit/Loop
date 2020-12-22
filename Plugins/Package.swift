// swift-tools-version:5.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Plugins",
    platforms: [.iOS(.v13)],
    products: [
        // Products define the executables and libraries a package produces, and make them visible to other packages.
        .library(
            name: "Plugins",
            targets: ["Plugins"]),
    ],
    dependencies: [
        .package(url: "https://github.com/LoopKit/LoopKit.git", .branch("package-experiment")),
        .package(name: "RileyLinkIOS", url: "https://github.com/ps2/rileylink_ios.git", .branch("package-experiment")),
        .package(url: "https://github.com/ps2/NightscoutService.git", .branch("package-experiment")),
        .package(name: "ShareClient", url: "https://github.com/LoopKit/dexcom-share-client-swift.git", .branch("package-experiment")),
        .package(url: "https://github.com/LoopKit/G4ShareSpy.git", .branch("package-experiment"))
    ],
    targets: [
        // Targets are the basic building blocks of a package. A target can define a module or a test suite.
        // Targets can depend on other targets in this package, and on products in packages this package depends on.
        .target(
            name: "Plugins",
            dependencies: [
                .product(name: "MockKit", package: "LoopKit"),
                .product(name: "MockKitUI", package: "LoopKit"),
                .product(name: "LoopKitUI", package: "LoopKit"),
                .product(name: "OmniKitPlugin", package: "RileyLinkIOS"),
                .product(name: "MinimedKitPlugin", package: "RileyLinkIOS"),
                .product(name: "NightscoutServiceKitPlugin", package: "NightscoutService"),
                .product(name: "ShareClientPlugin", package: "ShareClient"),
                .product(name: "G4ShareSpyPlugin", package: "G4ShareSpy"),
            ]),
        .testTarget(
            name: "PluginsTests",
            dependencies: ["Plugins"]),
    ]
)
