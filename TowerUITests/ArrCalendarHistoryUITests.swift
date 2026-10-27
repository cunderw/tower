import XCTest

/// The shared calendar and history sections.
@MainActor
final class ArrCalendarHistoryUITests: XCTestCase {
  private let radarr = "A0000000-0000-0000-0000-000000000001"
  private let sonarr = "A0000000-0000-0000-0000-000000000002"

  override func setUp() {
    super.setUp()
    continueAfterFailure = false
  }

  private func openSection(_ section: String, of service: String) -> XCUIApplication {
    let app = XCUIApplication()
    app.launchArguments = ["--uitest-seed-dashboard"]
    app.launch()
    app.buttons["Services"].firstMatch.tap()
    let row = app.descendants(matching: .any)
      .matching(identifier: "services.row.\(service)").firstMatch
    XCTAssertTrue(row.waitForExistence(timeout: 10))
    row.tap()
    XCTAssertTrue(element("arr.shell", in: app).waitForExistence(timeout: 15))
    app.buttons[section].firstMatch.tap()
    return app
  }

  private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
    app.descendants(matching: .any).matching(identifier: identifier).firstMatch
  }

  // MARK: - Calendar

  func testTheCalendarGroupsByDayAndMarksDownloadedEntries() {
    let app = openSection("Calendar", of: radarr)

    let downloaded = element("calendar.entry.10", in: app)
    XCTAssertTrue(downloaded.waitForExistence(timeout: 15), "the calendar never loaded")
    XCTAssertTrue(downloaded.label.contains("Downloaded"), downloaded.label)

    // Same day as the entry above it, three days before the third — so there is
    // more than one day section and they are in order.
    let upcoming = element("calendar.entry.11", in: app)
    XCTAssertTrue(upcoming.exists)
    XCTAssertFalse(upcoming.label.contains("Downloaded"))
    XCTAssertLessThan(
      upcoming.frame.origin.y, downloaded.frame.origin.y,
      "entries within a day are not in time order")

    let later = element("calendar.entry.12", in: app)
    XCTAssertTrue(later.exists)
    XCTAssertGreaterThan(
      later.frame.origin.y, downloaded.frame.origin.y, "days are out of order")
    XCTAssertTrue(later.label.contains("Unmonitored"))
  }

  func testTodayIsMarked() {
    let app = openSection("Calendar", of: radarr)
    XCTAssertTrue(element("calendar.entry.10", in: app).waitForExistence(timeout: 15))

    XCTAssertTrue(
      app.staticTexts["Today"].exists,
      "the current day isn't marked, which is the one a reader is looking for")
  }

  func testAnEmptyCalendarSaysSo() {
    let app = openSection("Calendar", of: sonarr)

    XCTAssertTrue(element("calendar.empty", in: app).waitForExistence(timeout: 15))
  }

  // MARK: - History

  func testHistoryShowsEventTypeQualityAndTime() {
    let app = openSection("History", of: radarr)

    let grabbed = element("history.record.9001", in: app)
    XCTAssertTrue(grabbed.waitForExistence(timeout: 15), "history never loaded")
    XCTAssertTrue(grabbed.label.contains("Grabbed"), grabbed.label)
    XCTAssertTrue(grabbed.label.contains("WEBDL-1080p"), grabbed.label)
    XCTAssertTrue(grabbed.label.contains("ago"), "no relative time: \(grabbed.label)")

    XCTAssertTrue(element("history.record.9002", in: app).label.contains("Imported"))
    XCTAssertTrue(element("history.record.9003", in: app).label.contains("Download failed"))
  }

  func testTappingAHistoryRecordOpensItsMedia() {
    let app = openSection("History", of: radarr)
    let grabbed = element("history.record.9001", in: app)
    XCTAssertTrue(grabbed.waitForExistence(timeout: 15))

    grabbed.tap()

    XCTAssertTrue(
      element("radarr.detail", in: app).waitForExistence(timeout: 10),
      "the history row didn't open its movie")
    XCTAssertTrue(app.navigationBars["Downloaded Film"].exists)
  }

  func testAnEmptyHistorySaysSo() {
    let app = openSection("History", of: sonarr)

    XCTAssertTrue(element("history.empty", in: app).waitForExistence(timeout: 15))
  }
}
