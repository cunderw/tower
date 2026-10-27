import UIKit
import XCTest

/// iPad only: an *arr screen open in the hub's detail column, then a second one
/// opened from the sidebar's Services section. Two live `ArrServiceScreen`s
/// must not freeze the app.
@MainActor
final class SidebarServiceHangUITests: XCTestCase {
  private let radarr = "D0000000-0000-0000-0000-000000000001"

  override func setUp() {
    super.setUp()
    continueAfterFailure = false
  }

  override func tearDown() async throws {
    useTabBarLayout(in: XCUIApplication())
    try await super.tearDown()
  }

  func testOpeningASidebarServiceBesideTheHubDetailStaysResponsive() throws {
    try XCTSkipUnless(
      UIDevice.current.userInterfaceIdiom == .pad, "the sidebar section is iPad-only")
    let app = XCUIApplication()
    app.launchArguments = ["--uitest-reset-credentials"]
    app.launch()
    let demo = app.buttons["connect.demo"]
    XCTAssertTrue(demo.waitForExistence(timeout: 15))
    demo.tap()

    useTabBarLayout(in: app)
    app.buttons["Services"].firstMatch.tap()
    let row = app.descendants(matching: .any).matching(identifier: "services.row.\(radarr)")
      .firstMatch
    XCTAssertTrue(row.waitForExistence(timeout: 10))
    row.tap()
    XCTAssertTrue(
      app.descendants(matching: .any).matching(identifier: "arr.shell").firstMatch
        .waitForExistence(timeout: 15))

    // Not "Radarr": the hub detail already shows it, so its navigation bar
    // would match whether or not the sidebar tap worked.
    for name in ["Radarr 4K", "Lidarr", "Bazarr"] {
      // In portrait the sidebar is an overlay that closes on every selection.
      // Not keyed on "Hide Sidebar": the hub's split view has a button with
      // that label too.
      let entry = app.cells.matching(NSPredicate(format: "label == %@", name)).firstMatch
      if !entry.exists {
        let toggle = app.buttons["ToggleSideBar"].firstMatch
        XCTAssertTrue(toggle.waitForExistence(timeout: 10))
        toggle.tap()
      }
      XCTAssertTrue(entry.waitForExistence(timeout: 10), "no sidebar entry for \(name)")
      entry.tap()
      XCTAssertTrue(
        app.navigationBars[name].waitForExistence(timeout: 15), "\(name) never appeared")
    }
  }
}
