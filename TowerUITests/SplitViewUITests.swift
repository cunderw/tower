import UIKit
import XCTest

/// The iPad two-column layout, and the iPhone push it must not have
/// changed.
///
/// **Both halves are asserted from the same file on purpose.** The claim is
/// "side by side in a regular width class, pushed in a compact one", and either
/// half alone is satisfiable by a regression in the other — a split view that
/// never collapses passes an iPad-only test, and a stack that never splits
/// passes an iPhone-only one. Each test skips on the idiom it doesn't
/// describe, so a run against the iPhone simulator covers the compact half
/// and a run against the iPad simulator covers the regular half (a run targets
/// it with `--simulator-name "Tower iPad"`).
///
/// `UIDevice.current` is the *runner's* device, which is the same simulator the
/// app is running on — the runner is an app installed alongside it.
@MainActor
final class SplitViewUITests: XCTestCase {
  override func setUp() {
    super.setUp()
    continueAfterFailure = false
  }

  private func launchOnDocker() -> XCUIApplication {
    let app = XCUIApplication()
    app.launchArguments = ["--uitest-seed-dashboard"]
    app.launch()
    app.buttons["Docker"].firstMatch.tap()
    return app
  }

  private func row(_ id: String, in app: XCUIApplication) -> XCUIElement {
    app.descendants(matching: .any).matching(identifier: "docker.row.\(id)").firstMatch
  }

  /// Queried through `descendants(matching: .any)` rather than `app.buttons`,
  /// like every other test that reaches this row: a `NavigationLink` inside a
  /// `List` does not reliably surface as a `Button` (see `ContainerLogsUITests`).
  private func viewLogs(in app: XCUIApplication) -> XCUIElement {
    app.descendants(matching: .any).matching(identifier: "containerDetail.viewLogsButton").firstMatch
  }

  // MARK: - Regular width

  /// The point of the split view: after selecting a container, the list and
  /// the detail are on screen *at the same time*. Asserting only that the
  /// detail appeared would also pass for a full-width push.
  func testIPadShowsTheListAndTheDetailAtOnce() throws {
    try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .pad, "regular width class only")
    let app = launchOnDocker()

    let firstContainer = row("uitest-container-1", in: app)
    XCTAssertTrue(firstContainer.waitForExistence(timeout: 10), "the container list never loaded")
    firstContainer.tap()

    XCTAssertTrue(
      viewLogs(in: app).waitForExistence(timeout: 10),
      "selecting a container never filled the detail column"
    )
    XCTAssertTrue(
      row("uitest-container-2", in: app).exists,
      "the list column disappeared when the detail was selected — this is a push, not a split view"
    )
  }

  /// Before anything is selected the detail column says so, rather than sitting
  /// empty. The placeholder is also what a store screenshot would capture if
  /// the tour forgot to select a row (see `ScreenshotTourUITests.selectOnIPad`).
  func testIPadDetailColumnStartsWithAPlaceholder() throws {
    try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .pad, "regular width class only")
    let app = launchOnDocker()

    XCTAssertTrue(row("uitest-container-1", in: app).waitForExistence(timeout: 10), "the list never loaded")
    XCTAssertTrue(
      app.descendants(matching: .any).matching(identifier: "docker.noSelection").firstMatch.exists,
      "an unselected detail column showed no placeholder"
    )
  }

  /// Selection survives a rebuild. Selection lives in `DockerListView`'s
  /// own `@State`, not inside the scaffold whose branch the width class picks,
  /// so tearing the layout down and rebuilding it must not reset it — here by
  /// leaving the tab and coming back, which rebuilds the whole tab body.
  ///
  /// **Rotation would be the closer analogue and is deliberately not used.**
  /// Setting `XCUIDevice.shared.orientation` makes every later test in the
  /// same iPad suite fail at launch with "Failed to tap … Button: No matches
  /// found". It also proves less than it appears to: a 13" iPad is a regular
  /// width class in *both* orientations, so rotating never crosses the branch
  /// this test exists to protect.
  func testIPadSelectionSurvivesLeavingAndReturningToTheTab() throws {
    try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .pad, "regular width class only")
    let app = launchOnDocker()

    let firstContainer = row("uitest-container-1", in: app)
    XCTAssertTrue(firstContainer.waitForExistence(timeout: 10), "the container list never loaded")
    firstContainer.tap()
    let logs = viewLogs(in: app)
    XCTAssertTrue(logs.waitForExistence(timeout: 10), "selecting a container never filled the detail column")

    app.buttons["VMs"].firstMatch.tap()
    XCTAssertTrue(
      app.descendants(matching: .any).matching(identifier: "vms.noSelection").firstMatch
        .waitForExistence(timeout: 10),
      "the VMs tab never came up"
    )
    app.buttons["Docker"].firstMatch.tap()

    XCTAssertTrue(
      logs.waitForExistence(timeout: 10),
      "coming back to the tab cleared the selection and left the detail column on its placeholder"
    )
  }

  // MARK: - Compact width

  /// The other half: iPhone still *pushes*, so the list is
  /// gone once the detail is up. A split view that failed to collapse would
  /// leave both on screen and fail here.
  func testIPhoneStillPushesTheDetailOverTheList() throws {
    try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .phone, "compact width class only")
    let app = launchOnDocker()

    let firstContainer = row("uitest-container-1", in: app)
    XCTAssertTrue(firstContainer.waitForExistence(timeout: 10), "the container list never loaded")
    firstContainer.tap()

    XCTAssertTrue(
      viewLogs(in: app).waitForExistence(timeout: 10),
      "tapping a container never pushed its detail screen"
    )
    XCTAssertFalse(
      row("uitest-container-2", in: app).isHittable,
      "the list was still on screen beside the detail on a compact width class"
    )
  }
}
