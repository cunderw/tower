import XCTest

/// Covers the two `DashboardView` scenarios no other UI test file already
/// exercises: the loaded screen's capacity ring and array-state pill
/// existing together with all three services rows, and the failed-load
/// `ContentUnavailableView` actually recovering when "Try Again" is tapped.
///
/// Deliberately does **not** duplicate:
/// - Services-row tap-to-navigate (`DashboardServicesUITests` already taps
///   `services.docker`/`.vms`/`.shares` and asserts the tab bar switches).
/// - Disk-detail push-and-title (`DiskDetailUITests` already taps the first
///   row of all three disk groups and asserts the pushed screen's title).
///
/// Taps with XCUITest's own `.tap()` because `idb ui tap` does nothing on
/// macOS 27 (see `DashboardServicesUITests`).
@MainActor
final class DashboardUITests: XCTestCase {
  /// `state` selects `FakeSystemRepository.Outcome` via
  /// `UITEST_DASHBOARD_STATE` (see `UITestSupport.swift`): `nil` for the
  /// default success fixture, `"failure"` for a permanently failed load, or
  /// `"retry-succeeds"` for a load that fails once and then recovers.
  private func launch(state: String? = nil) -> XCUIApplication {
    let app = XCUIApplication()
    app.launchArguments = ["--uitest-seed-dashboard"]
    if let state {
      app.launchEnvironment["UITEST_DASHBOARD_STATE"] = state
    }
    app.launch()
    return app
  }

  private func element(identifier: String, in app: XCUIApplication) -> XCUIElement {
    app.descendants(matching: .any).matching(identifier: identifier).firstMatch
  }

  func testLoadedDashboardShowsCapacityRingStatePillAndAllServiceRows() {
    let app = launch()

    let ring = element(identifier: "dashboard.capacityRing", in: app)
    XCTAssertTrue(ring.waitForExistence(timeout: 5), "dashboard.capacityRing never appeared on a loaded dashboard")

    let statePill = element(identifier: "array.state", in: app)
    XCTAssertTrue(statePill.waitForExistence(timeout: 5), "array.state pill never appeared on a loaded dashboard")
    // `UITestFixtures`' `ArrayStatus.uitestFixture` reports `state: "STARTED"`
    // — `ArrayHeroCard` renders it `.capitalized` as "Started".
    XCTAssertTrue(
      statePill.label.localizedCaseInsensitiveContains("started"),
      "array.state pill should reflect the array's STARTED state, got \"\(statePill.label)\""
    )

    // Existence only, deliberately: `DashboardServicesUITests` already
    // proves each row's exact label and that tapping it switches tabs. This
    // test's job is proving all three render together on a freshly loaded
    // dashboard, not re-proving their navigation behavior.
    XCTAssertTrue(element(identifier: "services.docker", in: app).waitForExistence(timeout: 5), "services.docker row missing on a loaded dashboard")
    XCTAssertTrue(element(identifier: "services.vms", in: app).exists, "services.vms row missing on a loaded dashboard")
    XCTAssertTrue(element(identifier: "services.shares", in: app).exists, "services.shares row missing on a loaded dashboard")
  }

  func testFailedDashboardShowsContentUnavailableViewAndTryAgainRecovers() {
    let app = launch(state: "retry-succeeds")

    // `dashboard.error`/`dashboard.retry` let this match by
    // identifier instead of string-matching user-facing copy, so a wording
    // change to the error message or button title can't break this test.
    let message = element(identifier: "dashboard.error", in: app)
    XCTAssertTrue(message.waitForExistence(timeout: 5), "dashboard.error never appeared on a failed dashboard")

    let tryAgain = element(identifier: "dashboard.retry", in: app)
    XCTAssertTrue(tryAgain.waitForExistence(timeout: 5), "dashboard.retry button never appeared on the failed dashboard")

    tryAgain.tap()

    // `FakeSystemRepository(outcome: .failFirstThenRecover)` fails only the
    // automatic initial load; this second `dashboard()` call — triggered by
    // the tap above — succeeds. A "Try Again" button that silently did
    // nothing would leave the screen on the exact same failed view forever,
    // so waiting for a loaded-only element is what actually distinguishes
    // "retried" from "did nothing": a bare re-assertion of the failed view
    // would pass either way.
    let ring = element(identifier: "dashboard.capacityRing", in: app)
    XCTAssertTrue(ring.waitForExistence(timeout: 5), "tapping Try Again never recovered the dashboard to its loaded state")
    XCTAssertFalse(message.exists, "dashboard.error still showing after a successful retry")
  }
}
