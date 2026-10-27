import XCTest

/// NZBGet's smoke paths, driven through **demo mode** — the same approach as
/// `ArrDemoSmokeUITests` and for the same reason: these screens have no DEBUG
/// seeded fake, so demo mode is the only way to reach them at all, and it is
/// the path an App Store reviewer takes.
///
/// Runs on iPad too, so tab taps use `.firstMatch` throughout
/// (CLAUDE.md, "With the sidebar showing, two elements are labelled "Services"").
@MainActor
final class DownloadClientDemoUITests: XCTestCase {
  /// `DemoServices` numbers instances by `idSuffix`'s name list: NZBGet is 09.
  private let nzbget = "D0000000-0000-0000-0000-000000000009"

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

  private func openService(_ id: String, in app: XCUIApplication) {
    app.buttons["Services"].firstMatch.tap()
    let row = app.descendants(matching: .any).matching(identifier: "services.row.\(id)").firstMatch
    XCTAssertTrue(scrollTo(row, in: app), "the demo hub never offered \(id)")
    row.tap()
  }

  private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
    app.descendants(matching: .any).matching(identifier: identifier).firstMatch
  }

  @discardableResult
  private func reveal(_ element: XCUIElement, in app: XCUIApplication) -> Bool {
    scrollTo(element, in: app, attempts: 12)
  }

  private func anyRow(prefix: String, in app: XCUIApplication) -> XCUIElement {
    app.descendants(matching: .any)
      .matching(NSPredicate(format: "identifier BEGINSWITH %@", prefix)).firstMatch
  }

  // MARK: - NZBGet

  func testTheNZBGetQueueHistoryAndStatusAllRender() {
    let app = launchIntoDemo()
    openService(nzbget, in: app)

    XCTAssertTrue(
      anyRow(prefix: "nzbget.row.", in: app).waitForExistence(timeout: 20),
      "the demo NZBGet queue never loaded")
    XCTAssertTrue(element("nzbget.summary", in: app).exists, "no status header")

    app.buttons["History"].firstMatch.tap()
    XCTAssertTrue(
      anyRow(prefix: "nzbget.history.row.", in: app).waitForExistence(timeout: 20),
      "the demo history is empty")

    app.buttons["Status"].firstMatch.tap()
    XCTAssertTrue(
      element("nzbget.status", in: app).waitForExistence(timeout: 20), "no status section")
  }

  func testPausingTheWholeServerShowsInTheHeader() {
    let app = launchIntoDemo()
    openService(nzbget, in: app)
    XCTAssertTrue(anyRow(prefix: "nzbget.row.", in: app).waitForExistence(timeout: 20))

    // The state is read from the label. On iOS 27 a toolbar button's
    // `accessibilityValue` does not reach the tree, and the label
    // already names the action the state allows.
    let toggle = element("nzbget.globalPause", in: app)
    XCTAssertTrue(toggle.waitForExistence(timeout: 10))
    XCTAssertEqual(toggle.label, "Pause Downloading")

    toggle.tap()

    // Re-read from the service rather than assumed, so this asserts the round
    // trip and not an optimistic flip.
    let resumed = XCTNSPredicateExpectation(
      predicate: NSPredicate(format: "label == 'Resume Downloading'"),
      object: element("nzbget.globalPause", in: app))
    XCTAssertEqual(
      XCTWaiter().wait(for: [resumed], timeout: 20), .completed,
      "the global pause never reported back")
  }

  // MARK: - The cross-service link

  /// The payoff of both families being in one app: an *arr queue row opens
  /// its download in NZBGet, in demo mode.
  func testAUsenetQueueRowOpensTheItemInNZBGet() {
    let app = launchIntoDemo()
    openService("D0000000-0000-0000-0000-000000000003", in: app)

    XCTAssertTrue(element("arr.shell", in: app).waitForExistence(timeout: 20), "no *arr shell")
    app.buttons["Queue"].firstMatch.tap()

    let link = element("queue.row.2.openClient", in: app)
    XCTAssertTrue(reveal(link, in: app), "the usenet queue row offered no link")
    link.tap()

    XCTAssertTrue(
      element("nzbget.summary", in: app).waitForExistence(timeout: 25),
      "the link didn't reach NZBGet's queue")
  }
}
