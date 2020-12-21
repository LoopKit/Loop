// swift-tools-version:5.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "LoopUI",
    defaultLocalization: "en",
    platforms: [.iOS(.v13), .watchOS(.v4)],
    products: [
        // Products define the executables and libraries a package produces, and make them visible to other packages.
        .library(
            name: "LoopUI",
            targets: ["LoopUI"]),
    ],
    dependencies: [
        .package(url: "https://github.com/LoopKit/LoopKit.git", .branch("package-experiment")),
        .package(path: "../LoopCore")
    ],
    targets: [
        // Targets are the basic building blocks of a package. A target can define a module or a test suite.
        // Targets can depend on other targets in this package, and on products in packages this package depends on.
        .target(
            name: "LoopUI",
            dependencies: ["LoopCore", .product(name: "LoopKitUI", package: "LoopKit")]),
        .testTarget(
            name: "LoopUITests",
            dependencies: ["LoopUI"]),
    ]
)
