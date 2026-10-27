import XCTest

/// A failed history action on NZBGet's History tab.
///
/// Demo mode cannot fail, so this runs against the seeded NZBGet with
/// `UITEST_NZBGET_STATE=action-fails`, which serves demo data and fails the
/// history retry and delete.
@MainActor
final class NZBGetActionErrorUITests: XCTestCase {
  private let nzbget = "A0000000-0000-0000-0000-000000000003"

  override func setUp() {
    super.setUp()
    continueAfterFailure = false
  }

  private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
    app.descendants(matching: .any).matching(identifier: identifier).firstMatch
  }

  func testAFailedHistoryDeleteKeepsTheRowAndSaysWhy() throws {
    let app = XCUIApplication()
    app.launchArguments = ["--uitest-seed-dashboard"]
    app.launchEnvironment["UITEST_NZBGET_STATE"] = "action-fails"
    app.launch()
    app.buttons["Services"].firstMatch.tap()
    let service = element("services.row.\(nzbget)", in: app)
    XCTAssertTrue(service.waitForExistence(timeout: 10))
    service.tap()
    XCTAssertTrue(
      element("nzbget.sections", in: app).waitForExistence(timeout: 15),
      "the NZBGet screen never opened")

    app.buttons["History"].firstMatch.tap()
    let row = element("nzbget.history.row.30", in: app)
    XCTAssertTrue(row.waitForExistence(timeout: 15), "the history never loaded")
    XCTAssertFalse(element("nzbget.history.actionError", in: app).exists)

    // A full swipe can commit the delete by itself, so the button is tapped
    // only if the swipe left it showing.
    row.swipeLeft()
    let delete = element("nzbget.history.delete.30", in: app)
    if delete.waitForExistence(timeout: 3) { delete.tap() }

    XCTAssertTrue(
      element("nzbget.history.actionError", in: app).waitForExistence(timeout: 10),
      "the failed delete was silent")
    XCTAssertTrue(row.exists, "the history row was lost to a failed delete")
    try saveScreenshot(named: "nzbget-history-action-error")
  }
}
