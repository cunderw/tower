// swift-tools-version: 6.2
import PackageDescription

let package = Package(
  name: "TowerKit",
  platforms: [.iOS(.v26), .macOS(.v13)],
  products: [
    .library(name: "TowerCore", targets: ["TowerCore"]),
    .library(name: "TowerData", targets: ["TowerData"]),
  ],
  dependencies: [
    // `.upToNextMinor`, not `from:`.
    // `BigInt.swift` declares `extension Int64: @retroactive CustomScalarType`
    // because ApolloAPI 2.3.0 ships no native one. If a future Apollo adds it,
    // that becomes a duplicate conformance and the build breaks. An open `from:`
    // range would let that arrive on someone's next `swift package update`; this
    // makes taking Apollo 2.4+ a deliberate edit, with the removal instructions
    // sitting in `BigInt.swift`. Patch releases still flow in automatically.
    .package(url: "https://github.com/apollographql/apollo-ios.git", .upToNextMinor(from: "2.3.0")),
    .package(path: "../TowerAPI"),
  ],
  targets: [
    .target(name: "TowerCore"),
    .target(name: "TowerData", dependencies: [
      "TowerCore",
      .product(name: "Apollo", package: "apollo-ios"),
      .product(name: "TowerAPI", package: "TowerAPI"),
    ]),
    .testTarget(name: "TowerCoreTests", dependencies: ["TowerCore"]),
    // `resources`: the service status fixtures are response bodies in the
    // shape each of the eight services sends, with invented values, so a
    // probe's shape assumptions are checked against a committed body rather
    // than against a literal written from memory.
    .testTarget(name: "TowerDataTests", dependencies: [
      "TowerData",
      "TowerCore",
      .product(name: "Apollo", package: "apollo-ios"),
      .product(name: "ApolloAPI", package: "apollo-ios"),
      .product(name: "ApolloTestSupport", package: "apollo-ios"),
      .product(name: "TowerAPI", package: "TowerAPI"),
      .product(name: "TowerAPITestMocks", package: "TowerAPI"),
    ], resources: [.copy("Fixtures")]),
  ]
)
