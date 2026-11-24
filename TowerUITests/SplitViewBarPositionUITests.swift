import XCTest

/// The split view's top bars stay where they are after a push (issue #40).
///
/// On iPad under the top tab bar, a push inside the detail column moved both
/// columns' navigation bars 44 pt lower, and they stayed there after Back and
/// after another service was selected. The App Store captures for streams,
/// music and subtitles showed the lower bars.
@MainActor
final class SplitViewBarPositionUITests: XCTestCase {
  override func setUp() {
    super.setUp()
    continueAfterFailure = false
  }

  func testBarsStayLevelAfterADetailPush() throws {
    try XCTSkipIf(UIDevice.current.userInterfaceIdiom != .pad, "only the iPad has a split view")

    let app = XCUIApplication()
    app.launchArguments = ["--uitest-reset-credentials"]
    app.launch()
    let demo = app.buttons["connect.demo"]
    XCTAssertTrue(demo.waitForExistence(timeout: 15), "the connect screen offered no demo")
    demo.tap()
    XCTAssertTrue(
      app.descendants(matching: .any).matching(identifier: "services.docker")
        .firstMatch.waitForExistence(timeout: 15),
      "the demo never reached a loaded dashboard")
    useTabBarLayout(in: app)
    app.buttons["Services"].firstMatch.tap()

    let add = app.buttons["services.add"].firstMatch
    open("D0000000-0000-0000-0000-000000000001", named: "Radarr", in: app)
    let movie = app.descendants(matching: .any)
      .matching(NSPredicate(format: "identifier BEGINSWITH 'radarr.row.'")).firstMatch
    XCTAssertTrue(movie.waitForExistence(timeout: 20), "the demo library never loaded")
    XCTAssertTrue(add.exists, "the hub had no Add Service button")
    let level = add.frame.minY

    movie.tap()
    tapBack(in: app)
    XCTAssertTrue(movie.waitForExistence(timeout: 10), "Back never returned to the library")

    open("D0000000-0000-0000-0000-000000000010", named: "Tautulli", in: app)
    XCTAssertTrue(
      app.descendants(matching: .any)
        .matching(NSPredicate(format: "identifier BEGINSWITH 'tautulli.stream.'")).firstMatch
        .waitForExistence(timeout: 25),
      "the demo activity never loaded")
    XCTAssertEqual(
      add.frame.minY, level, accuracy: 1,
      "the hub's bar moved after a push in the detail column")
  }

  private func open(_ id: String, named name: String, in app: XCUIApplication) {
    let row = app.descendants(matching: .any).matching(identifier: "services.row.\(id)").firstMatch
    XCTAssertTrue(row.waitForExistence(timeout: 15), "the demo hub never offered a \(name)")
    XCTAssertTrue(scrollUntilHittable(row, in: app, within: row), "the \(name) row was off screen")
    row.tap()
  }
}
