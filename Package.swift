// swift-tools-version:6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "mame",
    platforms: [.macOS(.v14), .iOS(.v17), .tvOS(.v17)],
    products: [
        .executable(name: "mame", targets: ["mame"]),
    ],
    dependencies: [
        .package(url: "https://github.com/hummingbird-project/hummingbird.git", from: "2.0.0"),
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.3.0"),
        .package(url: "https://github.com/jpsim/Yams.git", from: "5.0.0"),
        .package(url: "https://github.com/apple/swift-testing.git", from: "0.9.0"),
    ],
    targets: [
        .executableTarget(name: "mame",
                          dependencies: [
                              .product(name: "ArgumentParser", package: "swift-argument-parser"),
                              .product(name: "Hummingbird", package: "hummingbird"),
                              .product(name: "Yams", package: "Yams"),
                          ],
                          path: "Sources/App"),
        .testTarget(name: "mameTests",
                    dependencies: [
                        .byName(name: "mame"),
                        .product(name: "HummingbirdTesting", package: "hummingbird"),
                        .product(name: "Testing", package: "swift-testing"),
                    ],
                    path: "Tests/AppTests"),
    ],
)
