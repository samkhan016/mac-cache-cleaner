// swift-tools-version: 6.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "SwiftUIMacCacheCleaner",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .executable(name: "MacCacheCleaner", targets: ["SwiftUIMacCacheCleaner"]),
    ],
    targets: [
        .executableTarget(
            name: "SwiftUIMacCacheCleaner"
        ),
        .testTarget(
            name: "SwiftUIMacCacheCleanerTests",
            dependencies: ["SwiftUIMacCacheCleaner"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
