import XCTest

/// Parity check controls and the Parity screen (issue #22), against
/// `FakeSystemRepository`'s parity check, never a live server.
///
/// The fake starts with a running, correcting check at 63%, the fixture every
/// other dashboard class sees. Its actions change that state, and a cancel adds
/// a history row, so each test here drives the real store and views through
/// the same transitions a server would report. `UITEST_DASHBOARD_STATE=
/// parity-action-fails` makes every action fail with a server message.
///
/// **No `UITEST_POLL_INTERVAL_MS`.** The fake answers every poll with its
/// current state, so a poll cannot undo an action. But a successful poll
/// replaces `.actionFailed`, and the failure test reads that message, so the
/// 30-second default stays.
///
/// Each test also saves screenshots (see `saveScreenshot(named:)`), because
/// the dialogs' copy and the controls' layout can only be judged by eye.
@MainActor
final class ParityCheckUITests: XCTestCase {
  override func setUp() {
    super.setUp()
    continueAfterFailure = false
  }

  private func launch(state: String? = nil) -> XCUIApplication {
    let app = XCUIApplication()
    app.launchArguments = ["--uitest-seed-dashboard"]
    if let state { app.launchEnvironment["UITEST_DASHBOARD_STATE"] = state }
    app.launch()
    useTabBarLayout(in: app)
    return app
  }

  private func action(_ slug: String, in app: XCUIApplication) -> XCUIElement {
    app.buttons["parity.action.\(slug)"].firstMatch
  }

  /// A button in an open confirmation dialog. The dialog's "Cancel Check"
  /// shares its label with the control that opened it, so this excludes the
  /// controls by identifier.
  private func dialogButton(_ label: String, in app: XCUIApplication) -> XCUIElement {
    app.buttons.matching(
      NSPredicate(format: "label == %@ AND NOT (identifier BEGINSWITH 'parity.action.')", label)
    ).firstMatch
  }

  private func waitForDashboard(_ app: XCUIApplication) {
    XCTAssertTrue(
      app.descendants(matching: .any).matching(identifier: "array.state").firstMatch
        .waitForExistence(timeout: 10),
      "the dashboard never loaded"
    )
  }

  /// Cancels the running check through its confirmation, leaving the fake idle.
  private func cancelCheck(in app: XCUIApplication) {
    let cancel = action("cancel", in: app)
    XCTAssertTrue(scrollUntilHittable(cancel, in: app), "Cancel Check was not on screen")
    cancel.tap()
    let confirm = dialogButton("Cancel Check", in: app)
    XCTAssertTrue(confirm.waitForExistence(timeout: 5), "Cancel Check did not ask for confirmation")
    confirm.tap()
    XCTAssertTrue(action("start", in: app).waitForExistence(timeout: 10), "Start never appeared after a cancel")
  }

  // MARK: - Controls per state

  func testARunningCheckOffersPauseAndCancelButNotStart() throws {
    let app = launch()
    waitForDashboard(app)

    XCTAssertTrue(action("pause", in: app).waitForExistence(timeout: 5))
    XCTAssertTrue(action("cancel", in: app).exists)
    // VoiceOver reads the title alone, not the icon's name as well.
    XCTAssertEqual(action("pause", in: app).label, "Pause")
    XCTAssertEqual(action("cancel", in: app).label, "Cancel Check")
    XCTAssertFalse(action("start", in: app).exists, "Start must not appear while a check runs")
    XCTAssertFalse(action("resume", in: app).exists, "Resume must not appear while a check runs")
    try saveScreenshot(named: "parity-dashboard-running")
  }

  func testPauseAndResumeRefreshTheControls() throws {
    let app = launch()
    waitForDashboard(app)

    let pause = action("pause", in: app)
    XCTAssertTrue(scrollUntilHittable(pause, in: app))
    pause.tap()

    // No confirmation for Pause: the controls change straight away.
    let resume = action("resume", in: app)
    XCTAssertTrue(resume.waitForExistence(timeout: 10), "Resume never appeared after Pause")
    XCTAssertFalse(pause.exists, "Pause should be gone from a paused check")
    XCTAssertTrue(action("cancel", in: app).exists, "a paused check can still be cancelled")
    try saveScreenshot(named: "parity-dashboard-paused")

    resume.tap()
    XCTAssertTrue(pause.waitForExistence(timeout: 10), "Pause never came back after Resume")
    XCTAssertFalse(resume.exists)
  }

  // MARK: - Confirmations

  func testCancelAsksFirstAndDontCancelKeepsTheCheck() throws {
    let app = launch()
    waitForDashboard(app)

    let cancel = action("cancel", in: app)
    XCTAssertTrue(scrollUntilHittable(cancel, in: app))
    cancel.tap()

    let confirm = dialogButton("Cancel Check", in: app)
    XCTAssertTrue(confirm.waitForExistence(timeout: 5), "Cancel Check did not ask for confirmation")
    XCTAssertTrue(app.staticTexts["Cancel the parity check?"].exists, "the confirmation has no title")
    try saveScreenshot(named: "parity-cancel-confirmation")

    // iPad shows the dialog as a popover with no dismiss button; tapping
    // outside it is SwiftUI's own mechanics. The phone's sheet has one.
    let keep = dialogButton("Don't Cancel", in: app)
    if keep.exists {
      keep.tap()
      XCTAssertTrue(action("pause", in: app).waitForExistence(timeout: 5))
      XCTAssertFalse(action("start", in: app).exists, "dismissing the confirmation must not cancel the check")
    }
  }

  func testStartAsksWhetherToCorrectAndPassesTheChoice() throws {
    let app = launch()
    waitForDashboard(app)
    // The fixture's running check is a correcting one.
    XCTAssertTrue(app.staticTexts["Correcting"].waitForExistence(timeout: 5))

    cancelCheck(in: app)
    XCTAssertFalse(action("pause", in: app).exists, "a cancelled check has nothing to pause")

    let start = action("start", in: app)
    XCTAssertTrue(scrollUntilHittable(start, in: app))
    start.tap()

    let checkOnly = dialogButton("Check Only", in: app)
    XCTAssertTrue(checkOnly.waitForExistence(timeout: 5), "Start did not ask whether to correct errors")
    XCTAssertTrue(dialogButton("Check and Correct Errors", in: app).exists)
    try saveScreenshot(named: "parity-start-dialog")
    checkOnly.tap()

    // Running again, and not correcting: the fake records `correct: false`.
    XCTAssertTrue(action("pause", in: app).waitForExistence(timeout: 10), "the check never started")
    XCTAssertFalse(app.staticTexts["Correcting"].exists, "Check Only started a correcting check")

    cancelCheck(in: app)
    action("start", in: app).tap()
    let correct = dialogButton("Check and Correct Errors", in: app)
    XCTAssertTrue(correct.waitForExistence(timeout: 5))
    correct.tap()
    XCTAssertTrue(app.staticTexts["Correcting"].waitForExistence(timeout: 10), "Check and Correct Errors did not correct")
  }

  // MARK: - Failure

  func testAFailedActionShowsTheServersMessageAndKeepsTheDashboard() throws {
    let app = launch(state: "parity-action-fails")
    waitForDashboard(app)

    let pause = action("pause", in: app)
    XCTAssertTrue(scrollUntilHittable(pause, in: app))
    pause.tap()

    let message = app.staticTexts["Parity check could not be changed while the array is busy"]
    XCTAssertTrue(message.waitForExistence(timeout: 10), "the server's message never reached the screen")
    XCTAssertTrue(pause.exists, "a failed Pause must leave the running check's controls")
    try saveScreenshot(named: "parity-action-failed")
  }

  // MARK: - Parity screen

  func testTheParityScreenListsHistoryAndACancelAddsARow() throws {
    let app = launch()
    waitForDashboard(app)

    let link = app.descendants(matching: .any).matching(identifier: "parity.history.link").firstMatch
    XCTAssertTrue(scrollUntilHittable(link, in: app), "the Parity History link was not on screen")
    link.tap()

    let newest = app.descendants(matching: .any).matching(identifier: "parity.history.row.0").firstMatch
    XCTAssertTrue(newest.waitForExistence(timeout: 10), "the history never loaded")
    // Date, duration, speed, errors and status, all in one row.
    XCTAssertTrue(newest.label.contains("133.1 MB/s"), newest.label)
    XCTAssertTrue(newest.label.contains("1d 1h 2m"), newest.label)
    XCTAssertTrue(newest.label.contains("0 errors"), newest.label)
    XCTAssertTrue(newest.label.contains("Completed"), newest.label)

    // A line the server could not read says so instead of reading as zero.
    let unread = app.descendants(matching: .any).matching(identifier: "parity.history.row.3").firstMatch
    XCTAssertTrue(scrollTo(unread, in: app))
    XCTAssertTrue(unread.label.contains("Unknown date"), unread.label)
    XCTAssertTrue(unread.label.contains("Errors unknown"), unread.label)
    XCTAssertFalse(unread.label.contains("nan"), unread.label)
    try saveScreenshot(named: "parity-screen-running")

    // The controls are here too, and a cancel shows up in the history.
    cancelCheck(in: app)
    let row4 = app.descendants(matching: .any).matching(identifier: "parity.history.row.4").firstMatch
    XCTAssertTrue(
      row4.waitForExistence(timeout: 10) || scrollTo(row4, in: app),
      "the cancelled check never joined the history"
    )
    let first = app.descendants(matching: .any).matching(identifier: "parity.history.row.0").firstMatch
    XCTAssertTrue(scrollTo(first, in: app))
    XCTAssertTrue(first.label.contains("Cancelled"), first.label)
    // `LabeledContent` may put its value in `value` rather than `label`.
    let status = app.descendants(matching: .any).matching(identifier: "parity.status").firstMatch
    let statusText = status.label + " " + String(describing: status.value ?? "")
    XCTAssertTrue(statusText.contains("Cancelled"), statusText)
    try saveScreenshot(named: "parity-screen-cancelled")
  }
}
