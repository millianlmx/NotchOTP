// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "NotchOTP",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "NotchOTP", targets: ["NotchOTP"]),
        .library(name: "NotchOTPKit", targets: ["NotchOTPKit"]),
    ],
    dependencies: [
        .package(url: "https://github.com/Yubico/yubikit-swift", from: "1.3.0")
    ],
    targets: [
        .target(
            name: "NotchOTPKit",
            dependencies: [.product(name: "YubiKit", package: "yubikit-swift")]
        ),
        .executableTarget(
            name: "NotchOTP",
            dependencies: ["NotchOTPKit"]
        ),
        .testTarget(
            name: "NotchOTPKitTests",
            dependencies: [
                "NotchOTPKit",
                .product(name: "YubiKit", package: "yubikit-swift"),
            ]
        ),
    ]
)
