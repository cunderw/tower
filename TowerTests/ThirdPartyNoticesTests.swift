import Foundation
import Testing

/// The app bundle carries `THIRD-PARTY-NOTICES.md`, so the MIT and GPL notices travel with
/// the binary.
///
/// The file is at the repository root, outside every folder-synced group. One file reference
/// and one build file in `project.pbxproj` put it in the app's resources, and a project edit
/// that drops either one leaves the build green. The `TowerKit` tests cannot see a built
/// product. `TowerTests` is app-hosted, so `Bundle.main` here is the Tower app.
///
/// The app does not show the file. This checks only that it ships.
@Suite("Third-party notices")
struct ThirdPartyNoticesTests {
  @Test("the app bundle holds the notices file, with each license's text")
  func noticesShip() throws {
    let url = try #require(
      Bundle.main.url(forResource: "THIRD-PARTY-NOTICES", withExtension: "md"),
      "Tower.app has no THIRD-PARTY-NOTICES.md"
    )
    let text = try String(contentsOf: url, encoding: .utf8)
    // One marker per license. An empty or truncated copy fails here.
    for marker in [
      "Apollo Graph, Inc.", "Permission is hereby granted",
      "any later version", "GNU GENERAL PUBLIC LICENSE",
    ] {
      #expect(text.contains(marker), "the bundled notices do not contain \"\(marker)\"")
    }
  }
}
