import XCTest

/// Container updates (issue #23): one container from its detail screen, every
/// container through "Update All", and a server error reaching the screen.
///
/// Everything drives `FakeDockerRepository` through `--uitest-seed-dashboard`.
/// No test here sends a mutation to a real server. The fake recreates an
/// updated container as `<id>-updated`, as Docker gives a recreated container
/// a new ID, and that ID change is what these tests exist to cover: a screen
/// that held the old ID must stay on the container.
///
/// The row's swipe action is driven on iPhone only. In the iPad split view's
/// narrow list column a swipe commits the first trailing action (Restart)
/// instead of parking the row open (CLAUDE.md, "iPad"), so an iPad swipe test
/// would test the column width. `DockerStoreTests` covers the store path every
/// control shares.
@MainActor
final class ContainerUpdateUITests: XCTestCase {
  override func setUp() {
    continueAfterFailure = false
  }

  /// `state` sets `UITEST_DOCKER_STATE`: `update-fails` makes every update
  /// fail with a server message, and `many-updates` gives three containers an
  /// update, takes two seconds per update, and fails `uitest-container-5`.
  private func launchOnDocker(state: String? = nil) -> XCUIApplication {
    let app = XCUIApplication()
    app.launchArguments = ["--uitest-seed-dashboard"]
    if let state { app.launchEnvironment["UITEST_DOCKER_STATE"] = state }
    app.launch()
    useTabBarLayout(in: app)
    app.buttons["Docker"].firstMatch.tap()
    return app
  }

  /// `.firstMatch`: in the compact layout the row identifier sits on both the
  /// `NavigationLink` and the merged row inside it (see `DockerUITests.row`).
  private func row(_ id: String, in app: XCUIApplication) -> XCUIElement {
    app.descendants(matching: .any).matching(identifier: "docker.row.\(id)").firstMatch
  }

  private func element(_ identifier: String, labelContains text: String, in app: XCUIApplication) -> XCUIElement {
    app.descendants(matching: .any)
      .matching(NSPredicate(format: "identifier == %@ AND label CONTAINS %@", identifier, text))
      .firstMatch
  }

  /// Opens `webtop` (`uitest-container-3`, the one fixture with an update)
  /// and confirms its update.
  private func updateWebtopFromItsDetailScreen(in app: XCUIApplication) {
    let webtop = row("uitest-container-3", in: app)
    XCTAssertTrue(webtop.waitForExistence(timeout: 10), "webtop never appeared")
    webtop.tap()
    XCTAssertTrue(app.navigationBars["webtop"].waitForExistence(timeout: 5), "webtop's detail never opened")
    XCTAssertTrue(
      app.descendants(matching: .any)["containerDetail.updateNotice"].exists,
      "webtop's detail did not mark the update")

    let update = app.buttons["containerDetail.updateButton"]
    XCTAssertTrue(update.waitForExistence(timeout: 5), "the detail screen offered no Update")
    update.tap()

    // The confirmation, not the update itself: nothing runs until this tap.
    XCTAssertTrue(app.staticTexts["Update webtop?"].waitForExistence(timeout: 5), "Update asked for no confirmation")
    dialogButton("Update", in: app).tap()
  }

  /// The recreated container has a new ID. The detail screen holds the old
  /// one, and must stay on the container rather than show "Container Not
  /// Found". The update marker goes, and the list shows the new row.
  func testUpdatingFromTheDetailScreenKeepsItOpenAndClearsTheMarker() {
    let app = launchOnDocker()
    updateWebtopFromItsDetailScreen(in: app)

    XCTAssertTrue(
      element("containerDetail.updateResult", labelContains: "Updated webtop.", in: app)
        .waitForExistence(timeout: 10),
      "the detail screen showed no result for the update")
    XCTAssertTrue(app.navigationBars["webtop"].exists, "the detail screen left webtop after its ID changed")
    XCTAssertFalse(
      app.staticTexts["Container Not Found"].exists, "the detail screen lost the container after its ID changed")
    XCTAssertFalse(
      app.descendants(matching: .any)["containerDetail.updateNotice"].exists,
      "the update marker stayed after the update")
    XCTAssertFalse(app.buttons["containerDetail.updateButton"].exists, "Update was still offered after the update")

    if UIDevice.current.userInterfaceIdiom != .pad { tapBack(in: app) }
    let updated = row("uitest-container-3-updated", in: app)
    XCTAssertTrue(updated.waitForExistence(timeout: 5), "the list never showed the recreated container")
    XCTAssertFalse(row("uitest-container-3", in: app).exists, "the list still shows the old container")
    XCTAssertFalse(
      app.descendants(matching: .any)["docker.row.uitest-container-3-updated.updateBadge"].exists,
      "the recreated container still carries the Update badge")
    XCTAssertTrue(
      element("docker.updateReport", labelContains: "Updated webtop.", in: app).exists,
      "the list showed no result for the update")
  }

  /// "Update All" asks first, shows "N of M" while it runs, carries on past a
  /// failed container, and reports the result.
  func testUpdateAllShowsProgressThenTheResult() {
    let app = launchOnDocker(state: "many-updates")
    XCTAssertTrue(row("uitest-container-1", in: app).waitForExistence(timeout: 10), "the list never loaded")

    let updateAll = app.buttons["docker.updateAll"]
    XCTAssertTrue(updateAll.waitForExistence(timeout: 5), "no Update All with three updates available")
    updateAll.tap()

    // The toolbar button carries the same label; `dialogButton` skips it.
    let confirm = dialogButton("Update All", in: app)
    XCTAssertTrue(confirm.waitForExistence(timeout: 5), "Update All asked for no confirmation")
    XCTAssertTrue(app.staticTexts["Update 3 containers?"].exists, "the confirmation did not count the containers")
    confirm.tap()

    XCTAssertTrue(
      element("docker.updateProgress", labelContains: "of 3", in: app).waitForExistence(timeout: 5),
      "Update All showed no progress")
    XCTAssertFalse(updateAll.isEnabled, "Update All stayed enabled while it ran")

    XCTAssertTrue(
      element("docker.updateReport", labelContains: "Updated 2 of 3 containers.", in: app)
        .waitForExistence(timeout: 20),
      "Update All reported no result")
    XCTAssertTrue(
      element("docker.updateReport", labelContains: "Couldn't update emby.", in: app).exists,
      "the result did not name the container that failed")
    XCTAssertFalse(app.descendants(matching: .any)["docker.updateProgress"].exists, "the progress stayed after the run")

    XCTAssertTrue(row("uitest-container-1-updated", in: app).exists, "code-server was not recreated")
    XCTAssertTrue(row("uitest-container-3-updated", in: app).exists, "webtop was not recreated")
    XCTAssertTrue(
      app.descendants(matching: .any)["docker.row.uitest-container-5.updateBadge"].exists,
      "emby's update failed, so it must still show its badge")

    app.buttons["docker.updateReport.dismiss"].tap()
    XCTAssertFalse(
      app.descendants(matching: .any)["docker.updateReport"].waitForExistence(timeout: 2),
      "Dismiss left the result on screen")
  }

  /// The row's trailing swipe offers Update for a container with one. iPhone
  /// only: see this class's doc comment for the iPad split column.
  ///
  /// A partial drag, not `swipeLeft()`: a full swipe commits the first
  /// trailing action, which is Restart.
  func testRowSwipeUpdatesTheContainer() throws {
    try XCTSkipIf(UIDevice.current.userInterfaceIdiom == .pad, "a swipe in the split column commits Restart")
    let app = launchOnDocker()
    let webtop = row("uitest-container-3", in: app)
    XCTAssertTrue(webtop.waitForExistence(timeout: 10), "webtop never appeared")

    let update = app.buttons.matching(
      NSPredicate(format: "identifier == 'docker.swipe.update' OR label == 'Update'")
    ).firstMatch
    // A drag that ends early can fall short of opening the row. Try twice.
    for _ in 0..<2 where !update.exists {
      webtop.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5))
        .press(forDuration: 0.05, thenDragTo: webtop.coordinate(withNormalizedOffset: CGVector(dx: 0.45, dy: 0.5)))
      _ = update.waitForExistence(timeout: 2)
    }
    XCTAssertTrue(update.exists, "the row's swipe offered no Update")
    XCTAssertFalse(app.staticTexts["Restart webtop?"].exists, "the drag committed Restart")
    update.tap()

    XCTAssertTrue(
      app.staticTexts["Update webtop?"].waitForExistence(timeout: 5), "the swipe's Update asked for no confirmation")
    dialogButton("Update", in: app).tap()

    XCTAssertTrue(
      element("docker.updateReport", labelContains: "Updated webtop.", in: app).waitForExistence(timeout: 10),
      "the list showed no result for the update")
    XCTAssertTrue(row("uitest-container-3-updated", in: app).exists, "the list never showed the recreated container")
  }

  /// A failed update shows the server's own message, and the container keeps
  /// its update marker.
  func testAFailedUpdateShowsTheServerMessage() {
    let app = launchOnDocker(state: "update-fails")
    updateWebtopFromItsDetailScreen(in: app)

    XCTAssertTrue(
      element("containerDetail.updateResult", labelContains: "Error pulling image: manifest unknown", in: app)
        .waitForExistence(timeout: 10),
      "the server's error message never reached the detail screen")
    XCTAssertTrue(
      app.descendants(matching: .any)["containerDetail.updateNotice"].exists,
      "a failed update cleared the update marker")
    XCTAssertTrue(app.buttons["containerDetail.updateButton"].exists, "a failed update stopped offering Update")
  }

  /// After a client timeout the server may still pull, so the container is
  /// not offered a second update: the detail row says so and is off, and
  /// Update All goes away with no other container to update.
  func testATimedOutUpdateIsNotOfferedAgain() {
    let app = launchOnDocker(state: "update-times-out")
    updateWebtopFromItsDetailScreen(in: app)

    XCTAssertTrue(
      element("containerDetail.updateResult", labelContains: "still updating on the server", in: app)
        .waitForExistence(timeout: 10),
      "the detail screen showed no result for the timed-out update")
    let update = app.buttons["containerDetail.updateButton"]
    XCTAssertTrue(update.waitForExistence(timeout: 5), "the Update row disappeared")
    XCTAssertTrue(
      update.label.contains("Still updating on the server"), "the Update row read \"\(update.label)\"")
    XCTAssertFalse(update.isEnabled, "Update was offered again while the server still pulls")
    XCTAssertFalse(app.buttons["docker.updateAll"].exists, "Update All still offered the timed-out container")
  }
}
