import XCTest

@MainActor
final class ShellUITests: XCTestCase {
  func testEveryTabExistsAndDockerRoundTrips() {
    let app = XCUIApplication()
    // `--uitest-seed-dashboard` seeds a fake `Server` and swaps in
    // `FakeSystemRepository` (see `TowerApp`'s `#if DEBUG` block) so this
    // reaches `RootView` with no keychain access and no Unraid server —
    // neither of which XCUITest can provide.
    app.launchArguments = ["--uitest-seed-dashboard"]
    app.launch()

    let tabs = app.descendants(matching: .any).matching(identifier: "root.tabs").firstMatch
    XCTAssertTrue(tabs.waitForExistence(timeout: 5), "root.tabs never appeared")

    for tab in TowerTabFixture.allTitles {
      XCTAssertTrue(app.buttons[tab].firstMatch.waitForExistence(timeout: 5), "\(tab) tab is missing")
    }

    let dashboardContent = app.descendants(matching: .any)
      .matching(identifier: "tab.dashboard.content").firstMatch
    XCTAssertTrue(dashboardContent.waitForExistence(timeout: 5), "Dashboard tab never showed its content")

    app.buttons["Docker"].firstMatch.tap()

    // `RootView` puts `tab.docker.content` on the Docker tab's `DockerListView`.
    let dockerContent = app.descendants(matching: .any)
      .matching(identifier: "tab.docker.content").firstMatch
    XCTAssertTrue(dockerContent.waitForExistence(timeout: 5), "Docker tab content never showed")

    app.buttons["Dashboard"].firstMatch.tap()

    XCTAssertTrue(dashboardContent.waitForExistence(timeout: 5), "Dashboard content never returned")
    XCTAssertFalse(dockerContent.exists, "Docker tab content still showing after returning to Dashboard")
  }
}

/// Mirrors `TowerTab.title`'s five cases. The UI test target can't import
/// the app's `TowerTab` enum (no `@testable import` for XCUITest bundles —
/// they run out-of-process from the app under test), so the tab titles are
/// duplicated here rather than referencing it directly.
private enum TowerTabFixture {
  static let allTitles = ["Dashboard", "Docker", "VMs", "Shares", "Services"]
}
