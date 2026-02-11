// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "NuxieGodotBridge",
  platforms: [
    .iOS(.v15),
  ],
  products: [
    .library(
      name: "NuxieGodotBridge",
      type: .dynamic,
      targets: ["NuxieGodotBridge"]
    )
  ],
  dependencies: [
    .package(url: "https://github.com/nuxieio/nuxie-ios.git", branch: "main")
  ],
  targets: [
    .target(
      name: "NuxieGodotBridge",
      dependencies: [
        .product(name: "Nuxie", package: "nuxie-ios"),
      ]
    ),
    .testTarget(
      name: "NuxieGodotBridgeTests",
      dependencies: ["NuxieGodotBridge"],
      resources: [
        .process("Fixtures"),
      ]
    )
  ]
)
