// swift-tools-version: 6.0
import PackageDescription
import Foundation

let pinsURL = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("NATIVE-PINS.json")
let pins = try JSONSerialization.jsonObject(with: Data(contentsOf: pinsURL)) as! [String: Any]
let ios = pins["ios"] as! [String: String]

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
    .package(
      url: ios["repository"]!,
      revision: ios["revision"]!
    )
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
      dependencies: ["NuxieGodotBridge"]
    )
  ],
  swiftLanguageModes: [.v5]
)
