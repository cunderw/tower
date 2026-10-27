import XCTest

/// The *arr More screen: health, disk space, system status, commands.
@MainActor
final class ArrMoreUITests: XCTestCase {
  private let radarr = "A0000000-0000-0000-0000-000000000001"
  private let sonarr = "A0000000-0000-0000-0000-000000000002"

  override func setUp() {
    super.setUp()
    continueAfterFailure = false
  }

  private func openMore(of service: String, state: String? = nil) -> XCUIApplication {
    let app = XCUIApplication()
    app.launchArguments = ["--uitest-seed-dashboard"]
    if let state { app.launchEnvironment["UITEST_RADARR_STATE"] = state }
    app.launch()
    app.buttons["Services"].firstMatch.tap()
    let row = app.descendants(matching: .any)
      .matching(identifier: "services.row.\(service)").firstMatch
    XCTAssertTrue(row.waitForExistence(timeout: 10))
    row.tap()
    XCTAssertTrue(element("arr.shell", in: app).waitForExistence(timeout: 15))
    app.buttons["More"].firstMatch.tap()
    XCTAssertTrue(element("more", in: app).waitForExistence(timeout: 10))
    return app
  }

  private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
    app.descendants(matching: .any).matching(identifier: identifier).firstMatch
  }

  @discardableResult
  private func reveal(_ element: XCUIElement, in app: XCUIApplication) -> Bool {
    scrollTo(element, in: app, attempts: 12)
  }

  /// Scrolls to a command and taps it once it is actually hittable.
  ///
  /// Scrolling puts the row in the tree, but not necessarily under the finger
  /// yet — a tap dispatched in that window lands on nothing, and the failure
  /// then shows up as "the command reported nothing" several lines later.
  private func tapCommand(_ name: String, in app: XCUIApplication) {
    let command = element("more.command.\(name)", in: app)
    XCTAssertTrue(reveal(command, in: app), "the \(name) command never appeared")
    let hittable = XCTNSPredicateExpectation(
      predicate: NSPredicate(format: "isHittable == true"), object: command)
    XCTAssertEqual(
      XCTWaiter().wait(for: [hittable], timeout: 5), .completed,
      "the \(name) command never became tappable")
    command.tap()
  }

  // MARK: - Health

  func testHealthWarningsRenderWithTheirLinkWhenTheApiProvidesOne() {
    let app = openMore(of: radarr)

    let error = element("more.health.1", in: app)
    XCTAssertTrue(error.waitForExistence(timeout: 15), "health never loaded")
    XCTAssertTrue(error.label.contains("Indexers unavailable"), error.label)

    // The service links its own explanation; a warning nobody can act on just
    // worries them. The link is its own element rather than part of the row's
    // combined label, so it is asserted as one — and there is exactly one,
    // because only one fixture check carries a wiki URL.
    // Counted by identifier, not by element type. A SwiftUI `Link` surfaced
    // as a Button before iOS 27 and as a Link on it.
    XCTAssertEqual(
      app.descendants(matching: .any)
        .matching(NSPredicate(format: "identifier ENDSWITH '.wiki'")).count, 1,
      "expected exactly one wiki link, for the one check that has one")

    // **Hittable, not merely present.** A link with a hit area of roughly
    // 60x14pt does nothing under a finger, while a synthetic tap lands dead
    // centre and always works. `exists` passes either way; `isHittable` plus a
    // frame tall enough to hit is the assertion that can fail.
    let link = element("more.health.1.wiki", in: app)
    XCTAssertTrue(link.waitForExistence(timeout: 5), "the wiki link lost its identifier")
    XCTAssertTrue(link.isHittable)
    XCTAssertGreaterThanOrEqual(
      link.frame.height, 28,
      "the wiki link's tap target is back under a finger's worth of height")

    XCTAssertTrue(element("more.health.2", in: app).exists)
  }

  func testAHealthyServiceSaysSoRatherThanShowingAnEmptyList() {
    let app = openMore(of: sonarr)

    XCTAssertTrue(element("more.health.clear", in: app).waitForExistence(timeout: 15))
  }

  // MARK: - Disk space

  func testDiskSpaceFormatsMultiTerabyteValues() {
    let app = openMore(of: radarr)
    let disk = element("more.disk./data", in: app)
    XCTAssertTrue(reveal(disk, in: app), "disk space never appeared")

    // 12 TB total, 3.22 TB free — the units are the whole point of this row.
    XCTAssertTrue(disk.label.contains("TB"), "no terabyte units: \(disk.label)")
    XCTAssertTrue(disk.label.contains("free"), disk.label)
  }

  // MARK: - System

  func testSystemStatusShowsVersionAndUptime() {
    let app = openMore(of: radarr)
    // Every row in the section inherits the section's identifier, so the
    // assertions are per row by label rather than on one merged string.
    let rows = app.staticTexts.matching(identifier: "more.status")
    XCTAssertTrue(reveal(rows.firstMatch, in: app))

    let labels = (0..<rows.count).map { rows.element(boundBy: $0).label }
    XCTAssertTrue(labels.contains { $0.contains("5.14.0.9383") }, "no version: \(labels)")

    // **Revealed, not read out of the first snapshot** — the same rule the
    // Uptime assertion below follows. Container is not reliably above the fold:
    // in this fixture, which has two warnings, the taller health link pushes it
    // below. Rows are revealed in document order because scrolling *past* a row
    // removes it from the tree again.
    // Two steps, and both are needed. **Scroll** using the same `.containing`
    // query shape the Uptime assertion below uses — a compound
    // `identifier == … AND label BEGINSWITH …` predicate never resolves for
    // `scrollTo`, so it cannot be used to find a row that is not on screen yet.
    // Then **re-read** the section's labels, because each row renders two
    // static texts: the combined `more.status` one ("Container, Docker") and a
    // bare label one ("Container"). Asserting on the element the scroll found
    // reads the bare one, whose label can never contain "Docker".
    let containerRow = app.staticTexts
      .containing(NSPredicate(format: "label BEGINSWITH 'Container'")).firstMatch
    XCTAssertTrue(reveal(containerRow, in: app), "no container row: \(labels)")

    let revealed = app.staticTexts.matching(identifier: "more.status")
    let revealedLabels = (0..<revealed.count).map { revealed.element(boundBy: $0).label }
    XCTAssertTrue(
      revealedLabels.contains { $0.contains("Docker") }, "no container row: \(revealedLabels)")

    // Uptime is the last row in the section and starts below the fold — a List
    // doesn't render what it hasn't scrolled to, so it is revealed rather than
    // read out of the first snapshot.
    let uptime = app.staticTexts
      .containing(NSPredicate(format: "label BEGINSWITH 'Uptime'")).firstMatch
    XCTAssertTrue(reveal(uptime, in: app), "no uptime row")
  }

  // MARK: - Commands

  func testACommandReportsThatItRan() {
    // A command that reports nothing looks exactly like a button that does
    // nothing, because from the outside that is what it is.
    let app = openMore(of: radarr)
    // Queried as a `staticText`: the identifier is on a `Label`, whose glyph
    // child inherits it, and `firstMatch` otherwise returns the image.
    let result = app.staticTexts.matching(identifier: "more.commandResult").firstMatch
    tapCommand("RssSync", in: app)

    XCTAssertTrue(result.waitForExistence(timeout: 20), "the command reported nothing")
    XCTAssertTrue(result.label.contains("queued"), result.label)
  }

  func testAFailedCommandSaysWhy() {
    let app = openMore(of: radarr, state: "command-fails")
    let result = app.staticTexts.matching(identifier: "more.commandResult").firstMatch
    tapCommand("RssSync", in: app)

    XCTAssertTrue(result.waitForExistence(timeout: 20))
    XCTAssertTrue(result.label.contains("refused the command"), result.label)
  }
}
