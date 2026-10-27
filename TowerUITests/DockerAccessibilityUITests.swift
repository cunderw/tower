import XCTest

/// Confirms `ContainerRow` merges into one accessibility element. Without
/// `.accessibilityElement(children: .combine)`, `StateDot`, the name, the
/// subtitle, and the update badge are four separate VoiceOver stops per
/// row, so a long container list takes several swipes per row. This reads
/// `label` straight off the row element, the same technique
/// `DashboardAccessibilityUITests` uses to prove a merge actually reached
/// the accessibility tree rather than trusting a code read.
///
/// Nothing here needs to tap a container row itself — only the Docker tab
/// button, which (like `ShellUITests`) works because XCUITest uses real
/// on-device event synthesis rather than `idb`, whose taps do nothing on
/// macOS 27 (see `DashboardServicesUITests`).
@MainActor
final class DockerAccessibilityUITests: XCTestCase {
  private func launchOnDocker() -> XCUIApplication {
    let app = XCUIApplication()
    // See `ShellUITests` — seeds a fake `Server` and `FakeDockerRepository`
    // so this reaches the Docker tab with no keychain access and no Unraid
    // server.
    app.launchArguments = ["--uitest-seed-dashboard"]
    app.launch()
    app.buttons["Docker"].firstMatch.tap()
    return app
  }

  private func element(identifier: String, in app: XCUIApplication) -> XCUIElement {
    app.descendants(matching: .any).matching(identifier: identifier).firstMatch
  }

  /// `uitest-container-3` (`/webtop`, running, `isUpdateAvailable: true`) is
  /// the one fixture container that exercises every part of the merge at
  /// once: `StateDot`'s "Running", the name, the image, and the update
  /// badge, all read aloud as one label.
  func testRunningContainerWithUpdateReadsAsOneMergedLabel() {
    let app = launchOnDocker()

    let row = element(identifier: "docker.row.uitest-container-3", in: app)
    XCTAssertTrue(row.waitForExistence(timeout: 5), "docker.row.uitest-container-3 never appeared")
    XCTAssertEqual(row.label, "Running, webtop, linuxserver/webtop:latest, Update")
  }

  /// The exited fixture (`uitest-container-2`) is the case the merge has to
  /// get right: `subtitle` prefixes the state onto the image visually
  /// ("Exited · image") so a sighted user still sees it in text, not as
  /// colour alone, but merged naively that would make VoiceOver say the
  /// state twice — once from `StateDot`'s own label, once from `subtitle`'s
  /// text. This checks the state is announced once.
  func testExitedContainerDoesNotAnnounceStateTwice() {
    let app = launchOnDocker()

    let row = element(identifier: "docker.row.uitest-container-2", in: app)
    XCTAssertTrue(row.waitForExistence(timeout: 5), "docker.row.uitest-container-2 never appeared")
    XCTAssertEqual(row.label, "Exited, freshrss, linuxserver/freshrss:latest")
    XCTAssertEqual(
      row.label.components(separatedBy: "Exited").count - 1, 1,
      "state should be announced exactly once, got \"\(row.label)\""
    )
  }
}
