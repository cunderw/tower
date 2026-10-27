import XCTest

/// Tautulli's smoke path through **demo mode**, following
/// `LidarrBazarrDemoUITests` and `OverseerrProwlarrDemoUITests`: this screen has
/// no DEBUG seeded fake, so demo mode is the only way to reach it, and it is the
/// path an App Store reviewer takes.
///
/// Runs on iPad too, so tab taps use `.firstMatch`
/// (CLAUDE.md, "With the sidebar showing, two elements are labelled "Services"").
@MainActor
final class TautulliDemoUITests: XCTestCase {
  /// `DemoServices` numbers instances by `idSuffix`'s name list: Tautulli is 10, the last.
  private let tautulli = "D0000000-0000-0000-0000-000000000010"

  override func setUp() {
    super.setUp()
    continueAfterFailure = false
  }

  private func launchIntoDemo() -> XCUIApplication {
    let app = XCUIApplication()
    app.launchArguments = ["--uitest-reset-credentials"]
    app.launch()
    let demo = app.buttons["connect.demo"]
    XCTAssertTrue(demo.waitForExistence(timeout: 15), "the connect screen offered no demo")
    demo.tap()
    return app
  }

  private func openTautulli(in app: XCUIApplication) {
    // Back to the tab bar first: with the iPad sidebar showing, "Services"
    // matches the collapsible section header as well as the tab, and tapping
    // the header collapses the rows this then looks for.
    useTabBarLayout(in: app)
    app.buttons["Services"].firstMatch.tap()
    let row = app.descendants(matching: .any)
      .matching(identifier: "services.row.\(tautulli)").firstMatch
    XCTAssertTrue(scrollTo(row, in: app), "the demo hub never offered a Tautulli")
    row.tap()
    XCTAssertTrue(
      element("tautulli.sections", in: app).waitForExistence(timeout: 20),
      "the Tautulli screen never appeared")
  }

  private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
    app.descendants(matching: .any).matching(identifier: identifier).firstMatch
  }

  private func anyRow(prefix: String, in app: XCUIApplication) -> XCUIElement {
    app.descendants(matching: .any)
      .matching(NSPredicate(format: "identifier BEGINSWITH %@", prefix)).firstMatch
  }

  @discardableResult
  private func reveal(_ element: XCUIElement, in app: XCUIApplication) -> Bool {
    scrollTo(element, in: app, attempts: 12)
  }

  private func waitForNonExistence(of element: XCUIElement, timeout: TimeInterval = 25) -> Bool {
    let gone = XCTNSPredicateExpectation(
      predicate: NSPredicate(format: "exists == false"), object: element)
    return XCTWaiter().wait(for: [gone], timeout: timeout) == .completed
  }

  // MARK: - Activity → terminate

  func testTerminatingAStreamRemovesItFromActivity() {
    let app = launchIntoDemo()
    openTautulli(in: app)

    let stream = anyRow(prefix: "tautulli.stream.", in: app)
    XCTAssertTrue(stream.waitForExistence(timeout: 25), "the demo activity never loaded")

    // The transcoding stream sorts first, and it is the one the demo exists to
    // show — but assert on whichever row is actually there rather than
    // assuming the sort.
    let identifier = stream.identifier
    let terminate = element("\(identifier).terminate", in: app)
    XCTAssertTrue(reveal(terminate, in: app), "the stream row offered no way to stop it")
    terminate.tap()

    let confirm = element("tautulli.confirmTerminate", in: app)
    XCTAssertTrue(
      confirm.waitForExistence(timeout: 15), "stopping a stream asked for no confirmation")
    confirm.tap()

    // Gone, and gone from the header's counts with it.
    XCTAssertTrue(
      waitForNonExistence(of: element(identifier, in: app)),
      "the stream stayed on screen after being stopped")
    XCTAssertTrue(
      element("tautulli.summary", in: app).waitForExistence(timeout: 15),
      "the activity header disappeared with the stream")
  }

  // MARK: - The other three sections

  func testHistoryUsersAndLibrariesAllLoadInDemoMode() {
    let app = launchIntoDemo()
    openTautulli(in: app)

    app.buttons["History"].firstMatch.tap()
    XCTAssertTrue(
      anyRow(prefix: "tautulli.history.", in: app).waitForExistence(timeout: 25),
      "the demo history never loaded")

    app.buttons["Users"].firstMatch.tap()
    XCTAssertTrue(
      anyRow(prefix: "tautulli.user.", in: app).waitForExistence(timeout: 25),
      "the demo user list never loaded")

    app.buttons["Libraries"].firstMatch.tap()
    XCTAssertTrue(
      anyRow(prefix: "tautulli.library.", in: app).waitForExistence(timeout: 25),
      "the demo library list never loaded")
  }

  func testAUserDrillInShowsThatUsersHistory() {
    let app = launchIntoDemo()
    openTautulli(in: app)

    app.buttons["Users"].firstMatch.tap()
    // Casey by identifier rather than whichever row sorts first: the demo's
    // never-seen user has no history, which would make this pass vacuously.
    let user = element("tautulli.user.5", in: app)
    XCTAssertTrue(user.waitForExistence(timeout: 25), "the demo user list never loaded")
    user.tap()

    XCTAssertTrue(
      anyRow(prefix: "tautulli.history.", in: app).waitForExistence(timeout: 25),
      "the user's own history never loaded")
  }

  func testASearchThatMatchesNothingKeepsItsSearchField() throws {
    let app = launchIntoDemo()
    openTautulli(in: app)

    app.buttons["History"].firstMatch.tap()
    XCTAssertTrue(
      element("tautulli.history.count", in: app).waitForExistence(timeout: 25),
      "the demo history never loaded")

    let search = app.searchFields.firstMatch
    XCTAssertTrue(search.waitForExistence(timeout: 10), "history offered no search field")
    search.tap()
    search.typeText("zzz")

    XCTAssertTrue(
      element("tautulli.history.empty", in: app).waitForExistence(timeout: 25),
      "a search for nothing never reached the empty state")
    // The query is still applied, so the field that clears it has to stay.
    let field = app.searchFields.firstMatch
    XCTAssertTrue(field.exists, "the search field went away with the results")
    XCTAssertTrue(
      (field.value as? String)?.contains("zzz") == true,
      "the search field no longer shows the query; it reads \(String(describing: field.value))")
    try saveScreenshot(named: "tautulli-history-no-matches")
  }
}
