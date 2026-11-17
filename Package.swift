// swift-tools-version: 5.8

import PackageDescription

let package = Package(
  name: "MultiCodexPets",
  defaultLocalization: "en",
  platforms: [
    .macOS(.v13)
  ],
  products: [
    .executable(name: "MultiCodexPets", targets: ["MultiCodexPets"]),
    .library(name: "MultiCodexPetsCore", targets: ["MultiCodexPetsCore"]),
  ],
  targets: [
    .target(name: "MultiCodexPetsCore"),
    .executableTarget(
      name: "MultiCodexPets",
      dependencies: ["MultiCodexPetsCore"],
      resources: [.process("Resources")]
    ),
    .testTarget(
      name: "MultiCodexPetsCoreTests",
      dependencies: ["MultiCodexPetsCore"]
    ),
  ]
)
