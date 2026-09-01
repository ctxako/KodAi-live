// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ToolGuardrails",
    products: [
        .library(name: "ToolGuardrails", targets: ["ToolGuardrails"])
    ],
    targets: [
        .target(
            name: "ToolGuardrails",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "ToolGuardrailsTests",
            dependencies: ["ToolGuardrails"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
