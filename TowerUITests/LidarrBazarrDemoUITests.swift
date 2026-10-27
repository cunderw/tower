import XCTest

/// Lidarr and Bazarr smoke paths through **demo mode**, following
/// `ArrDemoSmokeUITests` and `OverseerrProwlarrDemoUITests`: neither screen has
/// a DEBUG seeded fake, so demo mode is the only way to reach them — and it is
/// the path an App Store reviewer takes.
///
/// Deliberately paths rather than per-screen assertions. What they catch is
/// the class of break the seeded suite structurally cannot: a demo repository
/// that returns nothing, a service never wired into `AppEnvironment.demo`, or
/// a mutation that never reaches the screen the user is looking at.
///
/// Runs on iPad too, so tab taps use `.firstMatch`: with `.sidebarAdaptable`
/// the tabs render twice there
/// (CLAUDE.md, "With the sidebar showing, two elements are labelled "Services"").
@MainActor
final class LidarrBazarrDemoUITests: XCTestCase {
  /// `DemoServices` numbers instances by `idSuffix`'s name list: Lidarr is 04, Bazarr 05.
  private let lidarr = "D0000000-0000-0000-0000-000000000004"
  private let bazarr = "D0000000-0000-0000-0000-000000000005"

  override func setUp() {
    super.setUp()
    continueAfterFailure = false
  }

  // MARK: - Navigation

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
    // Back to the tab bar first: with the iPad sidebar showing, "Services"
    // matches the collapsible section header as well as the tab, and tapping
    // the header collapses the rows this then looks for.
    useTabBarLayout(in: app)
    app.buttons["Services"].firstMatch.tap()
    let row = app.descendants(matching: .any).matching(identifier: "services.row.\(id)").firstMatch
    XCTAssertTrue(scrollTo(row, in: app), "the demo hub never offered \(id)")
    row.tap()
  }

  private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
    app.descendants(matching: .any).matching(identifier: identifier).firstMatch
  }

  private func anyRow(prefix: String, in app: XCUIApplication) -> XCUIElement {
    app.descendants(matching: .any)
      .matching(NSPredicate(format: "identifier BEGINSWITH %@", prefix)).firstMatch
  }

  @discardableResult
  private func reveal(_ element: XCUIElement, in app: XCUIApplication) -> Bool {
    scrollTo(element, in: app, attempts: 12)
  }

  /// Walks back up to the shell's section picker. Popping in a loop rather
  /// than a counted number of back taps keeps it honest on iPad, where the
  /// split view starts the stack at a different depth.
  private func popToShell(in app: XCUIApplication, attempts: Int = 4) -> Bool {
    for _ in 0..<attempts {
      if app.buttons["Queue"].firstMatch.exists { return true }
      let back = backButton(in: app)
      guard back.exists, back.isHittable else { break }
      back.tap()
    }
    return app.buttons["Queue"].firstMatch.waitForExistence(timeout: 5)
  }

  // MARK: - Lidarr: library → artist → album → tracks, and a mutation

  func testLidarrDemoPathRunsFromTheLibraryDownToTracks() {
    let app = launchIntoDemo()
    openService(lidarr, in: app)

    // Lidarr is built on the same shell as Radarr and Sonarr, so its arrival
    // is the shell's, not a screen of its own.
    XCTAssertTrue(
      element("arr.shell", in: app).waitForExistence(timeout: 20), "no *arr shell for Lidarr")

    // Artist 1 by identifier, not whichever row sorts first: the library sorts
    // by sort name, so the top row is Anvil Choir — an artist with nothing on
    // disk, and deliberately no seeded tracks.
    let artist = element("lidarr.row.1", in: app)
    XCTAssertTrue(artist.waitForExistence(timeout: 20), "the demo library never loaded")
    artist.tap()

    let album = anyRow(prefix: "lidarr.album.", in: app)
    XCTAssertTrue(album.waitForExistence(timeout: 20), "the demo artist had no albums")
    // Album 11 is the partial one, five tracks of ten — the row worth opening,
    // and the only one the demo seeds tracks for.
    let partial = element("lidarr.album.11", in: app)
    XCTAssertTrue(reveal(partial, in: app), "the demo artist had no partial album")
    partial.tap()

    let track = anyRow(prefix: "lidarr.track.", in: app)
    XCTAssertTrue(track.waitForExistence(timeout: 20), "the demo album listed no tracks")
  }

  func testUnmonitoringAnAlbumSticksInTheDemo() {
    let app = launchIntoDemo()
    openService(lidarr, in: app)

    let artist = element("lidarr.row.1", in: app)
    XCTAssertTrue(artist.waitForExistence(timeout: 20), "the demo library never loaded")
    artist.tap()

    let album = element("lidarr.album.11", in: app)
    XCTAssertTrue(album.waitForExistence(timeout: 20), "the demo artist had no albums")
    XCTAssertFalse(
      album.label.contains("Unmonitored"), "the album started unmonitored, so this proves nothing")
    album.tap()

    // The switch, not the row: a tap on a Toggle row's centre leaves the value
    // unchanged (CLAUDE.md, "Tapping a SwiftUI `Toggle` row does nothing").
    let toggle = element("lidarr.album.detail.monitored", in: app)
    XCTAssertTrue(reveal(toggle, in: app), "the album detail had no Monitored toggle")
    app.switches["lidarr.album.detail.monitored"].switches.firstMatch.tap()

    // Back on the artist, the row itself says so — which is the assertion that
    // the mutation reached the screen rather than only the store.
    tapBack(in: app)
    let changed = element("lidarr.album.11", in: app)
    XCTAssertTrue(changed.waitForExistence(timeout: 20), "never got back to the album list")
    let unmonitored = XCTNSPredicateExpectation(
      predicate: NSPredicate(format: "label CONTAINS %@", "Unmonitored"), object: changed)
    XCTAssertEqual(
      XCTWaiter().wait(for: [unmonitored], timeout: 20), .completed,
      "unmonitoring never showed up on the album row")
  }

  func testLidarrsQueueSharesTheDemoArrDataset() {
    let app = launchIntoDemo()
    openService(lidarr, in: app)

    XCTAssertTrue(popToShell(in: app), "no section picker on the Lidarr shell")
    app.buttons["Queue"].firstMatch.tap()

    // Lidarr's queue comes from the same demo dataset Radarr's does, so an
    // empty one here means the shared surface never got wired up.
    let row = anyRow(prefix: "queue.row.", in: app)
    XCTAssertTrue(row.waitForExistence(timeout: 20), "the demo Lidarr queue was empty")
  }

  // MARK: - Bazarr: wanted → search → download

  func testDownloadingASubtitleRemovesItsLanguageFromTheWantedRow() {
    let app = launchIntoDemo()
    openService(bazarr, in: app)

    // `bazarr.wanted.<id>` also prefixes that row's search button and the
    // empty-state view, so match the row itself rather than whatever sorts
    // first.
    let row = app.descendants(matching: .any).matching(
      NSPredicate(
        format: "identifier BEGINSWITH %@ AND NOT (identifier ENDSWITH %@) "
          + "AND identifier != %@", "bazarr.wanted.", ".search", "bazarr.wanted.empty")
    ).firstMatch
    XCTAssertTrue(row.waitForExistence(timeout: 20), "the demo wanted list never loaded")

    // The row's own search button, addressed by the row it belongs to, so the
    // assertion afterwards is about *that* row and not "some row went away".
    let identifier = row.identifier
    let search = element("\(identifier).search", in: app)
    XCTAssertTrue(reveal(search, in: app), "the wanted row offered no search")
    search.tap()

    let candidate = anyRow(prefix: "bazarr.candidate.", in: app)
    XCTAssertTrue(candidate.waitForExistence(timeout: 25), "no provider results in the demo")
    candidate.tap()

    let confirm = element("bazarr.confirmDownload", in: app)
    XCTAssertTrue(confirm.waitForExistence(timeout: 15), "no download confirmation")
    confirm.tap()

    // The sheet closes only after the wanted list has been re-read, so the
    // screen behind is already correct when it reappears. That first demo row
    // wants two languages, so it stays, with one language fewer.
    let wanted = element(identifier, in: app)
    XCTAssertTrue(wanted.waitForExistence(timeout: 25), "never got back to the wanted list")
    let narrowed = XCTNSPredicateExpectation(
      predicate: NSPredicate(format: "NOT (label CONTAINS %@)", "English,"), object: wanted)
    XCTAssertEqual(
      XCTWaiter().wait(for: [narrowed], timeout: 20), .completed,
      "the download never came off the wanted row")
  }

  func testBazarrsProviderSectionShowsSomethingFailing() {
    let app = launchIntoDemo()
    openService(bazarr, in: app)

    XCTAssertTrue(
      element("bazarr.sections", in: app).waitForExistence(timeout: 20), "no Bazarr sections")
    app.buttons["Providers"].firstMatch.tap()

    // The count is the reason to open this section at all, so an empty or
    // all-healthy demo would make it pointless.
    XCTAssertTrue(
      element("bazarr.failingProviders", in: app).waitForExistence(timeout: 20),
      "the demo had no failing provider to show")
  }
}
