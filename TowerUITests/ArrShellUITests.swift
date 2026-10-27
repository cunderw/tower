import XCTest

/// The shared *arr shell: opening an instance from the hub lands in its
/// own shell, with its own data, and sections that don't fetch until visited.
@MainActor
final class ArrShellUITests: XCTestCase {
  private enum Seed {
    static let radarr = "A0000000-0000-0000-0000-000000000001"
    static let sonarr = "A0000000-0000-0000-0000-000000000002"
    static let tautulli = "A0000000-0000-0000-0000-000000000004"
    static let radarr4K = "A0000000-0000-0000-0000-000000000006"
  }

  override func setUp() {
    super.setUp()
    continueAfterFailure = false
  }

  private func launchOnServices() -> XCUIApplication {
    let app = XCUIApplication()
    app.launchArguments = ["--uitest-seed-dashboard"]
    app.launch()
    // Back to the tab bar first: with the iPad sidebar showing — which an
    // earlier class, or an earlier *run*, may have left behind — "Services"
    // matches the collapsible section header as well as the tab, and tapping
    // the header collapses the very rows this class then looks for.
    useTabBarLayout(in: app)
    app.buttons["Services"].firstMatch.tap()
    return app
  }

  private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
    app.descendants(matching: .any).matching(identifier: identifier).firstMatch
  }

  /// Any hub row that is currently on screen, to scroll the column it lives in.
  private func visibleHubRow(in app: XCUIApplication) -> XCUIElement? {
    app.descendants(matching: .any)
      .matching(NSPredicate(format: "identifier BEGINSWITH 'services.row.'"))
      .allElementsBoundByIndex
      .first { $0.isHittable }
  }

  /// Gets back to somewhere a hub row can be tapped.
  ///
  /// **Never `navigationBars.buttons.firstMatch`.** That is the back button on
  /// an iPhone and a toolbar button on an iPad, where the shell is the split
  /// view's detail root and has no back button to the hub — so a "go back"
  /// tap opens a modal, and every assertion after it fails on elements the
  /// sheet is covering.
  /// In split view the hub is still on screen in the leading column, so there
  /// is nothing to do.
  private func returnToHub(in app: XCUIApplication) {
    if visibleHubRow(in: app) != nil { return }
    let back = app.navigationBars.buttons.matching(
      NSPredicate(format: "identifier == 'BackButton' OR label == 'Services' OR label == 'Back'")
    ).firstMatch
    XCTAssertTrue(back.waitForExistence(timeout: 5), "no way back to the services hub")
    back.tap()
  }

  private func openInstance(_ id: String, in app: XCUIApplication) {
    let row = element("services.row.\(id)", in: app)
    XCTAssertTrue(row.waitForExistence(timeout: 10), "services.row.\(id) never appeared")
    // Hittable, not merely existing: the hub's list is longer than the iPad
    // split view's narrow list column, and a row the list has scrolled past
    // stays in the tree — tapping it then lands on empty space and the test
    // walks on believing it navigated.
    // Scrolled *within the hub's own column*: on iPad the split view puts the
    // list in the narrow leading column, and a swipe aimed at the middle of
    // the screen moves the detail pane instead. Whichever hub row is already
    // on screen is the anchor — it is by definition inside the right column,
    // whether that column is the sidebar or a full-width list.
    XCTAssertTrue(
      scrollUntilHittable(row, in: app, within: visibleHubRow(in: app), attempts: 10),
      "services.row.\(id) was in the tree but never on screen")
    row.tap()
  }

  // MARK: - Landing in the shell

  func testOpeningARadarrLandsInTheShellWithThatInstancesLibrary() {
    let app = launchOnServices()
    openInstance(Seed.radarr, in: app)

    XCTAssertTrue(element("arr.shell", in: app).waitForExistence(timeout: 10))
    XCTAssertTrue(app.navigationBars["Radarr"].waitForExistence(timeout: 5))
    XCTAssertTrue(element("radarr.row.10", in: app).waitForExistence(timeout: 10))
    // A second row that is also on the first screen — the seeded library is 60
    // movies, and most of it is below the fold.
    XCTAssertTrue(element("radarr.row.100", in: app).exists)
  }

  func testOpeningASonarrLandsInItsOwnShell() {
    let app = launchOnServices()
    openInstance(Seed.sonarr, in: app)

    XCTAssertTrue(element("arr.shell", in: app).waitForExistence(timeout: 10))
    XCTAssertTrue(element("sonarr.row.1", in: app).waitForExistence(timeout: 10))
    // Sonarr's rows, not Radarr's — one shell, two libraries.
    XCTAssertFalse(element("radarr.row.10", in: app).exists)
  }

  func testAKindWithNoClientStillOpensItsConfigurationScreen() {
    // The UI-test factory returns `nil` for Tautulli, so this exercises the
    // fallback configuration screen, which must stay a real screen rather than
    // a dead end. A fake Tautulli repository in that factory would break this
    // test, `ServicesHubUITests` and `ServiceManagementUITests`.
    let app = launchOnServices()
    openInstance(Seed.tautulli, in: app)

    XCTAssertTrue(element("services.detail", in: app).waitForExistence(timeout: 10))
    XCTAssertFalse(element("arr.shell", in: app).exists)
  }

  // MARK: - Independent instances

  func testTwoRadarrsHoldIndependentLibraries() {
    // The seeded 4K instance has a different library on purpose: with identical
    // data, a shell that shared one store would look exactly right.
    let app = launchOnServices()
    openInstance(Seed.radarr, in: app)
    XCTAssertTrue(element("radarr.row.10", in: app).waitForExistence(timeout: 10))

    returnToHub(in: app)
    openInstance(Seed.radarr4K, in: app)

    XCTAssertTrue(element("radarr.row.1", in: app).waitForExistence(timeout: 10))
    XCTAssertTrue(app.navigationBars["Radarr 4K"].exists)
    XCTAssertFalse(
      element("radarr.row.10", in: app).exists,
      "the second instance is showing the first instance's library")
  }

  // MARK: - Sections

  func testEverySectionIsReachableAndTheLibraryIsTheDefault() {
    let app = launchOnServices()
    openInstance(Seed.radarr, in: app)
    XCTAssertTrue(element("arr.shell", in: app).waitForExistence(timeout: 10))

    // Library first, with no other section's content on screen.
    XCTAssertTrue(element("radarr.row.10", in: app).waitForExistence(timeout: 10))
    XCTAssertFalse(element("arr.section.queue.placeholder", in: app).exists)

    // Every section is a real screen — there are no placeholders left in the
    // shell.
    app.buttons["Queue"].firstMatch.tap()
    XCTAssertTrue(
      element("queue.row.41", in: app).waitForExistence(timeout: 15),
      "the Queue section never loaded")

    app.buttons["Calendar"].firstMatch.tap()
    XCTAssertTrue(
      element("calendar.entry.10", in: app).waitForExistence(timeout: 15),
      "the Calendar section never loaded")

    app.buttons["History"].firstMatch.tap()
    XCTAssertTrue(
      element("history.record.9001", in: app).waitForExistence(timeout: 15),
      "the History section never loaded")

    app.buttons["More"].firstMatch.tap()
    XCTAssertTrue(
      element("more", in: app).waitForExistence(timeout: 15),
      "the More section never loaded")

    app.buttons["Library"].firstMatch.tap()
    XCTAssertTrue(element("radarr.row.10", in: app).waitForExistence(timeout: 5))
  }

  func testAnUnvisitedSectionIsNeverBuilt() {
    // Lazy sections are the reason opening a Radarr doesn't fire five requests
    // at a service that may be behind a VPN. The observable proof is that no
    // other section's content exists until it is selected.
    let app = launchOnServices()
    openInstance(Seed.radarr, in: app)
    XCTAssertTrue(element("radarr.row.10", in: app).waitForExistence(timeout: 10))

    XCTAssertFalse(
      element("queue.row.41", in: app).exists,
      "the Queue section fetched without being visited")
    XCTAssertFalse(
      element("calendar.entry.10", in: app).exists,
      "the Calendar section fetched without being visited")
    XCTAssertFalse(
      element("history.record.9001", in: app).exists,
      "the History section fetched without being visited")
    XCTAssertFalse(
      element("more", in: app).exists,
      "the More section fetched without being visited")
  }
}
