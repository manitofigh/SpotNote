// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "SpotNote",
  platforms: [.macOS(.v14)],
  products: [
    .executable(name: "SpotNoteApp", targets: ["SpotNoteApp"])
  ],
  dependencies: [
    .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0")
  ],
  targets: [
    .executableTarget(
      name: "SpotNoteApp",
      dependencies: [
        "Core",
        "Spotlight",
        .product(name: "Sparkle", package: "Sparkle")
      ],
      path: "Sources/SpotNoteApp",
      exclude: ["Assets.xcassets"],
      swiftSettings: [.swiftLanguageMode(.v6)]
    ),
    .target(
      name: "Core",
      path: "Sources/Core",
      swiftSettings: [.swiftLanguageMode(.v6)]
    ),
    .target(
      name: "Spotlight",
      dependencies: ["Core"],
      path: "Sources/Spotlight",
      resources: [.copy("Resources")],
      swiftSettings: [.swiftLanguageMode(.v6)]
    ),
    .testTarget(
      name: "CoreTests",
      dependencies: ["Core"],
      path: "Tests/CoreTests",
      swiftSettings: [.swiftLanguageMode(.v6)]
    ),
    .testTarget(
      name: "SpotlightTests",
      dependencies: ["Spotlight"],
      path: "Tests/SpotlightTests",
      swiftSettings: [.swiftLanguageMode(.v6)]
    ),
  ]
)
