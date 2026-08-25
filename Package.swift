// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "Opticus",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Opticus", targets: ["Opticus"])],
    targets: [
        .executableTarget(
            name: "Opticus",
            resources: [
                .process("Resources/eye.svg"),
                .process("Resources/app-eyeglasses.svg"),
                .process("Resources/monitor.svg"),
                .process("Resources/steelrework-logo.png"),
                .copy("Resources/DaysOne-Regular.ttf"),
                .copy("Resources/calibration_mannequin.usdc"),
                .copy("Resources/calibration-success.wav"),
                .copy("Resources/Opticus.icns"),
                .copy("Resources/EyeglassesClassifier.mlmodelc"),
            ]
        ),
        .testTarget(name: "OpticusTests", dependencies: ["Opticus"]),
    ]
)
