import XCTest

/// The shared interactive-search screen, driven from Radarr's movie
/// detail against the seeded fake's three releases.
@MainActor
final class InteractiveSearchUITests: XCTestCase {
  private let radarr = "A0000000-0000-0000-0000-000000000001"

  override func setUp() {
    super.setUp()
    continueAfterFailure = false
  }

  private func openSearch(state: String? = nil) -> XCUIApplication {
    let app = XCUIApplication()
    app.launchArguments = ["--uitest-seed-dashboard"]
    if let state { app.launchEnvironment["UITEST_RADARR_STATE"] = state }
    app.launch()
    app.buttons["Services"].firstMatch.tap()
    let service = app.descendants(matching: .any)
      .matching(identifier: "services.row.\(radarr)").firstMatch
    XCTAssertTrue(service.waitForExistence(timeout: 10))
    service.tap()
    let movie = element("radarr.row.10", in: app)
    XCTAssertTrue(movie.waitForExistence(timeout: 15))
    movie.tap()
    XCTAssertTrue(element("radarr.detail", in: app).waitForExistence(timeout: 10))
    let search = element("radarr.detail.interactiveSearch", in: app)
    XCTAssertTrue(scrollTo(search, in: app, attempts: 12), "no interactive search button")
    search.tap()
    return app
  }

  private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
    app.descendants(matching: .any).matching(identifier: identifier).firstMatch
  }

  private func release(_ id: String, in app: XCUIApplication) -> XCUIElement {
    element("search.release.\(id)", in: app)
  }

  /// Opens the toolbar's sort picker and chooses an option.
  ///
  /// **Three iPad differences in one four-line interaction.** The
  /// picker's identifier is on a toolbar `Picker`, whose tappable element is a
  /// button descendant there; the menu opens as a *popover*, which animates, so
  /// the option is absent for the first frames; and its options surface as
  /// `menuItems` rather than `buttons`. Tapping the picker and then
  /// immediately `buttons["Age"]` works on a phone and finds nothing at all on
  /// an iPad.
  private func chooseSort(_ option: String, in app: XCUIApplication) {
    let picker = app.buttons["search.sort"].firstMatch.exists
      ? app.buttons["search.sort"].firstMatch
      : element("search.sort", in: app)
    XCTAssertTrue(picker.waitForExistence(timeout: 10), "no sort control in the toolbar")
    picker.tap()

    // **Never re-tap the picker to retry.** A second tap on an open menu
    // closes it, which turns a menu that *was* open into a permanent timeout.
    let choice = sortOption(option, in: app)
    XCTAssertTrue(choice.waitForExistence(timeout: 10), "the sort menu never opened")
    choice.tap()
  }

  /// The menu's option, whatever element type this device wraps it in.
  ///
  /// Not `app.buttons[option]`: the iPhone menu renders its options as buttons
  /// and iPad's popover does not, so a button-only query finds nothing there
  /// while the menu is plainly open on screen.
  private func sortOption(_ option: String, in app: XCUIApplication) -> XCUIElement {
    app.descendants(matching: .any)
      .matching(NSPredicate(format: "label == %@", option))
      .element(boundBy: 0)
  }

  // MARK: - The list

  func testTheReleaseListShowsQualitySizeAndIndexer() {
    let app = openSearch()

    let approved = release("release-approved", in: app)
    XCTAssertTrue(approved.waitForExistence(timeout: 15), "the search never returned")
    let label = approved.label
    XCTAssertTrue(label.contains("WEBDL-2160p"), "no quality: \(label)")
    // `Formatters.bytes` renders this as "87.24 GB", and the assertion pins that
    // exact rendering.
    XCTAssertTrue(label.contains("87.24 GB"), "no size: \(label)")
    XCTAssertTrue(label.contains("Example Indexer"), "no indexer: \(label)")
  }

  func testARejectedReleaseShowsTheServicesOwnReason() {
    // Verbatim, because the *arr explains its own rejection better than any
    // rewording here could — and it is what tells the user whether to override.
    let app = openSearch()
    let rejected = release("release-rejected", in: app)
    XCTAssertTrue(rejected.waitForExistence(timeout: 15))

    XCTAssertTrue(
      rejected.label.contains("already downloaded"),
      "the rejection reason never reached the row: \(rejected.label)")
  }

  func testApprovedReleasesLeadTheListByDefault() {
    // The service lists the rejected release first, so it would lead under any
    // ordering that kept the service's own.
    let app = openSearch()
    XCTAssertTrue(release("release-approved", in: app).waitForExistence(timeout: 15))

    let approvedY = release("release-approved", in: app).frame.origin.y
    let rejectedY = release("release-rejected", in: app).frame.origin.y
    XCTAssertLessThan(approvedY, rejectedY, "a rejected release led the list")
  }

  func testSortingByAgeReordersTheList() {
    let app = openSearch()
    XCTAssertTrue(release("release-approved", in: app).waitForExistence(timeout: 15))
    XCTAssertLessThan(
      release("release-approved", in: app).frame.origin.y,
      release("release-rejected", in: app).frame.origin.y)

    chooseSort("Age", in: app)

    // Twelve hours old beats four days, whatever the *arr thinks of it.
    XCTAssertTrue(
      waitForOrder(
        first: release("release-rejected", in: app),
        second: release("release-approved", in: app)),
      "sorting by age did not reorder the list")
  }

  // MARK: - Grabbing

  func testGrabbingAsksFirst() {
    let app = openSearch()
    let approved = release("release-approved", in: app)
    XCTAssertTrue(approved.waitForExistence(timeout: 15))

    approved.tap()

    XCTAssertTrue(
      app.staticTexts["Grab Example Film (2024) 2160p?"]
        .waitForExistence(timeout: 5))
    element("search.confirmGrab", in: app).tap()

    // The list is unchanged — a grab is a request to the download client, not
    // an edit to the search results.
    XCTAssertTrue(release("release-approved", in: app).waitForExistence(timeout: 10))
    XCTAssertFalse(element("search.grabError", in: app).exists)
  }

  func testAConfirmationForARejectedReleaseShowsWhatIsBeingOverridden() {
    let app = openSearch()
    let rejected = release("release-rejected", in: app)
    XCTAssertTrue(rejected.waitForExistence(timeout: 15))

    rejected.tap()

    // Grabbing a rejected release is allowed; the dialog has to say what is
    // being overridden.
    XCTAssertTrue(
      app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'already downloaded'"))
        .firstMatch.waitForExistence(timeout: 5),
      "the override dialog didn't say what was rejected")
  }

  func testARefusedGrabSurfacesTheReason() {
    let app = openSearch(state: "grab-fails")
    let approved = release("release-approved", in: app)
    XCTAssertTrue(approved.waitForExistence(timeout: 15))

    approved.tap()
    element("search.confirmGrab", in: app).tap()

    let error = element("search.grabError", in: app)
    XCTAssertTrue(error.waitForExistence(timeout: 10), "a refused grab said nothing")
    XCTAssertTrue(error.label.contains("rejected by the indexer"))
  }

  // MARK: - Empty and automatic

  func testAnEmptySearchSaysSoRatherThanLookingBroken() {
    let app = openSearch(state: "no-releases")

    XCTAssertTrue(element("search.empty", in: app).waitForExistence(timeout: 15))
  }

  func testAutomaticSearchIsOfferedAlongsideTheInteractiveOne() {
    let app = XCUIApplication()
    app.launchArguments = ["--uitest-seed-dashboard"]
    app.launch()
    app.buttons["Services"].firstMatch.tap()
    app.descendants(matching: .any)
      .matching(identifier: "services.row.\(radarr)").firstMatch.tap()
    let movie = element("radarr.row.10", in: app)
    XCTAssertTrue(movie.waitForExistence(timeout: 15))
    movie.tap()

    let automatic = element("radarr.detail.automaticSearch", in: app)
    XCTAssertTrue(scrollTo(automatic, in: app, attempts: 12))
    automatic.tap()

    // Nothing on screen changes — the command's effect shows up in the queue
    // later — so the assertion is that the screen survived and stayed usable.
    XCTAssertTrue(element("radarr.detail", in: app).waitForExistence(timeout: 10))
    XCTAssertFalse(element("radarr.library.refreshError", in: app).exists)
  }

  private func waitForOrder(
    first: XCUIElement, second: XCUIElement, timeout: TimeInterval = 5
  ) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
      if first.exists, second.exists, first.frame.origin.y < second.frame.origin.y { return true }
      _ = first.waitForExistence(timeout: 0.3)
    }
    return false
  }
}
