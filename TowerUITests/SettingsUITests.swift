import XCTest

/// Settings' system info, the theme override and its persistence, and the
/// syslog viewer.
@MainActor
final class SettingsUITests: XCTestCase {
  override func setUp() {
    super.setUp()
    continueAfterFailure = false
  }

  private func launch() -> XCUIApplication {
    let app = XCUIApplication()
    app.launchArguments = ["--uitest-seed-dashboard"]
    app.launch()
    return app
  }

  private func openSettings(_ app: XCUIApplication) {
    let gear = app.buttons["toolbar.settings"]
    XCTAssertTrue(gear.waitForExistence(timeout: 10), "the settings gear never appeared")
    gear.tap()
  }

  /// Opens the log viewer from Settings.
  ///
  /// Scrolls first: on iPad the Settings sheet is a *centered form sheet*,
  /// shorter than the device, so the Logs row starts below the fold — and a
  /// SwiftUI `List` doesn't render rows it hasn't scrolled to, so an unscrolled
  /// tap fails with "no matches found" rather than with a hidden row.
  private func openLogs(_ app: XCUIApplication) {
    let logs = app.descendants(matching: .any).matching(identifier: "settings.logs").firstMatch
    XCTAssertTrue(scrollTo(logs, in: app, attempts: 8), "Settings had no Logs row")
    logs.tap()
  }

  private func text(containing substring: String, in app: XCUIApplication) -> XCUIElement {
    app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", substring)).firstMatch
  }

  // MARK: - System info

  func testSystemSectionShowsWhatTheDashboardRead() {
    // Fed by `DashboardStore`, so it only appears once the dashboard has answered
    // — which is why this waits for the dashboard before opening Settings.
    let app = launch()
    XCTAssertTrue(
      app.descendants(matching: .any).matching(identifier: "services.docker")
        .firstMatch.waitForExistence(timeout: 15),
      "the dashboard never finished loading"
    )
    openSettings(app)

    // `LabeledContent` merges its label and value, so these read "OS, Unraid OS
    // 7.3.0" — matched by substring rather than equality.
    XCTAssertTrue(text(containing: "Unraid OS 7.3.0", in: app).waitForExistence(timeout: 10))
    XCTAssertTrue(text(containing: "Example 8-Core CPU", in: app).exists)
    XCTAssertTrue(text(containing: "8 cores", in: app).exists)
  }

  func testUptimeRendersAsADurationNotADate() {
    // `bootTimestamp` is a boot *time*; rendering it raw would put a date where a
    // duration belongs. The fixture boots on 2026-01-01, so any "2026" in this row
    // means the conversion was skipped.
    let app = launch()
    XCTAssertTrue(
      app.descendants(matching: .any).matching(identifier: "services.docker")
        .firstMatch.waitForExistence(timeout: 15)
    )
    openSettings(app)

    let uptime = app.descendants(matching: .any).matching(identifier: "settings.uptime").firstMatch
    XCTAssertTrue(uptime.waitForExistence(timeout: 10), "the Uptime row never rendered")
    XCTAssertFalse(uptime.label.contains("2026"), "uptime rendered as a date: \(uptime.label)")
    XCTAssertTrue(uptime.label.contains("d "), "uptime didn't read as a duration: \(uptime.label)")
  }

  // MARK: - Theme

  func testTheThemeChoiceSurvivesARelaunch() {
    // The choice survives a relaunch, end to end — `ThemePreferenceTests`
    // proves the store round-trips, and this proves the picker is actually
    // wired to it.
    let app = launch()
    openSettings(app)

    let theme = app.descendants(matching: .any).matching(identifier: "settings.theme").firstMatch
    // Scrolls if needed — see `XCTestCase+Scrolling.swift`. On iPad this sheet is
    // a centered form sheet, shorter than the device, so the picker starts below
    // the fold and a `List` hasn't rendered it.
    scrollTo(theme, in: app)
    XCTAssertTrue(theme.waitForExistence(timeout: 10), "the theme picker never appeared")
    theme.tap()
    app.buttons["Dark"].tap()

    app.terminate()
    let relaunched = launch()
    openSettings(relaunched)

    let restored = relaunched.descendants(matching: .any)
      .matching(identifier: "settings.theme").firstMatch
    scrollTo(restored, in: relaunched)
    XCTAssertTrue(restored.waitForExistence(timeout: 10))
    XCTAssertTrue(
      restored.value as? String == "Dark" || restored.label.contains("Dark"),
      "the theme didn't survive a relaunch: value=\(String(describing: restored.value)) label=\(restored.label)"
    )

    // Put it back, so this test doesn't change what every later test in the run
    // sees — `UserDefaults` persists across launches on the same simulator.
    restored.tap()
    relaunched.buttons["System"].tap()
  }

  // MARK: - Syslog viewer

  func testTheLogListLabelsAnEmptyFileAndOpensAPopulatedOne() {
    let app = launch()
    openSettings(app)

    openLogs(app)

    // A 0-byte file says so rather than opening to a blank screen — a real server
    // has several empty log files.
    XCTAssertTrue(
      app.descendants(matching: .any).matching(identifier: "logs.row.cron")
        .firstMatch.waitForExistence(timeout: 10)
    )
    XCTAssertTrue(text(containing: "Empty", in: app).exists, "a 0-byte log wasn't labelled")

    app.descendants(matching: .any).matching(identifier: "logs.row.docker.log").firstMatch.tap()

    XCTAssertTrue(
      app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "docker.log line"))
        .firstMatch.waitForExistence(timeout: 10),
      "the log viewer rendered no lines"
    )
  }

  func testATruncatedLogSaysSoAndCanLoadEarlierLines() {
    // Someone searching a log has to know whether they're looking at the whole
    // file or its tail.
    let app = launch()
    openSettings(app)
    openLogs(app)
    XCTAssertTrue(
      app.descendants(matching: .any).matching(identifier: "logs.row.docker.log")
        .firstMatch.waitForExistence(timeout: 10)
    )
    app.descendants(matching: .any).matching(identifier: "logs.row.docker.log").firstMatch.tap()

    let footer = app.descendants(matching: .any).matching(identifier: "logFile.lineCount").firstMatch
    XCTAssertTrue(footer.waitForExistence(timeout: 10), "the viewer showed no line count")
    XCTAssertTrue(
      footer.label.contains("Showing last 200 of 900"),
      "the footer didn't distinguish a tail from the whole file: \(footer.label)"
    )

    let loadMore = app.buttons["logFile.loadMore"]
    XCTAssertTrue(loadMore.waitForExistence(timeout: 10), "a truncated log offered no way to see earlier lines")
    loadMore.tap()

    XCTAssertTrue(
      waitForLabel(footer, toContain: "Showing last 800 of 900", timeout: 10),
      "loading earlier lines didn't widen the window: \(footer.label)"
    )
  }

  func testAWholeFileDoesNotOfferToLoadEarlierLines() {
    // A button that can't do anything is never offered. `syslog` is 12 lines, so
    // the initial 200-line window already holds all of it.
    let app = launch()
    openSettings(app)
    openLogs(app)
    let syslog = app.descendants(matching: .any).matching(identifier: "logs.row.syslog").firstMatch
    XCTAssertTrue(syslog.waitForExistence(timeout: 10))
    syslog.tap()

    let footer = app.descendants(matching: .any).matching(identifier: "logFile.lineCount").firstMatch
    XCTAssertTrue(footer.waitForExistence(timeout: 10))
    XCTAssertEqual(footer.label, "12 lines")
    XCTAssertFalse(
      app.buttons["logFile.loadMore"].exists,
      "a complete file offered to load earlier lines"
    )
  }

  func testAnEmptyLogOpensToAnExplanationRatherThanABlankScreen() {
    let app = launch()
    openSettings(app)
    openLogs(app)
    let cron = app.descendants(matching: .any).matching(identifier: "logs.row.cron").firstMatch
    XCTAssertTrue(cron.waitForExistence(timeout: 10))
    cron.tap()

    XCTAssertTrue(
      app.descendants(matching: .any).matching(identifier: "logFile.empty")
        .firstMatch.waitForExistence(timeout: 10),
      "an empty log opened to a blank screen"
    )
  }

  // MARK: - Helpers

  private func waitForLabel(_ element: XCUIElement, toContain text: String, timeout: TimeInterval) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
      if element.exists, element.label.contains(text) { return true }
      _ = element.waitForExistence(timeout: 0.5)
    }
    return false
  }
}
