import XCTest

/// The notification bell and sheet, driven against
/// `FakeNotificationRepository`.
@MainActor
final class NotificationUITests: XCTestCase {
  override func setUp() {
    super.setUp()
    continueAfterFailure = false
  }

  private func launch(state: String? = nil) -> XCUIApplication {
    let app = XCUIApplication()
    app.launchArguments = ["--uitest-seed-dashboard"]
    if let state { app.launchEnvironment["UITEST_NOTIFICATIONS_STATE"] = state }
    app.launch()
    return app
  }

  private func openSheet(_ app: XCUIApplication) {
    let bell = app.buttons["toolbar.notifications"]
    XCTAssertTrue(bell.waitForExistence(timeout: 10), "the notification bell never appeared")
    bell.tap()
  }

  private func row(_ id: String, in app: XCUIApplication) -> XCUIElement {
    app.descendants(matching: .any).matching(identifier: "notifications.row.\(id)").firstMatch
  }

  // MARK: - The badge

  func testTheBellCarriesTheUnreadCountAndSaysItInWords() {
    // A state is conveyed in text, not colour alone, and this is the surface
    // where it matters most: a small red numeral is not the only signal. The
    // accessibility label spells the count out.
    let app = launch()
    let bell = app.buttons["toolbar.notifications"]

    XCTAssertTrue(bell.waitForExistence(timeout: 10))
    XCTAssertTrue(
      bell.label.contains("4 unread"),
      "the bell didn't announce the unread count: \(bell.label)"
    )
  }

  func testTheBellHasNoBadgeWhenNothingIsUnread() {
    // `badgeCount` is `Int?` and nil at zero — a badge reading "0" draws the eye
    // to say nothing happened.
    let app = launch(state: "empty")
    let bell = app.buttons["toolbar.notifications"]

    XCTAssertTrue(bell.waitForExistence(timeout: 10))
    XCTAssertEqual(bell.label, "Notifications", "an empty inbox still announced a count")
  }

  func testTheBellAppearsOnEveryTab() {
    // The bell is on every tab, asserted rather than assumed — each tab applies
    // the toolbar modifier inside its own `NavigationStack`, so this is four
    // separate opportunities to forget it.
    let app = launch()
    for tab in ["Docker", "VMs", "Shares", "Dashboard"] {
      app.buttons[tab].firstMatch.tap()
      XCTAssertTrue(
        app.buttons["toolbar.notifications"].waitForExistence(timeout: 10),
        "the \(tab) tab has no notification bell"
      )
    }
  }

  // MARK: - The sheet

  func testTheSheetShowsUnreadFirstWithImportanceInWords() {
    let app = launch()
    openSheet(app)

    let alert = row("uitest-notification-1", in: app)
    XCTAssertTrue(alert.waitForExistence(timeout: 10), "the unread notifications never rendered")
    // Importance leads the merged label, so VoiceOver says it before the subject —
    // and it is a word, not only a red glyph.
    XCTAssertTrue(
      alert.label.hasPrefix("Alert, UPS Alert"),
      "importance wasn't announced first, in words: \(alert.label)"
    )
    XCTAssertTrue(
      row("uitest-notification-3", in: app).label.hasPrefix("Warning,"),
      "a warning wasn't announced as one"
    )
  }

  func testSwitchingToTheArchiveShowsDifferentNotifications() {
    let app = launch()
    openSheet(app)
    XCTAssertTrue(row("uitest-notification-1", in: app).waitForExistence(timeout: 10))

    app.buttons["Archive"].firstMatch.tap()

    XCTAssertTrue(
      row("uitest-notification-5", in: app).waitForExistence(timeout: 10),
      "the archive bucket never rendered"
    )
    XCTAssertFalse(
      row("uitest-notification-1", in: app).exists,
      "an unread notification is showing in the archive bucket"
    )
  }

  func testArchivingMovesANotificationBetweenBucketsAndUpdatesTheBadge() {
    // The end-to-end proof that the action reached the server and the badge is a
    // claim about the server's state rather than a local decrement.
    let app = launch()
    openSheet(app)

    let target = row("uitest-notification-3", in: app)
    XCTAssertTrue(target.waitForExistence(timeout: 10))
    target.swipeRight()

    // By identifier, not by label: the bucket picker also has an "Archive"
    // button, and matching by label taps *that* — switching buckets while looking
    // exactly like a successful archive, right down to the row disappearing.
    // Only the badge assertion tells the two apart.
    let archive = app.buttons["notifications.swipe.archive"]
    XCTAssertTrue(archive.waitForExistence(timeout: 10), "the leading swipe offered no Archive action")
    archive.tap()

    XCTAssertTrue(
      waitForNonExistence(target, timeout: 10),
      "the archived notification stayed in the unread list"
    )

    app.buttons["notifications.done"].tap()
    let bell = app.buttons["toolbar.notifications"]
    XCTAssertTrue(bell.waitForExistence(timeout: 10))
    XCTAssertTrue(
      waitForLabel(bell, toContain: "3 unread", timeout: 10),
      "the badge didn't follow the archive: \(bell.label)"
    )
  }

  func testAFailedActionKeepsTheListAndSurfacesTheError() {
    // `uitest-notification-fail` fails every action. The list must survive it —
    // a swipe that silently removes a row it couldn't archive would be worse than
    // no swipe at all.
    let app = launch()
    openSheet(app)

    let failing = row("uitest-notification-fail", in: app)
    XCTAssertTrue(failing.waitForExistence(timeout: 10))
    failing.swipeRight()
    let archive = app.buttons["notifications.swipe.archive"]
    XCTAssertTrue(archive.waitForExistence(timeout: 10), "the leading swipe offered no Archive action")
    archive.tap()

    XCTAssertTrue(
      app.descendants(matching: .any).matching(identifier: "notifications.actionError")
        .firstMatch.waitForExistence(timeout: 10),
      "a failed action surfaced no message"
    )
    XCTAssertTrue(failing.exists, "a failed archive removed the row anyway")
  }

  func testTheEmptyUnreadStateDoesNotClaimThereAreNoNotifications() {
    let app = launch(state: "empty")
    openSheet(app)

    XCTAssertTrue(
      app.descendants(matching: .any).matching(identifier: "notifications.emptyUnread")
        .firstMatch.waitForExistence(timeout: 10),
      "the empty-unread state never appeared"
    )
  }

  // MARK: - Helpers

  private func waitForNonExistence(_ element: XCUIElement, timeout: TimeInterval) -> Bool {
    let expectation = XCTNSPredicateExpectation(
      predicate: NSPredicate(format: "exists == false"), object: element
    )
    return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
  }

  /// Polls a label rather than existence — the bell exists throughout; it's what
  /// it *says* that changes.
  private func waitForLabel(_ element: XCUIElement, toContain text: String, timeout: TimeInterval) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
      if element.exists, element.label.contains(text) { return true }
      _ = element.waitForExistence(timeout: 0.5)
    }
    return false
  }
}
