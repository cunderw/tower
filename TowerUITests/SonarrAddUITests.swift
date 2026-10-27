import XCTest

/// The Sonarr add-series flow.
@MainActor
final class SonarrAddUITests: XCTestCase {
  private let sonarr = "A0000000-0000-0000-0000-000000000002"

  override func setUp() {
    super.setUp()
    continueAfterFailure = false
  }

  private func launchOnSonarr(state: String? = nil) -> XCUIApplication {
    let app = XCUIApplication()
    app.launchArguments = ["--uitest-seed-dashboard"]
    if let state { app.launchEnvironment["UITEST_SONARR_STATE"] = state }
    app.launch()
    app.buttons["Services"].firstMatch.tap()
    let service = app.descendants(matching: .any)
      .matching(identifier: "services.row.\(sonarr)").firstMatch
    XCTAssertTrue(service.waitForExistence(timeout: 10))
    service.tap()
    XCTAssertTrue(element("sonarr.row.1", in: app).waitForExistence(timeout: 15))
    return app
  }

  private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
    app.descendants(matching: .any).matching(identifier: identifier).firstMatch
  }

  @discardableResult
  private func reveal(_ element: XCUIElement, in app: XCUIApplication) -> Bool {
    scrollTo(element, in: app, attempts: 12)
  }

  private func waitUntilEnabled(_ element: XCUIElement, timeout: TimeInterval = 10) -> Bool {
    let enabled = XCTNSPredicateExpectation(
      predicate: NSPredicate(format: "isEnabled == true"), object: element)
    return XCTWaiter().wait(for: [enabled], timeout: timeout) == .completed
  }

  /// Opens the add sheet and searches, leaving the results on screen.
  private func searchForAddable(in app: XCUIApplication) {
    element("sonarr.library.add", in: app).tap()
    let search = app.searchFields["Search by name"].firstMatch
    XCTAssertTrue(search.waitForExistence(timeout: 10))
    type("addable", into: search)
    app.keyboards.buttons["Search"].firstMatch.tap()
  }

  func testAddingASeriesEndToEndPutsItInTheLibrary() {
    let app = launchOnSonarr()
    searchForAddable(in: app)

    let result = element("sonarr.add.result.777100", in: app)
    XCTAssertTrue(result.waitForExistence(timeout: 15), "the lookup returned nothing")
    result.tap()

    let confirm = app.buttons["sonarr.add.confirm"].firstMatch
    XCTAssertTrue(confirm.waitForExistence(timeout: 10))
    XCTAssertTrue(waitUntilEnabled(confirm), "Add never became available")
    confirm.tap()

    // The "(searching)" suffix is the fake's stand-in for
    // `addOptions.searchForMissingEpisodes` reaching the service.
    let added = app.descendants(matching: .any)
      .matching(NSPredicate(format: "label CONTAINS 'Addable Series (searching)'")).firstMatch
    XCTAssertTrue(reveal(added, in: app), "the added series never appeared in the library")
  }

  func testTheConfigureSheetOffersSonarrsOwnMonitorVocabulary() {
    // `firstSeason`, `missing`, `pilot` and the rest mean specific things to
    // Sonarr; the picker has to offer them rather than a paraphrase.
    let app = launchOnSonarr()
    searchForAddable(in: app)
    element("sonarr.add.result.777100", in: app).tap()

    let monitor = element("sonarr.add.monitor", in: app)
    XCTAssertTrue(reveal(monitor, in: app))
    monitor.tap()

    for option in ["All episodes", "Future episodes", "Missing episodes", "Pilot only", "None"] {
      XCTAssertTrue(
        app.buttons[option].firstMatch.waitForExistence(timeout: 5),
        "the monitor picker is missing \(option)")
    }
  }

  func testSeriesTypeAndSeasonFoldersAreOffered() {
    let app = launchOnSonarr()
    searchForAddable(in: app)
    element("sonarr.add.result.777100", in: app).tap()

    let type = element("sonarr.add.seriesType", in: app)
    XCTAssertTrue(reveal(type, in: app))
    type.tap()
    for option in ["Standard", "Daily", "Anime"] {
      XCTAssertTrue(app.buttons[option].firstMatch.waitForExistence(timeout: 5))
    }
    app.buttons["Anime"].firstMatch.tap()

    XCTAssertTrue(reveal(app.switches["sonarr.add.seasonFolders"].firstMatch, in: app))
  }

  func testASeriesAlreadyInTheLibraryIsMarkedAndNotOfferedAgain() {
    let app = launchOnSonarr()
    element("sonarr.library.add", in: app).tap()
    let search = app.searchFields["Search by name"].firstMatch
    XCTAssertTrue(search.waitForExistence(timeout: 10))
    type("complete", into: search)
    app.keyboards.buttons["Search"].firstMatch.tap()

    let existing = element("sonarr.add.result.1", in: app)
    XCTAssertTrue(existing.waitForExistence(timeout: 15))
    XCTAssertTrue(existing.label.contains("Already added"))

    existing.tap()
    XCTAssertFalse(app.buttons["sonarr.add.confirm"].firstMatch.waitForExistence(timeout: 2))
  }

  func testAFailedAddKeepsTheSheetOpenAndSaysWhy() {
    let app = launchOnSonarr(state: "action-fails")
    searchForAddable(in: app)
    element("sonarr.add.result.777100", in: app).tap()

    let confirm = app.buttons["sonarr.add.confirm"].firstMatch
    XCTAssertTrue(confirm.waitForExistence(timeout: 10))
    XCTAssertTrue(waitUntilEnabled(confirm))
    confirm.tap()

    XCTAssertTrue(
      reveal(element("sonarr.add.saveError", in: app), in: app), "the failure was swallowed")
    // Still open, with the configuration intact.
    XCTAssertTrue(app.buttons["sonarr.add.confirm"].firstMatch.exists)
  }
}
