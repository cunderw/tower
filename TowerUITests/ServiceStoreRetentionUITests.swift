import UIKit
import XCTest

/// Re-entering a service renders its data immediately, because the store is
/// retained above navigation rather than rebuilt on every visit.
@MainActor
final class ServiceStoreRetentionUITests: XCTestCase {
  private let radarr = "A0000000-0000-0000-0000-000000000001"

  override func setUp() {
    super.setUp()
    continueAfterFailure = false
  }

  /// The library fetch takes three seconds under this fixture, which is what
  /// makes the timing assertion meaningful rather than decorative.
  private func launch() -> XCUIApplication {
    let app = XCUIApplication()
    app.launchArguments = ["--uitest-seed-dashboard"]
    app.launchEnvironment["UITEST_RADARR_STATE"] = "slow-library"
    app.launch()
    app.buttons["Services"].firstMatch.tap()
    return app
  }

  private func openRadarr(in app: XCUIApplication) {
    let row = app.descendants(matching: .any)
      .matching(identifier: "services.row.\(radarr)").firstMatch
    XCTAssertTrue(row.waitForExistence(timeout: 15), "the Radarr row never appeared")
    row.tap()
  }

  private func leaveRadarr(in app: XCUIApplication) {
    app.navigationBars.buttons["Services"].firstMatch.tap()
  }

  func testComingBackToAServiceShowsItsLibraryWithoutRefetching() throws {
    // Compact width only. The split view's shell has no back button to the
    // hub, and this test is about the phone's push-and-pop navigation
    // (CLAUDE.md, "`navigationBars.buttons` by index is not "back" on iPad").
    try XCTSkipUnless(
      UIDevice.current.userInterfaceIdiom == .phone, "push-and-pop navigation is iPhone-only")
    let app = launch()

    openRadarr(in: app)
    let firstRow = app.descendants(matching: .any).matching(identifier: "radarr.row.10").firstMatch
    XCTAssertTrue(
      firstRow.waitForExistence(timeout: 20),
      "the library never loaded the first time")

    leaveRadarr(in: app)
    XCTAssertTrue(
      app.descendants(matching: .any).matching(identifier: "services.row.\(radarr)")
        .firstMatch.waitForExistence(timeout: 10),
      "never got back to the hub")

    openRadarr(in: app)

    // **One second, against a three-second fetch.** A rebuilt store would have
    // to go back to the repository, so it could not possibly have rows yet.
    // This is the assertion that fails without the registry.
    XCTAssertTrue(
      firstRow.waitForExistence(timeout: 1),
      "the library was not on screen immediately — the store was rebuilt")
  }
}
