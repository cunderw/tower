// swift-tools-version:6.1

import PackageDescription

let package = Package(
  name: "TowerAPI",
  platforms: [
    .iOS(.v15),
    .macOS(.v12),
    .tvOS(.v15),
    .watchOS(.v8),
    .visionOS(.v1),
  ],
  products: [
    .library(name: "TowerAPI", targets: ["TowerAPI"]),
    .library(name: "TowerAPITestMocks", targets: ["TowerAPITestMocks"]),
  ],
  dependencies: [
    .package(url: "https://github.com/apollographql/apollo-ios", exact: "2.3.0"),
  ],
  targets: [
    .target(
      name: "TowerAPI",
      dependencies: [
        .product(name: "ApolloAPI", package: "apollo-ios"),
      ],
      path: "./Sources"
    ),
    .target(
      name: "TowerAPITestMocks",
      dependencies: [
        .product(name: "ApolloTestSupport", package: "apollo-ios"),
        .target(name: "TowerAPI"),
      ],
      path: "./TowerAPITestMocks"
    ),
  ],
  swiftLanguageModes: [.v6, .v5]
)
