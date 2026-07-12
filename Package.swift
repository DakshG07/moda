// swift-tools-version: 6.2

import PackageDescription

let package = Package(
  name: "Moda",
  platforms: [
    .macOS(.v26)
  ],
  products: [
    .executable(name: "Moda", targets: ["Moda"])
  ],
  targets: [
    .target(
      name: "ModaHardwareBridge",
      path: "Sources/ModaHardwareBridge",
      publicHeadersPath: "include",
      cSettings: [.unsafeFlags(["-fobjc-arc"])],
      linkerSettings: [.linkedFramework("Foundation")]
    ),
    .executableTarget(
      name: "Moda",
      dependencies: ["ModaHardwareBridge"],
      linkerSettings: [
        .linkedFramework("AppKit"),
        .linkedFramework("ApplicationServices"),
        .linkedFramework("AudioToolbox"),
        .linkedFramework("CoreAudio"),
        .linkedFramework("ServiceManagement"),
      ]
    ),
    .testTarget(
      name: "ModaTests",
      dependencies: ["Moda"]
    ),
  ]
)
