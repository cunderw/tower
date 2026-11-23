import XCTest

/// Start and stop the array (issue #25), against `FakeSystemRepository`'s
/// `FakeArray`, never a live server.
///
/// `UITEST_DASHBOARD_STATE` picks the array: the default fixture is started,
/// `array-stopped` and `array-encrypted` are stopped, `array-action-fails`
/// fails every action with a server message, and `array-slow` holds every
/// action for 90 s so the progress line can be seen.
///
/// **`UITEST_ARRAY_POLL_INTERVAL_MS` for the wrong passphrase.** The fake
/// leaves the array stopped and reports no error, so the store waits out its
/// 30 re-fetches before it says so. At 50 ms each that is under two seconds.
/// Not `UITEST_POLL_INTERVAL_MS`: a fast dashboard poll would replace the
/// error line before the test reads it.
///
/// Each test also saves screenshots (see `saveScreenshot(named:)`). The
/// passphrase sheet is photographed only with an empty field.
@MainActor
final class ArrayStateUITests: XCTestCase {
  /// `FakeArray.passphrase` in the app. A fake's, never a real one.
  private let fakePassphrase = "uitest-correct-passphrase"

  override func setUp() {
    super.setUp()
    continueAfterFailure = false
  }

  private func launch(state: String? = nil, fastArrayPoll: Bool = false) -> XCUIApplication {
    let app = XCUIApplication()
    app.launchArguments = ["--uitest-seed-dashboard"]
    if let state { app.launchEnvironment["UITEST_DASHBOARD_STATE"] = state }
    if fastArrayPoll { app.launchEnvironment["UITEST_ARRAY_POLL_INTERVAL_MS"] = "50" }
    app.launch()
    useTabBarLayout(in: app)
    XCTAssertTrue(statePill(in: app).waitForExistence(timeout: 10), "the dashboard never loaded")
    return app
  }

  private func statePill(in app: XCUIApplication) -> XCUIElement {
    app.descendants(matching: .any).matching(identifier: "array.state").firstMatch
  }

  private func action(_ slug: String, in app: XCUIApplication) -> XCUIElement {
    app.buttons["array.action.\(slug)"].firstMatch
  }

  private func waitForPill(_ text: String, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
    let pill = statePill(in: app)
    let reads = NSPredicate(format: "label CONTAINS[c] %@", text)
    let expectation = XCTNSPredicateExpectation(predicate: reads, object: pill)
    XCTAssertEqual(
      XCTWaiter().wait(for: [expectation], timeout: 10), .completed,
      "the array never read \(text), got \"\(pill.label)\"", file: file, line: line
    )
  }

  /// Taps Stop Array and returns the confirmation's Stop Array button.
  private func askToStop(in app: XCUIApplication) -> XCUIElement {
    let stop = action("stop", in: app)
    XCTAssertTrue(scrollUntilHittable(stop, in: app), "Stop Array was not on screen")
    stop.tap()
    let confirm = dialogButton("Stop Array", in: app)
    XCTAssertTrue(confirm.waitForExistence(timeout: 5), "Stop Array did not ask for confirmation")
    return confirm
  }

  /// Taps Start Array on the encrypted fixture and returns the sheet's field.
  private func openPassphraseSheet(in app: XCUIApplication) -> XCUIElement {
    let start = action("start", in: app)
    XCTAssertTrue(scrollUntilHittable(start, in: app), "Start Array was not on screen")
    start.tap()
    let field = app.secureTextFields["array.passphrase.field"]
    XCTAssertTrue(field.waitForExistence(timeout: 5), "an encrypted start did not ask for the passphrase")
    return field
  }

  // MARK: - Which button

  func testAStartedArrayOffersStopAndNotStart() throws {
    let app = launch()
    XCTAssertTrue(action("stop", in: app).waitForExistence(timeout: 5))
    XCTAssertEqual(action("stop", in: app).label, "Stop Array")
    XCTAssertFalse(action("start", in: app).exists, "Start and Stop must never show together")
    try saveScreenshot(named: "array-started")
  }

  func testAStoppedArrayOffersStartAndNotStop() throws {
    let app = launch(state: "array-stopped")
    waitForPill("Stopped", in: app)
    XCTAssertTrue(action("start", in: app).waitForExistence(timeout: 5))
    XCTAssertEqual(action("start", in: app).label, "Start Array")
    XCTAssertFalse(action("stop", in: app).exists, "Start and Stop must never show together")
    // A stopped array runs no parity check, so it has nothing to pause.
    XCTAssertFalse(app.buttons["parity.action.pause"].exists)
    try saveScreenshot(named: "array-stopped")
  }

  // MARK: - Stop

  func testStopAsksForConfirmationNamingTheConsequenceThenStops() throws {
    let app = launch()
    let confirm = askToStop(in: app)
    XCTAssertTrue(app.staticTexts["Stop the array?"].exists, "the confirmation has no title")
    let consequence = app.staticTexts.matching(
      NSPredicate(format: "label CONTAINS %@", "Docker containers and VMs that use the array stop")
    ).firstMatch
    XCTAssertTrue(consequence.exists, "the confirmation does not name what stops with the array")
    // Asking is not stopping.
    XCTAssertTrue(statePill(in: app).label.localizedCaseInsensitiveContains("started"))
    try saveScreenshot(named: "array-stop-confirmation")

    confirm.tap()
    waitForPill("Stopped", in: app)
    XCTAssertTrue(action("start", in: app).waitForExistence(timeout: 5), "Start never replaced Stop")
    XCTAssertFalse(action("stop", in: app).exists, "Start and Stop must never show together")
    // The stop ended the fixture's running parity check.
    XCTAssertFalse(app.buttons["parity.action.pause"].exists)
  }

  /// The fake holds the action for 90 s, so this test waits out XCTest's
  /// 60 s animation wait while the spinner turns.
  func testTheControlsAreReplacedByAProgressLineWhileTheArrayStops() throws {
    let app = launch(state: "array-slow")
    askToStop(in: app).tap()

    let progress = app.descendants(matching: .any).matching(identifier: "array.progress").firstMatch
    XCTAssertTrue(progress.waitForExistence(timeout: 80), "no progress line while the array stops")
    XCTAssertTrue(progress.label.contains("Stopping the array"), progress.label)
    XCTAssertFalse(action("stop", in: app).exists, "Stop Array stayed on screen while the array stops")
    XCTAssertFalse(action("start", in: app).exists)
    let pause = app.buttons["parity.action.pause"]
    XCTAssertTrue(pause.exists)
    XCTAssertFalse(pause.isEnabled, "the parity controls stay enabled while the array stops")
    try saveScreenshot(named: "array-stopping")
  }

  // MARK: - Start

  func testStartStartsAStoppedArray() throws {
    let app = launch(state: "array-stopped")
    let start = action("start", in: app)
    XCTAssertTrue(scrollUntilHittable(start, in: app))
    start.tap()

    // A plain array starts at once: no confirmation, no passphrase.
    XCTAssertFalse(app.secureTextFields["array.passphrase.field"].exists)
    waitForPill("Started", in: app)
    XCTAssertTrue(action("stop", in: app).waitForExistence(timeout: 5), "Stop never replaced Start")
    XCTAssertFalse(action("start", in: app).exists, "Start and Stop must never show together")
  }

  func testAnEncryptedStartWithTheRightPassphraseStartsTheArray() throws {
    let app = launch(state: "array-encrypted")
    let field = openPassphraseSheet(in: app)
    let submit = app.buttons["array.passphrase.start"]
    XCTAssertFalse(submit.isEnabled, "Start is enabled with an empty passphrase")
    // The field takes focus on its own. Wait for the keyboard, so the capture
    // shows the sheet at rest rather than mid-rise.
    _ = app.keyboards.firstMatch.waitForExistence(timeout: 3)
    try saveScreenshot(named: "array-passphrase-sheet")

    type(fakePassphrase, into: field)
    XCTAssertTrue(submit.isEnabled)
    submit.tap()

    waitForPill("Started", in: app)
    XCTAssertFalse(field.exists, "the sheet stayed open after Start")
    XCTAssertTrue(action("stop", in: app).waitForExistence(timeout: 5))
  }

  func testAnEncryptedStartWithAWrongPassphraseSaysSo() throws {
    let app = launch(state: "array-encrypted", fastArrayPoll: true)
    let field = openPassphraseSheet(in: app)
    type("not-the-passphrase", into: field)
    app.buttons["array.passphrase.start"].tap()

    let message = app.staticTexts["The array did not start. The passphrase may be wrong."]
    XCTAssertTrue(message.waitForExistence(timeout: 15), "a wrong passphrase showed no error")
    XCTAssertTrue(statePill(in: app).label.localizedCaseInsensitiveContains("stopped"))
    XCTAssertTrue(action("start", in: app).exists, "Start must stay for another try")
    try saveScreenshot(named: "array-passphrase-wrong")

    // A second try opens an empty field: the sheet keeps nothing.
    let again = openPassphraseSheet(in: app)
    let value = again.value as? String ?? ""
    XCTAssertTrue(value.isEmpty || value == "Passphrase", "the field kept the last passphrase: \(value.count) characters")
    app.buttons["array.passphrase.cancel"].tap()
    XCTAssertFalse(again.waitForExistence(timeout: 2), "Cancel did not close the sheet")
  }

  // MARK: - Failure

  func testAFailedActionShowsTheServersMessageAndKeepsTheArray() throws {
    let app = launch(state: "array-action-fails")
    askToStop(in: app).tap()

    let message = app.staticTexts["Array state is still being updated"]
    XCTAssertTrue(message.waitForExistence(timeout: 10), "the server's message never reached the screen")
    XCTAssertTrue(statePill(in: app).label.localizedCaseInsensitiveContains("started"))
    XCTAssertTrue(action("stop", in: app).exists, "a failed stop must leave Stop Array")
    try saveScreenshot(named: "array-action-failed")
  }
}
