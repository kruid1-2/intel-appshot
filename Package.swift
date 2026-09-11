// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "IntelAppshotShimProbe",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "AppshotShimCore", targets: ["AppshotShimCore"]),
        .executable(
            name: "SkyComputerUseService",
            targets: ["SkyComputerUseService"]
        ),
        .executable(
            name: "AppshotProbeClient",
            targets: ["AppshotProbeClient"]
        )
    ],
    targets: [
        .target(name: "AppshotShimCore"),
        .executableTarget(
            name: "SkyComputerUseService",
            dependencies: ["AppshotShimCore"]
        ),
        .executableTarget(name: "AppshotProbeClient"),
        .testTarget(
            name: "AppshotShimCoreTests",
            dependencies: ["AppshotShimCore"]
        )
    ]
)
