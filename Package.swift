// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "VDDX",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "VDDX", targets: ["VDDX"])
    ],
    targets: [
        .target(
            name: "CVirtualDisplayBridge",
            path: "Sources/CVirtualDisplayBridge",
            cSettings: [.unsafeFlags(["-fobjc-arc"])]
        ),
        .executableTarget(
            name: "VDDX",
            dependencies: ["CVirtualDisplayBridge"],
            path: "Sources/VDDX",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
