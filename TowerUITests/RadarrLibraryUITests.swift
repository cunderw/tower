import XCTest

/// The Radarr library and movie detail, against a 60-movie seeded
/// library — search, sort, and filters only mean something on a list that
/// doesn't fit on one screen.
@MainActor
final class RadarrLibraryUITests: XCTestCase {
  private let radarr = "A0000000-0000-0000-0000-000000000001"

  override func setUp() {
    super.setUp()
    continueAfterFailure = false
  }

  private func launchOnRadarr(state: String? = nil) -> XCUIApplication {
    let app = XCUIApplication()
    app.launchArguments = ["--uitest-seed-dashboard"]
    if let state { app.launchEnvironment["UITEST_RADARR_STATE"] = state }
    app.launch()
    app.buttons["Services"].firstMatch.tap()
    let row = app.descendants(matching: .any)
      .matching(identifier: "services.row.\(radarr)").firstMatch
    XCTAssertTrue(row.waitForExistence(timeout: 10))
    row.tap()
    XCTAssertTrue(movieRow(10, in: app).waitForExistence(timeout: 15), "the library never loaded")
    return app
  }

  private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
    app.descendants(matching: .any).matching(identifier: identifier).firstMatch
  }

  private func movieRow(_ id: Int, in app: XCUIApplication) -> XCUIElement {
    element("radarr.row.\(id)", in: app)
  }

  /// A `List` doesn't render what it hasn't scrolled to, so a row below the
  /// fold is genuinely absent from the tree — the trap `scrollTo` exists for.
  /// With 60 movies, most of this library is below the fold.
  @discardableResult
  private func reveal(_ element: XCUIElement, in app: XCUIApplication) -> Bool {
    scrollTo(element, in: app, attempts: 12)
  }

  private func waitForNonExistence(of element: XCUIElement, timeout: TimeInterval = 10) -> Bool {
    let gone = XCTNSPredicateExpectation(
      predicate: NSPredicate(format: "exists == false"), object: element)
    return XCTWaiter().wait(for: [gone], timeout: timeout) == .completed
  }

  /// Tapping a `Toggle` row does nothing — only the switch at its trailing edge
  /// responds (CLAUDE.md, "Tapping a SwiftUI `Toggle` row does nothing").
  private func flip(_ identifier: String, in app: XCUIApplication) {
    let row = app.switches[identifier].firstMatch
    XCTAssertTrue(row.waitForExistence(timeout: 10), "no \(identifier) toggle")
    let inner = row.switches.firstMatch
    if inner.exists {
      inner.tap()
    } else {
      row.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
    }
  }

  /// Opens the Sort and Filter menu and picks an option by its label.
  private func chooseOption(_ label: String, in app: XCUIApplication) {
    element("radarr.library.options", in: app).tap()
    let option = app.buttons[label].firstMatch
    XCTAssertTrue(option.waitForExistence(timeout: 5), "no \(label) option in the menu")
    option.tap()
  }

  // MARK: - The list

  func testTheLibraryRendersItsRowsWithTheirAvailabilityStates() {
    let app = launchOnRadarr()

    // The three states, each on a row that is in that state.
    XCTAssertTrue(movieRow(10, in: app).label.contains("Downloaded"))
    XCTAssertTrue(reveal(movieRow(11, in: app), in: app), "Missing Film never came into view")
    XCTAssertTrue(movieRow(11, in: app).label.contains("Missing"))
    XCTAssertTrue(reveal(movieRow(12, in: app), in: app))
    XCTAssertTrue(movieRow(12, in: app).label.contains("Unreleased"))
    // And unmonitored is spoken, not just dimmed.
    XCTAssertTrue(movieRow(12, in: app).label.contains("Unmonitored"))
  }

  // MARK: - Search

  func testSearchNarrowsTheLibrary() {
    let app = launchOnRadarr()
    let searchField = app.searchFields.firstMatch
    XCTAssertTrue(searchField.waitForExistence(timeout: 5))

    type("Missing Film", into: searchField)

    XCTAssertTrue(movieRow(11, in: app).waitForExistence(timeout: 5))
    XCTAssertTrue(
      waitForNonExistence(of: movieRow(10, in: app)),
      "a non-matching row survived the search")
  }

  // MARK: - Filters

  func testTheMissingFilterExcludesDownloadedAndUnreleasedFilms() {
    let app = launchOnRadarr()

    chooseOption("Missing", in: app)

    // Still 28 filler films ahead of it alphabetically, so it needs revealing
    // even after the filter.
    XCTAssertTrue(reveal(movieRow(11, in: app), in: app))
    XCTAssertTrue(waitForNonExistence(of: movieRow(10, in: app)), "a downloaded film is not missing")
    XCTAssertFalse(movieRow(12, in: app).exists, "an unreleased film is not missing")
  }

  func testTheDownloadedFilterKeepsOnlyFilmsOnDisk() {
    let app = launchOnRadarr()

    chooseOption("Downloaded", in: app)

    XCTAssertTrue(movieRow(10, in: app).waitForExistence(timeout: 5))
    XCTAssertTrue(waitForNonExistence(of: movieRow(11, in: app)))
  }

  // MARK: - Sort

  func testSortingBySizePutsTheBiggestFilmFirst() {
    // "Zulu Voyage" is both the largest film and the last alphabetically. Sorted
    // by title it is 60 rows down and therefore not in the tree at all; sorted
    // by size it must be on the first screen. That difference is the assertion
    // — and it needs no guess about which element is "row zero".
    let app = launchOnRadarr()
    XCTAssertFalse(
      movieRow(13, in: app).exists, "the largest film was already on screen before sorting")

    chooseOption("Size", in: app)

    XCTAssertTrue(
      movieRow(13, in: app).waitForExistence(timeout: 5),
      "sorting by size did not reorder the library")
  }

  // MARK: - Detail

  func testOpeningAMovieShowsItsFileInformation() {
    let app = launchOnRadarr()
    movieRow(10, in: app).tap()

    XCTAssertTrue(element("radarr.detail", in: app).waitForExistence(timeout: 10))
    // `LabeledContent` rows merge into one label ("Quality, WEBDL-1080p") and
    // inherit the section's identifier, so the assertion is on the text rather
    // than on an identifier of its own — taken from a real accessibility dump.
    let quality = app.staticTexts
      .containing(NSPredicate(format: "label CONTAINS 'WEBDL-1080p'")).firstMatch
    XCTAssertTrue(reveal(quality, in: app), "no quality in the file section")
  }

  func testAMissingFilmSaysSoInsteadOfShowingAnEmptyFileSection() {
    let app = launchOnRadarr()
    XCTAssertTrue(reveal(movieRow(11, in: app), in: app))
    movieRow(11, in: app).tap()

    XCTAssertTrue(reveal(element("radarr.detail.noFile", in: app), in: app))
    XCTAssertFalse(element("radarr.detail.file", in: app).exists)
  }

  // MARK: - Delete

  func testDeletingAsksFirstAndOffersBothOutcomes() {
    let app = launchOnRadarr()
    movieRow(10, in: app).tap()
    XCTAssertTrue(element("radarr.detail", in: app).waitForExistence(timeout: 10))

    XCTAssertTrue(reveal(element("radarr.detail.delete", in: app), in: app))
    element("radarr.detail.delete", in: app).tap()

    // Two destructive choices, not one hidden behind a toggle: removing from
    // Radarr and deleting the file are different decisions.
    XCTAssertTrue(app.staticTexts["Delete Downloaded Film?"].waitForExistence(timeout: 5))
    XCTAssertTrue(element("radarr.detail.confirmDelete", in: app).exists)
    XCTAssertTrue(element("radarr.detail.confirmDeleteFiles", in: app).exists)

    element("radarr.detail.confirmDelete", in: app).tap()

    // Back on the library, with the row gone.
    XCTAssertTrue(
      waitForNonExistence(of: movieRow(10, in: app)), "the deleted film is still listed")
    // A row that is on screen without scrolling — "Filler Film 00" sorts near
    // the top, unlike the missing/unreleased fixtures further down.
    XCTAssertTrue(movieRow(100, in: app).exists, "the rest of the library was disturbed")
  }

  func testAFailedActionKeepsTheLibraryOnScreen() {
    // `UITEST_RADARR_STATE=action-fails` makes every mutation fail. The library
    // must survive it — losing the list to a failed delete is the outcome the
    // `.actionFailed` rule exists to prevent.
    let app = launchOnRadarr(state: "action-fails")
    movieRow(10, in: app).tap()
    XCTAssertTrue(element("radarr.detail", in: app).waitForExistence(timeout: 10))

    XCTAssertTrue(reveal(element("radarr.detail.delete", in: app), in: app))
    element("radarr.detail.delete", in: app).tap()
    element("radarr.detail.confirmDelete", in: app).tap()

    // Still on the detail screen (the delete didn't happen), and the library
    // behind it is intact with an error banner.
    XCTAssertTrue(element("radarr.detail", in: app).waitForExistence(timeout: 10))
    tapBack(in: app)
    XCTAssertTrue(movieRow(10, in: app).waitForExistence(timeout: 10), "the library was lost")
    XCTAssertTrue(
      element("radarr.library.refreshError", in: app).waitForExistence(timeout: 5),
      "the failure was swallowed")
  }

  func testAFailedToggleSaysSoOnTheDetailScreen() throws {
    // The library's error row is behind the detail screen, out of sight, so a
    // failure reported only there is one the user never sees.
    let app = launchOnRadarr(state: "action-fails")
    movieRow(10, in: app).tap()
    XCTAssertTrue(element("radarr.detail", in: app).waitForExistence(timeout: 10))
    XCTAssertFalse(element("radarr.detail.actionError", in: app).exists)

    flip("radarr.detail.monitored", in: app)

    XCTAssertTrue(
      element("radarr.detail.actionError", in: app).waitForExistence(timeout: 10),
      "the failed toggle was silent on the detail screen")
    try saveScreenshot(named: "radarr-detail-action-error")
  }
}
