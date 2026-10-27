import XCTest

/// Instance management: disable, delete, edit, and reorder, from the hub
/// and from Settings → Services.
///
/// **Driven by swipe actions and buttons, never by a context menu.** A
/// `press(forDuration:)` on a row in this app costs about a minute, which is
/// more than the rest of this file put together. The context menus exist and
/// carry the same actions; they are just not what the tests reach for.
@MainActor
final class ServiceManagementUITests: XCTestCase {
  private enum Seed {
    static let radarr = "A0000000-0000-0000-0000-000000000001"
    static let sonarr = "A0000000-0000-0000-0000-000000000002"
    static let tautulli = "A0000000-0000-0000-0000-000000000004"
    static let prowlarr = "A0000000-0000-0000-0000-000000000005"
  }

  override func setUp() {
    super.setUp()
    continueAfterFailure = false
  }

  private func launchOnServices() -> XCUIApplication {
    let app = XCUIApplication()
    app.launchArguments = ["--uitest-seed-dashboard"]
    app.launch()
    app.buttons["Services"].firstMatch.tap()
    return app
  }

  private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
    app.descendants(matching: .any).matching(identifier: identifier).firstMatch
  }

  private func row(_ id: String, in app: XCUIApplication) -> XCUIElement {
    element("services.row.\(id)", in: app)
  }

  private func waitForNonExistence(of element: XCUIElement, timeout: TimeInterval = 10) -> Bool {
    let gone = XCTNSPredicateExpectation(
      predicate: NSPredicate(format: "exists == false"), object: element)
    return XCTWaiter().wait(for: [gone], timeout: timeout) == .completed
  }

  /// Reveals a row's swipe action and taps it — *if* the swipe parked rather
  /// than committing. A leading/trailing swipe that travels far enough runs the
  /// action itself (the iPad-column behaviour CLAUDE.md records), so requiring
  /// the button to appear would assert on column width rather than behaviour.
  private func swipeAction(
    _ suffix: String, on row: XCUIElement, edge: Edge, in app: XCUIApplication
  ) {
    switch edge {
    case .leading: row.swipeRight()
    case .trailing: row.swipeLeft()
    }
    let button = app.descendants(matching: .any)
      .matching(NSPredicate(format: "identifier ENDSWITH %@", suffix)).firstMatch
    if button.waitForExistence(timeout: 2) {
      button.tap()
    }
  }

  private enum Edge { case leading, trailing }

  // MARK: - Delete

  func testDeleteAsksFirstAndThenRemovesTheRow() {
    let app = launchOnServices()
    let radarr = row(Seed.radarr, in: app)
    XCTAssertTrue(radarr.waitForExistence(timeout: 10))

    swipeAction(".delete", on: radarr, edge: .trailing, in: app)

    // The dialog names the service, and the row survives until it is
    // confirmed — a delete that ran on the swipe would already be gone.
    XCTAssertTrue(app.staticTexts["Delete Radarr?"].waitForExistence(timeout: 5))
    XCTAssertTrue(radarr.exists, "the row must survive until the delete is confirmed")

    element("services.confirmDelete", in: app).tap()

    XCTAssertTrue(waitForNonExistence(of: radarr), "the deleted service is still listed")
    XCTAssertTrue(row(Seed.sonarr, in: app).exists, "the rest of the hub must be untouched")
  }

  // MARK: - Disable

  func testDisablingHidesAServiceAndReEnablingBringsItBack() {
    let app = launchOnServices()
    let radarr = row(Seed.radarr, in: app)
    XCTAssertTrue(radarr.waitForExistence(timeout: 10))

    swipeAction(".toggle", on: radarr, edge: .leading, in: app)

    XCTAssertTrue(waitForNonExistence(of: radarr), "a disabled service must leave the hub")

    // It is still configured — and Settings is where that can be seen, which is
    // the reason management lists disabled instances at all.
    element("toolbar.settings", in: app).tap()
    element("settings.manageServices", in: app).tap()
    let managed = element("manageServices.row.\(Seed.radarr)", in: app)
    XCTAssertTrue(managed.waitForExistence(timeout: 10), "the disabled service vanished entirely")
    XCTAssertTrue(managed.label.lowercased().contains("disabled"))

    swipeAction(".toggle", on: managed, edge: .leading, in: app)
    XCTAssertTrue(
      waitForLabel(managed, notContaining: "disabled"),
      "the service is still marked disabled after being enabled")
  }

  // MARK: - Edit

  func testEditingRenamesTheServiceInPlace() {
    // Driven from Tautulli's configuration screen: a Radarr row
    // opens the *arr shell instead, and Edit lives on the configuration screen.
    let app = launchOnServices()
    let tautulli = row(Seed.tautulli, in: app)
    XCTAssertTrue(tautulli.waitForExistence(timeout: 10))
    let rowsBefore = rowCount(in: app)

    tautulli.tap()
    element("services.detail.edit", in: app).tap()

    let name = element("addService.name", in: app)
    XCTAssertTrue(name.waitForExistence(timeout: 10))
    // The same sheet adds and edits; an edit must not say it is adding.
    XCTAssertTrue(
      app.navigationBars["Edit Service"].waitForExistence(timeout: 5),
      "the edit sheet is not titled Edit Service")
    replaceText(in: name, with: "Tautulli Main")
    element("addService.save", in: app).tap()

    // Back on the detail screen, under the new name.
    XCTAssertTrue(app.navigationBars["Tautulli Main"].waitForExistence(timeout: 10))

    // Back to the hub. On iPad the hub is already beside the detail, and the
    // detail column's root has no Back button.
    if !tautulli.isHittable { tapBack(in: app) }

    // Same row identifier and the same number of rows — an edit that added a
    // second record would leave the old row in place and put a new one beside it.
    XCTAssertTrue(tautulli.waitForExistence(timeout: 10))
    XCTAssertTrue(tautulli.label.contains("Tautulli Main"))
    XCTAssertEqual(rowCount(in: app), rowsBefore, "editing must not add a second instance")
  }

  // MARK: - Settings → Services

  func testSettingsListsEveryInstanceIncludingDisabledOnes() {
    let app = launchOnServices()
    XCTAssertTrue(row(Seed.radarr, in: app).waitForExistence(timeout: 10))

    element("toolbar.settings", in: app).tap()
    element("settings.manageServices", in: app).tap()

    for id in [Seed.radarr, Seed.sonarr, Seed.prowlarr] {
      XCTAssertTrue(
        element("manageServices.row.\(id)", in: app).waitForExistence(timeout: 10),
        "manageServices.row.\(id) is missing")
    }
  }

  func testDeleteIsAvailableFromSettingsToo() {
    let app = launchOnServices()
    XCTAssertTrue(row(Seed.radarr, in: app).waitForExistence(timeout: 10))
    element("toolbar.settings", in: app).tap()
    element("settings.manageServices", in: app).tap()

    let managed = element("manageServices.row.\(Seed.prowlarr)", in: app)
    XCTAssertTrue(managed.waitForExistence(timeout: 10))

    swipeAction(".delete", on: managed, edge: .trailing, in: app)
    XCTAssertTrue(app.staticTexts["Delete Prowlarr?"].waitForExistence(timeout: 5))
    element("manageServices.confirmDelete", in: app).tap()

    XCTAssertTrue(waitForNonExistence(of: managed))
  }

  /// Rows carry their identifier on more than one node, so this counts distinct
  /// matches only as a *relative* figure — compared before and after an edit,
  /// never asserted as an absolute.
  private func rowCount(in app: XCUIApplication) -> Int {
    app.descendants(matching: .any)
      .matching(NSPredicate(format: "identifier BEGINSWITH 'services.row.'")).count
  }

  private func waitForLabel(
    _ element: XCUIElement, notContaining text: String, timeout: TimeInterval = 10
  ) -> Bool {
    let predicate = NSPredicate(format: "NOT (label CONTAINS[c] %@)", text)
    let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
    return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
  }
}
