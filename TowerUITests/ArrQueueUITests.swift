import XCTest

/// The shared *arr queue section.
@MainActor
final class ArrQueueUITests: XCTestCase {
  private let radarr = "A0000000-0000-0000-0000-000000000001"
  private let sonarr = "A0000000-0000-0000-0000-000000000002"

  override func setUp() {
    super.setUp()
    continueAfterFailure = false
  }

  private func openQueue(of service: String, state: String? = nil) -> XCUIApplication {
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
    app.buttons["Queue"].firstMatch.tap()
    return app
  }

  private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
    app.descendants(matching: .any).matching(identifier: identifier).firstMatch
  }

  private func queueRow(_ id: Int, in app: XCUIApplication) -> XCUIElement {
    element("queue.row.\(id)", in: app)
  }

  private func waitForNonExistence(of element: XCUIElement, timeout: TimeInterval = 10) -> Bool {
    let gone = XCTNSPredicateExpectation(
      predicate: NSPredicate(format: "exists == false"), object: element)
    return XCTWaiter().wait(for: [gone], timeout: timeout) == .completed
  }

  // MARK: - Rendering

  func testTheQueueShowsProgressTimeLeftAndProtocol() {
    let app = openQueue(of: radarr)

    let downloading = queueRow(41, in: app)
    XCTAssertTrue(downloading.waitForExistence(timeout: 15), "the queue never loaded")
    let label = downloading.label
    XCTAssertTrue(label.contains("Downloading"), label)
    XCTAssertTrue(label.contains("00:12:34"), "no time left: \(label)")
    XCTAssertTrue(label.contains("Usenet"), "no protocol: \(label)")
    XCTAssertTrue(label.contains("67 percent"), "no progress: \(label)")
  }

  func testAStuckImportSaysWhyRatherThanJustWarning() {
    // A row that says only "warning" sends the user to the *arr's web UI to
    // find out what this screen already knows.
    let app = openQueue(of: radarr)
    let stuck = queueRow(42, in: app)
    XCTAssertTrue(stuck.waitForExistence(timeout: 15))

    XCTAssertTrue(stuck.label.contains("Import blocked"), stuck.label)
    XCTAssertTrue(
      stuck.label.contains("No files found are eligible for import"),
      "the reason never reached the row: \(stuck.label)")
  }

  func testItemsNeedingAttentionLeadTheQueue() {
    // A stuck import at the bottom of a long queue is a stuck import nobody
    // finds.
    let app = openQueue(of: radarr)
    XCTAssertTrue(queueRow(42, in: app).waitForExistence(timeout: 15))

    XCTAssertLessThan(
      queueRow(42, in: app).frame.origin.y,
      queueRow(41, in: app).frame.origin.y,
      "the stuck item was below the healthy ones")
  }

  func testAWaitingToImportItemIsDistinctFromADownloadingOne() {
    let app = openQueue(of: radarr)
    XCTAssertTrue(queueRow(43, in: app).waitForExistence(timeout: 15))

    XCTAssertTrue(queueRow(43, in: app).label.contains("Waiting to import"))
    XCTAssertFalse(queueRow(43, in: app).label.contains("Downloading"))
  }

  // MARK: - Removal

  func testRemovingOffersBlocklistAndUpdatesTheList() {
    let app = openQueue(of: radarr)
    let row = queueRow(41, in: app)
    XCTAssertTrue(row.waitForExistence(timeout: 15))

    row.swipeLeft()
    let remove = element("queue.row.41.remove", in: app)
    if remove.waitForExistence(timeout: 2) { remove.tap() }

    // Both decisions offered, spelled out.
    XCTAssertTrue(element("queue.confirmRemove", in: app).waitForExistence(timeout: 5))
    XCTAssertTrue(element("queue.confirmBlocklist", in: app).exists)
    element("queue.confirmBlocklist", in: app).tap()

    XCTAssertTrue(waitForNonExistence(of: queueRow(41, in: app)), "the item stayed in the queue")
    XCTAssertTrue(queueRow(42, in: app).exists, "the rest of the queue was disturbed")
  }

  func testAFailedRemovalKeepsTheQueueAndSaysWhy() {
    let app = openQueue(of: radarr, state: "action-fails")
    let row = queueRow(41, in: app)
    XCTAssertTrue(row.waitForExistence(timeout: 15))

    row.swipeLeft()
    let remove = element("queue.row.41.remove", in: app)
    if remove.waitForExistence(timeout: 2) { remove.tap() }
    element("queue.confirmRemove", in: app).tap()

    XCTAssertTrue(
      element("queue.actionError", in: app).waitForExistence(timeout: 10),
      "the failure was swallowed")
    XCTAssertTrue(queueRow(41, in: app).exists, "the queue was lost to a failed removal")
  }

  // MARK: - Empty

  func testAnEmptyQueueSaysSoRatherThanLookingBroken() {
    let app = openQueue(of: sonarr)

    XCTAssertTrue(element("queue.empty", in: app).waitForExistence(timeout: 15))
  }
}
