import XCTest

/// Demo mode, driven exactly as an App Store reviewer would: from a cold launch,
/// through the connect screen, without a server.
///
/// These tests use **no** `--uitest-seed-dashboard` launch argument. That is the
/// point — they exercise the shipping path, not the DEBUG bypass, so what they
/// prove is what a reviewer will actually get.
@MainActor
final class DemoModeUITests: XCTestCase {
  override func setUp() {
    super.setUp()
    continueAfterFailure = false
  }

  private func launchIntoDemo() -> XCUIApplication {
    let app = XCUIApplication()
    // Clears any stored credential so the connect screen is what appears.
    app.launchArguments = ["--uitest-reset-credentials"]
    app.launch()

    let demo = app.buttons["connect.demo"]
    XCTAssertTrue(demo.waitForExistence(timeout: 15), "the connect screen offered no demo")
    demo.tap()
    return app
  }

  func testTheDemoIsOfferedOnTheConnectScreenWithoutAnyGesture() {
    // "Discoverable" is a requirement, not a nicety: an undiscoverable demo
    // doesn't serve a reviewer without a server, which is its whole purpose.
    let app = XCUIApplication()
    app.launchArguments = ["--uitest-reset-credentials"]
    app.launch()

    let demo = app.buttons["connect.demo"]
    XCTAssertTrue(demo.waitForExistence(timeout: 15), "no demo button on the connect screen")
    XCTAssertTrue(demo.isHittable, "the demo button isn't reachable without scrolling or a gesture")
  }

  func testTheDemoShowsAPopulatedServicesHub() {
    // The Services tab is most of what Tower does, and a reviewer has no
    // Radarr — the demo is the only way they see it work.
    let app = launchIntoDemo()
    app.buttons["Services"].firstMatch.tap()

    let rows = app.descendants(matching: .any)
      .matching(NSPredicate(format: "identifier BEGINSWITH 'services.row.'"))
    XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 15), "the demo hub is empty")
    XCTAssertFalse(
      app.descendants(matching: .any).matching(identifier: "services.empty").firstMatch.exists,
      "the demo hub showed its empty state")

    // Both a healthy and a failing service, before scrolling anywhere — the
    // badge means nothing on a screen where every row is green.
    let labels = (0..<rows.count).map { rows.element(boundBy: $0).label }
    XCTAssertTrue(labels.contains { $0.contains("Connected") }, "no connected service in the demo")
    XCTAssertTrue(labels.contains { $0.contains("Unreachable") }, "no failing service in the demo")

    // All four sections are present — the later ones only after scrolling, since
    // a SwiftUI List doesn't render what it hasn't reached (see `scrollTo`).
    for header in ["Media management", "Requests & indexers", "Downloads", "Monitoring"] {
      XCTAssertTrue(
        scrollTo(app.staticTexts[header], in: app), "no \(header) section in the demo")
    }
  }

  func testTheDemoOpensARadarrLibraryWithRealData() {
    // Demo mode is the only path to the *arr surface a reviewer without a
    // server has, so the library has to be populated and navigable there, not
    // just under the DEBUG launch argument the other suites use.
    let app = launchIntoDemo()
    app.buttons["Services"].firstMatch.tap()

    let radarr = app.descendants(matching: .any)
      .matching(NSPredicate(format: "identifier BEGINSWITH 'services.row.'"))
      .containing(NSPredicate(format: "label CONTAINS 'Radarr'"))
      .firstMatch
    XCTAssertTrue(radarr.waitForExistence(timeout: 15), "no Radarr on the demo hub")
    radarr.tap()

    let rows = app.descendants(matching: .any)
      .matching(NSPredicate(format: "identifier BEGINSWITH 'radarr.row.'"))
    XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 20), "the demo library is empty")

    // The queue is populated too — the section a reviewer checks to see the app
    // doing something.
    app.buttons["Queue"].firstMatch.tap()
    let queueRows = app.descendants(matching: .any)
      .matching(NSPredicate(format: "identifier BEGINSWITH 'queue.row.'"))
    XCTAssertTrue(queueRows.firstMatch.waitForExistence(timeout: 20), "the demo queue is empty")
  }

  func testTheDemoLoadsADashboardWithoutAServer() {
    let app = launchIntoDemo()

    XCTAssertTrue(
      app.descendants(matching: .any).matching(identifier: "services.docker")
        .firstMatch.waitForExistence(timeout: 15),
      "the demo never reached a loaded dashboard"
    )
  }

  func testEveryTabIsPopulatedInTheDemo() {
    // A reviewer will tap all four. Any that shows an error or an empty state
    // reads as a broken app.
    let app = launchIntoDemo()
    XCTAssertTrue(
      app.descendants(matching: .any).matching(identifier: "services.docker")
        .firstMatch.waitForExistence(timeout: 15)
    )

    app.buttons["Docker"].firstMatch.tap()
    XCTAssertTrue(
      app.staticTexts["code-server"].waitForExistence(timeout: 15),
      "the Docker tab is empty in the demo"
    )

    app.buttons["VMs"].firstMatch.tap()
    XCTAssertTrue(
      app.staticTexts["Debian Desktop"].waitForExistence(timeout: 15),
      "the VMs tab is empty in the demo"
    )

    app.buttons["Shares"].firstMatch.tap()
    XCTAssertTrue(
      app.staticTexts["appdata"].waitForExistence(timeout: 15),
      "the Shares tab is empty in the demo"
    )
  }

  func testAMutationChangesTheDemoServerAndTheChangeIsVisibleElsewhere() {
    // What matters most: a reviewer can start and stop a container and see it
    // change. And because all six demo repositories share one
    // in-memory server, the *dashboard's* running count follows — which is what
    // makes the demo hold together rather than being six unrelated fixtures.
    let app = launchIntoDemo()
    XCTAssertTrue(
      app.descendants(matching: .any).matching(identifier: "services.docker")
        .firstMatch.waitForExistence(timeout: 15)
    )
    let dockerRow = app.descendants(matching: .any).matching(identifier: "services.docker").firstMatch
    let before = dockerRow.label

    app.buttons["Docker"].firstMatch.tap()
    let stopped = app.descendants(matching: .any)
      .matching(identifier: "docker.row.demo-container-freshrss").firstMatch
    XCTAssertTrue(stopped.waitForExistence(timeout: 15), "the stopped demo container never appeared")
    XCTAssertTrue(stopped.label.contains("Exited"), "fixture precondition: it starts stopped")

    // Tap Start only if the swipe *revealed* it. A leading swipe that travels
    // far enough commits its action outright, and in the iPad split layout
    // the list column is narrow enough that `swipeRight()` often does, flipping
    // the row to Running with no button ever appearing. Requiring the button
    // would assert on the width of the column rather than on the mutation,
    // which is what the next assertion covers either way. Same shape as
    // `DockerUITests.startBySwipe`.
    stopped.swipeRight()
    let start = app.buttons["Start"]
    if start.waitForExistence(timeout: 10) { start.tap() }

    XCTAssertTrue(
      waitForLabel(stopped, toContain: "Running", timeout: 15),
      "starting a demo container didn't change its row: \(stopped.label)"
    )

    app.buttons["Dashboard"].firstMatch.tap()
    XCTAssertTrue(
      waitForLabel(dockerRow, toNotEqual: before, timeout: 15),
      "the dashboard's running count didn't follow the demo mutation: \(dockerRow.label)"
    )
  }

  func testLeavingTheDemoReturnsToConnectAndStoresNothing() {
    // Nothing may reach the keychain: relaunching after signing out of the demo
    // has to land on the connect screen, not back in the demo.
    let app = launchIntoDemo()
    XCTAssertTrue(
      app.descendants(matching: .any).matching(identifier: "services.docker")
        .firstMatch.waitForExistence(timeout: 15)
    )

    app.buttons["toolbar.settings"].tap()
    // Waits for a row that is definitely on screen first, then scrolls: Settings
    // has System, Logs, and Appearance sections above Sign Out, so Sign Out is
    // below the fold — and a SwiftUI `List` doesn't render rows it hasn't
    // scrolled to, so `waitForExistence` on it times out rather than finding a
    // hidden element.
    XCTAssertTrue(
      app.staticTexts["Server"].waitForExistence(timeout: 10),
      "the settings sheet never appeared"
    )
    let signOut = app.buttons["settings.signOut"]
    scrollTo(signOut, in: app)
    XCTAssertTrue(signOut.waitForExistence(timeout: 10), "Sign Out never came into view")
    signOut.tap()
    // `.firstMatch`: the confirmation dialog surfaces more than one element
    // under this identifier. This test is about what the demo *stores*, and the
    // first match is the button.
    app.buttons["settings.confirmSignOut"].firstMatch.tap()

    XCTAssertTrue(
      app.buttons["connect.demo"].waitForExistence(timeout: 15),
      "signing out of the demo didn't return to the connect screen"
    )

    // Relaunch with no reset argument at all: if the demo had written a
    // credential, this would skip the connect screen.
    app.terminate()
    let relaunched = XCUIApplication()
    relaunched.launch()
    XCTAssertTrue(
      relaunched.buttons["connect.demo"].waitForExistence(timeout: 15),
      "the demo stored a credential — relaunching skipped the connect screen"
    )
  }

  // MARK: - Helpers

  private func waitForLabel(_ element: XCUIElement, toContain text: String, timeout: TimeInterval) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
      if element.exists, element.label.contains(text) { return true }
      _ = element.waitForExistence(timeout: 0.5)
    }
    return false
  }

  private func waitForLabel(_ element: XCUIElement, toNotEqual text: String, timeout: TimeInterval) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
      if element.exists, element.label != text { return true }
      _ = element.waitForExistence(timeout: 0.5)
    }
    return false
  }
}
