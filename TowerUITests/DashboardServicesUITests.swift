import XCTest

/// Proves `ServicesCard`'s rows actually switch the tab bar — the one thing a
/// static screenshot can't verify.
///
/// Uses XCUITest's own `.tap()`: real event synthesis through the on-device
/// XCTest runner, so it proves the tap-to-navigate behaviour rather than just
/// that the row renders.
///
/// `idb ui tap` exits 0 and does nothing on macOS 27, because `idb-companion`
/// 1.1.8 duplicates the `FBProcess` class the OS now defines. idb's reads still
/// work. For exploratory taps, AXe (through XcodeBuildMCP) works.
@MainActor
final class DashboardServicesUITests: XCTestCase {
  private func launchOnDashboard() -> XCUIApplication {
    let app = XCUIApplication()
    // See `ShellUITests` — seeds a fake `Server` and `FakeSystemRepository`
    // so this reaches `RootView` with no keychain access and no Unraid
    // server.
    app.launchArguments = ["--uitest-seed-dashboard"]
    app.launch()
    return app
  }

  func testTappingDockerRowSwitchesToDockerTab() {
    let app = launchOnDashboard()

    let dockerRow = app.descendants(matching: .any).matching(identifier: "services.docker").firstMatch
    XCTAssertTrue(dockerRow.waitForExistence(timeout: 5), "services.docker row never appeared")
    XCTAssertEqual(dockerRow.label, "Docker, 14 of 16 running")

    dockerRow.tap()

    // `RootView` puts `tab.docker.content` on the Docker tab's `DockerListView`.
    let dockerContent = app.descendants(matching: .any)
      .matching(identifier: "tab.docker.content").firstMatch
    XCTAssertTrue(dockerContent.waitForExistence(timeout: 5), "tapping services.docker never switched to the Docker tab")
  }

  func testTappingVMsRowSwitchesToVMsTab() {
    let app = launchOnDashboard()

    let vmsRow = app.descendants(matching: .any).matching(identifier: "services.vms").firstMatch
    XCTAssertTrue(vmsRow.waitForExistence(timeout: 5), "services.vms row never appeared")
    XCTAssertEqual(vmsRow.label, "VMs, 2 of 3 running")

    vmsRow.tap()

    // `RootView` puts `tab.vms.content` on the VMs tab's `VMListView`.
    let vmsContent = app.descendants(matching: .any)
      .matching(identifier: "tab.vms.content").firstMatch
    XCTAssertTrue(vmsContent.waitForExistence(timeout: 5), "tapping services.vms never switched to the VMs tab")
  }

  func testTappingSharesRowSwitchesToSharesTab() {
    let app = launchOnDashboard()

    let sharesRow = app.descendants(matching: .any).matching(identifier: "services.shares").firstMatch
    XCTAssertTrue(sharesRow.waitForExistence(timeout: 5), "services.shares row never appeared")
    // Shares shows the count only — no aggregated usage line:
    // `share.used`/`free` describe the pool a share lives on, not the share
    // itself, so summing them across shares is meaningless and is never
    // rendered here.
    XCTAssertEqual(sharesRow.label, "Shares, 9 shares")

    sharesRow.tap()

    // `RootView` puts `tab.shares.content` on the Shares tab's `ShareListView`.
    let sharesContent = app.descendants(matching: .any)
      .matching(identifier: "tab.shares.content").firstMatch
    XCTAssertTrue(sharesContent.waitForExistence(timeout: 5), "tapping services.shares never switched to the Shares tab")
  }
}
