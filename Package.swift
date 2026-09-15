// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "YubicoNotch",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "YubicoNotch", targets: ["YubicoNotch"]),
        .library(name: "YubicoNotchKit", targets: ["YubicoNotchKit"]),
    ],
    dependencies: [
        .package(url: "https://github.com/Yubico/yubikit-swift", from: "1.3.0")
    ],
    targets: [
        .target(
            name: "YubicoNotchKit",
            dependencies: [.product(name: "YubiKit", package: "yubikit-swift")]
        ),
        .executableTarget(
            name: "YubicoNotch",
            dependencies: ["YubicoNotchKit"]
        ),
        .testTarget(
            name: "YubicoNotchKitTests",
            dependencies: [
                "YubicoNotchKit",
                .product(name: "YubiKit", package: "yubikit-swift"),
            ]
        ),
    ]
)
