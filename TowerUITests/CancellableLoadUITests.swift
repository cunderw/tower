import XCTest

/// The escape hatch from a load that never resolves.
///
/// `UITEST_DASHBOARD_STATE=hangs` makes `dashboard()` sleep for an hour —
/// cancellation-aware, so `cancelLoad()` reaches it the way a real request's
/// cancellation would. That models the situation Tower is most likely to meet: a
/// LAN address that has become unreachable, where a request neither succeeds nor
/// fails fast and the 60-second default timeout is the only thing that ends it.
@MainActor
final class CancellableLoadUITests: XCTestCase {
  override func setUp() {
    super.setUp()
    continueAfterFailure = false
  }

  private func launchHanging() -> XCUIApplication {
    let app = XCUIApplication()
    app.launchArguments = ["--uitest-seed-dashboard"]
    app.launchEnvironment["UITEST_DASHBOARD_STATE"] = "hangs"
    app.launch()
    return app
  }

  func testAHangingLoadOffersCancel() {
    let app = launchHanging()

    XCTAssertTrue(
      app.buttons["loading.cancel"].waitForExistence(timeout: 10),
      "a load that never resolves offered no way out"
    )
  }

  func testCancellingLandsOnARetryableFailureRatherThanTheSameSpinner() {
    // The whole point: cancelling has to leave the user somewhere with a way
    // forward. `.idle` would show the same spinner they were trying to escape.
    let app = launchHanging()

    let cancel = app.buttons["loading.cancel"]
    XCTAssertTrue(cancel.waitForExistence(timeout: 10), "Cancel never appeared")
    cancel.tap()

    XCTAssertTrue(
      app.buttons["dashboard.retry"].waitForExistence(timeout: 10),
      "cancelling didn't produce a retry affordance"
    )
    XCTAssertTrue(
      app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", "Cancelled")).firstMatch.exists,
      "the cancelled state didn't say it was cancelled"
    )
    // And the spinner is gone — the failure this test exists to prevent is
    // cancelling into an identical-looking screen.
    XCTAssertFalse(cancel.exists, "Cancel is still offered after the load was cancelled")
  }

  func testRetryingAfterCancelStartsANewLoad() {
    // Retrying re-enters the hanging load, so Cancel comes back. That proves the
    // retry actually re-invoked the repository rather than just clearing the
    // error — the same distinction `FakeSystemRepository.failFirstThenRecover`
    // draws.
    let app = launchHanging()

    let cancel = app.buttons["loading.cancel"]
    XCTAssertTrue(cancel.waitForExistence(timeout: 10))
    cancel.tap()

    let retry = app.buttons["dashboard.retry"]
    XCTAssertTrue(retry.waitForExistence(timeout: 10))
    retry.tap()

    XCTAssertTrue(
      app.buttons["loading.cancel"].waitForExistence(timeout: 10),
      "retrying after a cancel didn't start a new load"
    )
  }
}
