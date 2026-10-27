import XCTest

/// Sonarr's three levels: series → season → episode, with monitoring and
/// search at each.
@MainActor
final class SonarrLibraryUITests: XCTestCase {
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
    XCTAssertTrue(
      element("sonarr.row.1", in: app).waitForExistence(timeout: 15), "the library never loaded")
    return app
  }

  private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
    app.descendants(matching: .any).matching(identifier: identifier).firstMatch
  }

  @discardableResult
  private func reveal(_ element: XCUIElement, in app: XCUIApplication) -> Bool {
    scrollTo(element, in: app, attempts: 12)
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

  private func openSeasonOne(in app: XCUIApplication) {
    element("sonarr.row.1", in: app).tap()
    XCTAssertTrue(element("sonarr.detail", in: app).waitForExistence(timeout: 10))
    let season = element("sonarr.season.1", in: app)
    XCTAssertTrue(reveal(season, in: app), "season 1 never appeared")
    season.tap()
    XCTAssertTrue(element("sonarr.season", in: app).waitForExistence(timeout: 10))
  }

  // MARK: - Library and series detail

  func testTheLibraryShowsAiredProgressRatherThanTotalEpisodes() {
    // 20 of 20 aired is "Complete" even though the series has unaired episodes
    // ahead of it — counting those would make every continuing series look
    // permanently behind.
    let app = launchOnSonarr()

    XCTAssertTrue(element("sonarr.row.1", in: app).label.contains("Complete"))
    XCTAssertTrue(element("sonarr.row.2", in: app).label.contains("6 of 10"))
    XCTAssertTrue(element("sonarr.row.2", in: app).label.contains("Unmonitored"))
  }

  func testSeriesDetailListsItsSeasonsWithSpecialsFirst() {
    let app = launchOnSonarr()
    element("sonarr.row.1", in: app).tap()

    XCTAssertTrue(element("sonarr.detail", in: app).waitForExistence(timeout: 10))
    let specials = element("sonarr.season.0", in: app)
    XCTAssertTrue(reveal(specials, in: app))
    XCTAssertTrue(specials.label.contains("Specials"))
    XCTAssertLessThan(
      specials.frame.origin.y, element("sonarr.season.1", in: app).frame.origin.y)
  }

  // MARK: - Episodes

  func testASeasonListsItsEpisodesWithTheirThreeStates() {
    let app = launchOnSonarr()
    openSeasonOne(in: app)

    // Downloaded, aired-but-missing, and not out yet — the same three-way split
    // the Radarr library makes, and only one of them is worth searching for.
    XCTAssertTrue(element("sonarr.episode.101", in: app).waitForExistence(timeout: 10))
    XCTAssertTrue(element("sonarr.episode.101", in: app).label.contains("Downloaded"))
    XCTAssertTrue(element("sonarr.episode.102", in: app).label.contains("Missing"))
    XCTAssertTrue(element("sonarr.episode.103", in: app).label.contains("Unaired"))
  }

  func testEpisodeDetailShowsFileAndQualityWhenDownloaded() {
    let app = launchOnSonarr()
    openSeasonOne(in: app)
    element("sonarr.episode.101", in: app).tap()

    XCTAssertTrue(element("sonarr.episode.detail", in: app).waitForExistence(timeout: 10))
    let quality = app.staticTexts
      .containing(NSPredicate(format: "label CONTAINS 'WEBDL-1080p'")).firstMatch
    XCTAssertTrue(reveal(quality, in: app), "no quality on a downloaded episode")
    let size = app.staticTexts.containing(NSPredicate(format: "label CONTAINS '5.37 GB'")).firstMatch
    XCTAssertTrue(size.exists, "no size on a downloaded episode")
  }

  func testAnEpisodeWithNoFileSaysWhichKindOfNoFile() {
    let app = launchOnSonarr()
    openSeasonOne(in: app)
    element("sonarr.episode.103", in: app).tap()

    XCTAssertTrue(element("sonarr.episode.detail", in: app).waitForExistence(timeout: 10))
    let noFile = element("sonarr.episode.noFile", in: app)
    XCTAssertTrue(reveal(noFile, in: app))
    XCTAssertTrue(noFile.label.contains("aired"), "an unaired episode read as merely missing")
  }

  // MARK: - Monitoring at three levels

  func testMonitoringCanBeToggledAtSeriesLevel() {
    let app = launchOnSonarr()
    element("sonarr.row.1", in: app).tap()
    XCTAssertTrue(element("sonarr.detail", in: app).waitForExistence(timeout: 10))

    let toggle = app.switches["sonarr.detail.monitored"].firstMatch
    XCTAssertTrue(toggle.waitForExistence(timeout: 10))
    XCTAssertEqual(toggle.value as? String, "1")

    flip("sonarr.detail.monitored", in: app)

    XCTAssertTrue(waitForValue(toggle, equals: "0"), "the series monitor toggle didn't stick")
  }

  func testTogglingASeasonUpdatesItsEpisodes() {
    // A local-only flag flip would pass this falsely: Sonarr applies a
    // season's monitoring to its episodes, so the episode rows have to follow.
    let app = launchOnSonarr()
    openSeasonOne(in: app)
    XCTAssertTrue(element("sonarr.episode.101", in: app).waitForExistence(timeout: 10))
    XCTAssertFalse(element("sonarr.episode.101", in: app).label.contains("Unmonitored"))

    flip("sonarr.season.monitored", in: app)

    XCTAssertTrue(
      waitForLabel(element("sonarr.episode.101", in: app), containing: "Unmonitored"),
      "the season's episodes kept their old monitoring")
    XCTAssertTrue(element("sonarr.episode.102", in: app).label.contains("Unmonitored"))
  }

  func testMonitoringCanBeToggledOnASingleEpisode() {
    let app = launchOnSonarr()
    openSeasonOne(in: app)
    element("sonarr.episode.101", in: app).tap()
    XCTAssertTrue(element("sonarr.episode.detail", in: app).waitForExistence(timeout: 10))

    let toggle = app.switches["sonarr.episode.monitored"].firstMatch
    XCTAssertTrue(reveal(toggle, in: app))
    XCTAssertEqual(toggle.value as? String, "1")

    flip("sonarr.episode.monitored", in: app)

    XCTAssertTrue(waitForValue(toggle, equals: "0"))
    // And only that episode — its neighbour is untouched.
    tapBack(in: app)
    XCTAssertTrue(element("sonarr.episode.102", in: app).waitForExistence(timeout: 10))
    XCTAssertFalse(element("sonarr.episode.102", in: app).label.contains("Unmonitored"))
  }

  func testAFailedToggleSaysSoOnEachOfTheThreeScreens() {
    // Each level is pushed over the one before, so an error shown only on the
    // library list is out of sight on all three.
    let app = launchOnSonarr(state: "action-fails")
    element("sonarr.row.1", in: app).tap()
    XCTAssertTrue(element("sonarr.detail", in: app).waitForExistence(timeout: 10))
    XCTAssertFalse(element("sonarr.detail.actionError", in: app).exists)

    flip("sonarr.detail.monitored", in: app)
    XCTAssertTrue(
      element("sonarr.detail.actionError", in: app).waitForExistence(timeout: 10),
      "the failed series toggle was silent")

    let season = element("sonarr.season.1", in: app)
    XCTAssertTrue(reveal(season, in: app), "season 1 never appeared")
    season.tap()
    XCTAssertTrue(element("sonarr.season", in: app).waitForExistence(timeout: 10))
    flip("sonarr.season.monitored", in: app)
    XCTAssertTrue(
      element("sonarr.season.actionError", in: app).waitForExistence(timeout: 10),
      "the season screen showed no error")

    let episode = element("sonarr.episode.101", in: app)
    XCTAssertTrue(reveal(episode, in: app), "episode 101 never appeared")
    episode.tap()
    XCTAssertTrue(element("sonarr.episode.detail", in: app).waitForExistence(timeout: 10))
    let toggle = app.switches["sonarr.episode.monitored"].firstMatch
    XCTAssertTrue(reveal(toggle, in: app))
    flip("sonarr.episode.monitored", in: app)
    XCTAssertTrue(
      element("sonarr.episode.actionError", in: app).waitForExistence(timeout: 10),
      "the episode screen showed no error")
  }

  // MARK: - Search entry points

  func testSearchIsOfferedAtSeriesSeasonAndEpisodeLevel() {
    let app = launchOnSonarr()
    element("sonarr.row.1", in: app).tap()
    XCTAssertTrue(element("sonarr.detail", in: app).waitForExistence(timeout: 10))
    XCTAssertTrue(reveal(element("sonarr.detail.search", in: app), in: app), "no series search")

    let season = element("sonarr.season.1", in: app)
    XCTAssertTrue(reveal(season, in: app))
    season.tap()
    XCTAssertTrue(element("sonarr.season.search", in: app).waitForExistence(timeout: 10))

    element("sonarr.episode.102", in: app).tap()
    XCTAssertTrue(element("sonarr.episode.detail", in: app).waitForExistence(timeout: 10))
    XCTAssertTrue(reveal(element("sonarr.episode.automaticSearch", in: app), in: app))
    XCTAssertTrue(element("sonarr.episode.interactiveSearch", in: app).exists)
  }

  func testAnEpisodesInteractiveSearchOpensTheSharedReleaseList() {
    // The same screen Radarr uses — one component, two services.
    let app = launchOnSonarr()
    openSeasonOne(in: app)
    element("sonarr.episode.102", in: app).tap()
    XCTAssertTrue(element("sonarr.episode.detail", in: app).waitForExistence(timeout: 10))
    let search = element("sonarr.episode.interactiveSearch", in: app)
    XCTAssertTrue(reveal(search, in: app))

    search.tap()

    XCTAssertTrue(
      element("search.release.sonarr-release", in: app).waitForExistence(timeout: 15),
      "the shared release list never appeared for Sonarr")
  }

  private func waitForValue(
    _ element: XCUIElement, equals value: String, timeout: TimeInterval = 10
  ) -> Bool {
    let predicate = NSPredicate(format: "value == %@", value)
    let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
    return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
  }

  private func waitForLabel(
    _ element: XCUIElement, containing text: String, timeout: TimeInterval = 10
  ) -> Bool {
    let predicate = NSPredicate(format: "label CONTAINS %@", text)
    let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
    return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
  }
}
