import XCTest

/// The Radarr edit sheet and add flow, end to end against the seeded
/// fake — search, configure, add, and the pickers that must come from the
/// service rather than from a constant.
@MainActor
final class RadarrAddEditUITests: XCTestCase {
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
    XCTAssertTrue(
      element("radarr.row.10", in: app).waitForExistence(timeout: 15), "the library never loaded")
    return app
  }

  private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
    app.descendants(matching: .any).matching(identifier: identifier).firstMatch
  }

  @discardableResult
  private func reveal(_ element: XCUIElement, in app: XCUIApplication) -> Bool {
    scrollTo(element, in: app, attempts: 12)
  }

  /// The add sheet's field, addressed by its own prompt: the library behind the
  /// sheet also has a search field, and `app.searchFields.firstMatch` finds
  /// that one.
  private func addSearchField(in app: XCUIApplication) -> XCUIElement {
    app.searchFields["Search by name"].firstMatch
  }

  /// Flips a SwiftUI `Toggle` in a `Form`.
  ///
  /// **Tapping the identified element does nothing.** The identifier lands on
  /// the whole row (370pt wide), and only the switch at its trailing edge
  /// responds — confirmed from an accessibility dump where a tap on the row
  /// left `value` at 1. The inner switch carries no identifier of its own, so
  /// it is reached as a descendant.
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

  /// Waits for a control to become enabled. SwiftUI enables the Save button on
  /// the next render after the change, not synchronously with the tap.
  private func waitUntilEnabled(_ element: XCUIElement, timeout: TimeInterval = 5) -> Bool {
    let enabled = XCTNSPredicateExpectation(
      predicate: NSPredicate(format: "isEnabled == true"), object: element)
    return XCTWaiter().wait(for: [enabled], timeout: timeout) == .completed
  }

  // MARK: - Add

  func testAddingAMovieEndToEndPutsItInTheLibrary() {
    let app = launchOnRadarr()
    element("radarr.library.add", in: app).tap()

    XCTAssertTrue(element("radarr.add.prompt", in: app).waitForExistence(timeout: 5))
    let search = addSearchField(in: app)
    XCTAssertTrue(search.waitForExistence(timeout: 5))
    type("addable", into: search)
    app.keyboards.buttons["Search"].firstMatch.tap()

    let result = element("radarr.add.result.900100", in: app)
    XCTAssertTrue(result.waitForExistence(timeout: 10), "the lookup returned nothing")
    result.tap()

    // The pickers are populated from the service before Add is enabled.
    let confirm = app.buttons["radarr.add.confirm"].firstMatch
    XCTAssertTrue(confirm.waitForExistence(timeout: 10))
    // Enabled only once the pickers have answered — the defaults come from the
    // service, so there is nothing to add until they arrive.
    XCTAssertTrue(waitUntilEnabled(confirm, timeout: 10), "Add never became available")
    confirm.tap()

    // Back on the library, with the new film in it. The "(searching)" suffix is
    // the fake's way of showing that search-on-add reached the service — on a
    // real Radarr it is `addOptions.searchForMovie` in the POST body.
    let added = app.descendants(matching: .any)
      .matching(NSPredicate(format: "label CONTAINS 'Addable Film (searching)'")).firstMatch
    XCTAssertTrue(reveal(added, in: app), "the added film never appeared in the library")
  }

  func testAFilmAlreadyInTheLibraryIsMarkedAndNotOfferedAgain() {
    let app = launchOnRadarr()
    element("radarr.library.add", in: app).tap()
    let search = addSearchField(in: app)
    XCTAssertTrue(search.waitForExistence(timeout: 5))
    type("downloaded", into: search)
    app.keyboards.buttons["Search"].firstMatch.tap()

    let existing = element("radarr.add.result.10", in: app)
    XCTAssertTrue(existing.waitForExistence(timeout: 10))
    XCTAssertTrue(existing.label.contains("Already added"))

    existing.tap()
    // Nothing opens: adding it twice is an error Radarr would reject.
    XCTAssertFalse(app.buttons["radarr.add.confirm"].firstMatch.waitForExistence(timeout: 2))
  }

  func testTurningOffSearchOnAddChangesWhatIsSent() {
    // The mirror of the first test: with the toggle off, the added film has no
    // "(searching)" suffix, which is only possible if the flag travelled.
    let app = launchOnRadarr()
    element("radarr.library.add", in: app).tap()
    let search = addSearchField(in: app)
    XCTAssertTrue(search.waitForExistence(timeout: 5))
    type("addable", into: search)
    app.keyboards.buttons["Search"].firstMatch.tap()
    element("radarr.add.result.900100", in: app).tap()

    let toggle = app.switches["radarr.add.searchOnAdd"].firstMatch
    XCTAssertTrue(reveal(toggle, in: app))
    flip("radarr.add.searchOnAdd", in: app)
    let confirm = app.buttons["radarr.add.confirm"].firstMatch
    XCTAssertTrue(waitUntilEnabled(confirm))
    confirm.tap()

    let plain = app.descendants(matching: .any)
      .matching(NSPredicate(format: "label CONTAINS 'Addable Film'")).firstMatch
    XCTAssertTrue(reveal(plain, in: app))
    XCTAssertFalse(plain.label.contains("searching"), "search-on-add fired when it was off")
  }

  // MARK: - Edit

  func testEditingAMovieSavesThroughToTheLibraryRow() {
    let app = launchOnRadarr()
    element("radarr.row.10", in: app).tap()
    XCTAssertTrue(element("radarr.detail", in: app).waitForExistence(timeout: 10))

    element("radarr.detail.edit", in: app).tap()
    let monitored = app.switches["radarr.edit.monitored"].firstMatch
    XCTAssertTrue(monitored.waitForExistence(timeout: 10))
    XCTAssertEqual(monitored.value as? String, "1")
    flip("radarr.edit.monitored", in: app)

    let save = app.buttons["radarr.edit.save"].firstMatch
    XCTAssertTrue(waitUntilEnabled(save), "Save stayed disabled after a change")
    save.tap()

    // The detail's own toggle reflects it, without a refetch.
    let detailToggle = app.switches["radarr.detail.monitored"].firstMatch
    XCTAssertTrue(detailToggle.waitForExistence(timeout: 10))
    XCTAssertEqual(detailToggle.value as? String, "0")
  }

  func testSaveIsDisabledUntilSomethingChanges() {
    let app = launchOnRadarr()
    element("radarr.row.10", in: app).tap()
    XCTAssertTrue(element("radarr.detail", in: app).waitForExistence(timeout: 10))
    element("radarr.detail.edit", in: app).tap()

    let save = app.buttons["radarr.edit.save"].firstMatch
    XCTAssertTrue(save.waitForExistence(timeout: 10))
    XCTAssertFalse(save.isEnabled, "an unchanged edit offered to save anyway")
  }

  func testAFailedEditKeepsTheSheetOpenAndSaysWhy() {
    let app = launchOnRadarr(state: "action-fails")
    element("radarr.row.10", in: app).tap()
    XCTAssertTrue(element("radarr.detail", in: app).waitForExistence(timeout: 10))
    element("radarr.detail.edit", in: app).tap()

    flip("radarr.edit.monitored", in: app)
    let save = app.buttons["radarr.edit.save"].firstMatch
    XCTAssertTrue(waitUntilEnabled(save))
    save.tap()

    XCTAssertTrue(
      reveal(element("radarr.edit.saveError", in: app), in: app),
      "the failure was swallowed")
    // Still open, with the change still in it.
    XCTAssertTrue(app.switches["radarr.edit.monitored"].firstMatch.exists)
  }
}
