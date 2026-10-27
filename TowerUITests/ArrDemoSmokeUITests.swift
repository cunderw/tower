import XCTest

/// The *arr smoke paths, driven through **demo mode** rather than the DEBUG
/// seeded fake.
///
/// Every other `*arr` class here launches with `--uitest-seed-dashboard`, which
/// swaps in `UITestSupport`'s repositories. That is the right tool for asserting
/// on a screen's behaviour — it can be seeded into any state, including failing
/// ones — but it proves nothing about the path an App Store reviewer takes. This
/// class launches cold, taps Demo on the connect screen, and walks the whole
/// way down on the demo repositories.
///
/// So these are deliberately *paths*, not per-screen assertions: library →
/// detail → interactive search → grab → queue for Radarr, and series → season →
/// episode → search for Sonarr. What they catch is the class of break that the
/// seeded suite structurally cannot — a demo repository that returns nothing, a
/// service that never gets wired into `AppEnvironment.demo`, a mutation that
/// doesn't reach the screen the user is looking at.
///
/// Runs on iPad too, so tab taps use `.firstMatch` throughout: with
/// `.sidebarAdaptable` the tabs render twice there and a bare
/// `app.buttons["Services"]` is ambiguous
/// (CLAUDE.md, "With the sidebar showing, two elements are labelled "Services"").
@MainActor
final class ArrDemoSmokeUITests: XCTestCase {
  /// `DemoServices` numbers instances by `idSuffix`'s name list, so Radarr is
  /// 01 and Sonarr — behind the second Radarr — is 03.
  private let radarr = "D0000000-0000-0000-0000-000000000001"
  private let sonarr = "D0000000-0000-0000-0000-000000000003"

  override func setUp() {
    super.setUp()
    continueAfterFailure = false
  }

  // MARK: - Navigation

  private func launchIntoDemo() -> XCUIApplication {
    let app = XCUIApplication()
    // No `--uitest-seed-dashboard`: the point of this class is the shipping path.
    app.launchArguments = ["--uitest-reset-credentials"]
    app.launch()

    let demo = app.buttons["connect.demo"]
    XCTAssertTrue(demo.waitForExistence(timeout: 15), "the connect screen offered no demo")
    demo.tap()
    return app
  }

  private func openService(_ id: String, in app: XCUIApplication) {
    // Back to the tab bar first: with the iPad sidebar showing, "Services"
    // matches the collapsible section header as well as the tab, and tapping
    // the header collapses the rows this then looks for.
    useTabBarLayout(in: app)
    app.buttons["Services"].firstMatch.tap()
    let row = app.descendants(matching: .any).matching(identifier: "services.row.\(id)").firstMatch
    XCTAssertTrue(scrollTo(row, in: app), "the demo hub never offered \(id)")
    row.tap()
    XCTAssertTrue(
      element("arr.shell", in: app).waitForExistence(timeout: 15), "no *arr shell for \(id)")
  }

  private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
    app.descendants(matching: .any).matching(identifier: identifier).firstMatch
  }

  @discardableResult
  private func reveal(_ element: XCUIElement, in app: XCUIApplication) -> Bool {
    scrollTo(element, in: app, attempts: 12)
  }

  /// Walks back up to the shell's section picker.
  ///
  /// Search is two pushes deep from the library (detail, then search), so a
  /// single back tap lands on the movie detail and the section picker isn't
  /// there yet. Popping in a
  /// loop rather than tapping back a counted number of times keeps it honest on
  /// iPad, where the split view starts the stack at a different depth.
  ///
  /// **Finds its way out by identity, never by index.** The search sheet's
  /// sort control is a `Menu`, which surfaces as a button in the navigation
  /// bar, so `navigationBars.buttons.element(boundBy: 0)` resolves to *Sort*
  /// and a loop on it reopens that menu until the attempts run out. On iPad
  /// index 0 is the Services column's *Add Service* button, which comes before
  /// the detail column's back button.
  private func popToShell(in app: XCUIApplication, attempts: Int = 4) -> Bool {
    for _ in 0..<attempts {
      if app.buttons["Queue"].firstMatch.exists { return true }
      // The search sheet owns a named Done button.
      let done = app.buttons["search.done"].firstMatch
      if done.exists, done.isHittable {
        done.tap()
        continue
      }
      // Otherwise a navigation stack: match the back button by identifier, or by
      // its `Back` label where the identifier is missing.
      let back = app.navigationBars.buttons.matching(
        NSPredicate(format: "identifier == 'BackButton' OR label == 'Back'")
      ).firstMatch
      guard back.exists, back.isHittable else { break }
      back.tap()
    }
    return app.buttons["Queue"].firstMatch.waitForExistence(timeout: 5)
  }

  /// Waits for a control to become enabled — SwiftUI enables Add on the render
  /// after the pickers answer, not synchronously with the tap.
  private func waitUntilEnabled(_ element: XCUIElement, timeout: TimeInterval = 15) -> Bool {
    let enabled = XCTNSPredicateExpectation(
      predicate: NSPredicate(format: "isEnabled == true"), object: element)
    return XCTWaiter().wait(for: [enabled], timeout: timeout) == .completed
  }

  // MARK: - Radarr: library → detail → interactive search → grab → queue

  func testRadarrDemoPathRunsFromTheLibraryToAGrabThatReachesTheQueue() {
    let app = launchIntoDemo()
    openService(radarr, in: app)

    // Wait for the library itself before searching it — the demo's seeded
    // latency means the search field is live before there is anything to filter.
    let anyRow = app.descendants(matching: .any)
      .matching(NSPredicate(format: "identifier BEGINSWITH 'radarr.row.'")).firstMatch
    XCTAssertTrue(anyRow.waitForExistence(timeout: 20), "the demo library never loaded")

    // "Winter Ledger" is the demo's missing film — the one with something worth
    // searching for, and so the row a reviewer is meant to tap. The library
    // sorts alphabetically and there are 54 films, so it is reached by narrowing
    // rather than by scrolling; that the search box works is worth a smoke
    // assertion of its own anyway.
    let field = searchField(prompt: "Search movies", in: app)
    XCTAssertTrue(field.waitForExistence(timeout: 10), "the demo library had no search field")
    type("Winter Ledger", into: field)

    let missing = element("radarr.row.3", in: app)
    XCTAssertTrue(missing.waitForExistence(timeout: 15), "search never found the missing film")
    XCTAssertTrue(missing.label.contains("Winter Ledger"), "got \(missing.label)")
    XCTAssertTrue(missing.label.contains("Missing"), "got \(missing.label)")
    missing.tap()

    XCTAssertTrue(element("radarr.detail", in: app).waitForExistence(timeout: 15))
    let search = element("radarr.detail.interactiveSearch", in: app)
    XCTAssertTrue(reveal(search, in: app), "no interactive search on the demo's movie detail")
    search.tap()

    let approved = element("search.release.demo-release-1", in: app)
    XCTAssertTrue(approved.waitForExistence(timeout: 20), "the demo search returned nothing")
    // The release is named after the film that was searched for. A movie search
    // answering with a TV release title is the fixture showing through, and the
    // grab dialog quotes this string back at the reviewer.
    XCTAssertTrue(approved.label.contains("Winter Ledger"), "got \(approved.label)")

    approved.tap()
    let confirm = element("search.confirmGrab", in: app)
    XCTAssertTrue(confirm.waitForExistence(timeout: 10), "grabbing didn't ask first")
    confirm.tap()
    XCTAssertFalse(
      element("search.grabError", in: app).waitForExistence(timeout: 3),
      "the demo refused its own grab")

    // The payoff, and the reason this is one test rather than three: the grab
    // has to show up somewhere the user can see it. Back out to the shell and
    // open the Queue.
    XCTAssertTrue(popToShell(in: app), "never got back to the *arr shell after grabbing")
    app.buttons["Queue"].firstMatch.tap()

    let queued = app.descendants(matching: .any)
      .matching(NSPredicate(format: "identifier BEGINSWITH 'queue.row.'"))
      .containing(NSPredicate(format: "label CONTAINS 'Winter Ledger'"))
      .firstMatch
    XCTAssertTrue(queued.waitForExistence(timeout: 20), "the grabbed release never reached the queue")
  }

  // MARK: - Sonarr: series → season → episode → search

  func testSonarrDemoPathRunsFromTheSeriesDownToAnEpisodeSearch() {
    let app = launchIntoDemo()
    openService(sonarr, in: app)

    let series = element("sonarr.row.1", in: app)
    XCTAssertTrue(series.waitForExistence(timeout: 20), "the demo series library never loaded")
    XCTAssertTrue(series.label.contains("Northern Lights"), "got \(series.label)")
    series.tap()

    XCTAssertTrue(element("sonarr.detail", in: app).waitForExistence(timeout: 15))
    // Season 2 is the one holding the missing episode; season 1 is complete.
    let season = element("sonarr.season.2", in: app)
    XCTAssertTrue(reveal(season, in: app), "season 2 never appeared")
    season.tap()
    XCTAssertTrue(element("sonarr.season", in: app).waitForExistence(timeout: 15))

    let missing = element("sonarr.episode.2011", in: app)
    XCTAssertTrue(reveal(missing, in: app), "the missing episode never appeared")
    XCTAssertTrue(missing.label.contains("Missing"), "got \(missing.label)")
    missing.tap()

    XCTAssertTrue(element("sonarr.episode.detail", in: app).waitForExistence(timeout: 15))
    let search = element("sonarr.episode.interactiveSearch", in: app)
    XCTAssertTrue(reveal(search, in: app), "no interactive search on the demo's episode detail")
    search.tap()

    let approved = element("search.release.demo-release-1", in: app)
    XCTAssertTrue(approved.waitForExistence(timeout: 20), "the demo episode search returned nothing")
    XCTAssertTrue(approved.label.contains("Northern Lights S02E11"), "got \(approved.label)")
    // Both sides of the list: one grabbable, one rejected with the service's own
    // reason, which is what tells a user whether overriding is reasonable.
    let rejected = element("search.release.demo-release-2", in: app)
    XCTAssertTrue(rejected.exists, "the demo offered no rejected release to contrast against")
    XCTAssertTrue(rejected.label.contains("below the profile's cutoff"), "got \(rejected.label)")
  }

  // MARK: - Add, in the demo

  func testAddingAMovieInTheDemoPutsItInTheDemoLibrary() {
    let app = launchIntoDemo()
    openService(radarr, in: app)
    let anyRow = app.descendants(matching: .any)
      .matching(NSPredicate(format: "identifier BEGINSWITH 'radarr.row.'")).firstMatch
    XCTAssertTrue(anyRow.waitForExistence(timeout: 20), "the library never loaded")

    element("radarr.library.add", in: app).tap()
    XCTAssertTrue(element("radarr.add.prompt", in: app).waitForExistence(timeout: 10))

    // The sheet's own field: the library behind it also has a search field, and
    // `searchFields.firstMatch` finds that one.
    let field = app.searchFields["Search by name"].firstMatch
    XCTAssertTrue(field.waitForExistence(timeout: 10))
    type("harbour", into: field)
    app.keyboards.buttons["Search"].firstMatch.tap()

    // "Harbour Lights" is the demo candidate not already in the library.
    let result = element("radarr.add.result.700000", in: app)
    XCTAssertTrue(result.waitForExistence(timeout: 20), "the demo lookup returned nothing")
    result.tap()

    let confirm = app.buttons["radarr.add.confirm"].firstMatch
    XCTAssertTrue(confirm.waitForExistence(timeout: 15))
    XCTAssertTrue(waitUntilEnabled(confirm), "Add never became available in the demo")
    confirm.tap()

    // Demo mutations are real, in memory — so the film has to actually be in the
    // library behind the sheet, not merely accepted by a sheet that dismissed.
    // Narrowed rather than scrolled to: the new film sorts into the middle of 55.
    let libraryField = searchField(prompt: "Search movies", in: app)
    XCTAssertTrue(libraryField.waitForExistence(timeout: 15), "never got back to the library")
    type("Harbour Lights", into: libraryField)

    let added = app.descendants(matching: .any)
      .matching(NSPredicate(format: "identifier BEGINSWITH 'radarr.row.'"))
      .containing(NSPredicate(format: "label CONTAINS 'Harbour Lights'")).firstMatch
    XCTAssertTrue(
      added.waitForExistence(timeout: 15), "the added film never reached the demo library")
  }
}
