import XCTest

/// Proves `ContainerDetailView`'s "View Logs" row actually pushes
/// `ContainerLogsView` and that fetched lines render on screen — the thing a
/// static `#Preview` can't verify. It taps with XCUITest's own `.tap()`
/// because `idb ui tap` does nothing on macOS 27 (see
/// `DashboardServicesUITests`).
@MainActor
final class ContainerLogsUITests: XCTestCase {
  private func launchOnDocker() -> XCUIApplication {
    let app = XCUIApplication()
    // See `ShellUITests` — seeds a fake `Server` and `FakeDockerRepository`
    // (which answers `logs(id:tail:since:)` with two canned lines) so
    // this reaches the Docker tab with no keychain access and no
    // Unraid server.
    app.launchArguments = ["--uitest-seed-dashboard"]
    app.launch()
    app.buttons["Docker"].firstMatch.tap()
    return app
  }

  private func element(labelContains substring: String, in app: XCUIApplication) -> XCUIElement {
    app.descendants(matching: .any)
      .matching(NSPredicate(format: "label CONTAINS[c] %@", substring))
      .firstMatch
  }

  func testViewLogsPushesLogViewerAndRendersFetchedLines() {
    let app = launchOnDocker()

    let row = app.descendants(matching: .any).matching(identifier: "docker.row.uitest-container-1").firstMatch
    XCTAssertTrue(row.waitForExistence(timeout: 5), "docker.row.uitest-container-1 never appeared")
    row.tap()

    let viewLogsButton = app.descendants(matching: .any).matching(identifier: "containerDetail.viewLogsButton").firstMatch
    XCTAssertTrue(viewLogsButton.waitForExistence(timeout: 5), "View Logs row never appeared on the container detail screen")
    viewLogsButton.tap()

    XCTAssertTrue(app.navigationBars["Logs"].waitForExistence(timeout: 5), "tapping View Logs never pushed the log viewer")
    XCTAssertTrue(element(labelContains: "Starting up", in: app).waitForExistence(timeout: 5), "fetched log line missing from the log viewer")
    XCTAssertTrue(element(labelContains: "Ready.", in: app).exists, "second fetched log line missing from the log viewer")
  }
}
