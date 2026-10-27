import UIKit
import XCTest

/// The Services hub tab, driven against `UITestServices`' seeded
/// directory and `FakeServiceStatusChecker`.
@MainActor
final class ServicesHubUITests: XCTestCase {
  private enum Seed {
    static let radarr = "A0000000-0000-0000-0000-000000000001"
    static let sonarr = "A0000000-0000-0000-0000-000000000002"
    static let nzbget = "A0000000-0000-0000-0000-000000000003"
    static let tautulli = "A0000000-0000-0000-0000-000000000004"
    static let prowlarr = "A0000000-0000-0000-0000-000000000005"
  }

  override func setUp() {
    super.setUp()
    continueAfterFailure = false
  }

  /// Puts the iPad back on the tab bar.
  ///
  /// This class is the only one that shows the sidebar deliberately, and
  /// iPadOS remembers that choice in the *simulator* — so it outlives the app,
  /// the class, and the whole run. Left on, it makes "Services" ambiguous for
  /// every later class (tab, and collapsible section header), which makes
  /// tests pass alone and fail in the suite. Cleaning up here
  /// is the fix; the per-class `useTabBarLayout` calls are the backup, for
  /// when a test fails before its own cleanup.
  /// `async throws`, not the plain form: the synchronous `tearDown()` is
  /// nonisolated, so hopping to this `@MainActor` class's helper from it is a
  /// Swift 6 data-race error rather than a warning. The async overload runs on
  /// the class's own actor.
  override func tearDown() async throws {
    useTabBarLayout(in: XCUIApplication())
    try await super.tearDown()
  }

  private func launchOnServices(state: String? = nil) -> XCUIApplication {
    let app = XCUIApplication()
    app.launchArguments = ["--uitest-seed-dashboard"]
    if let state { app.launchEnvironment["UITEST_SERVICES_STATE"] = state }
    app.launch()
    app.buttons["Services"].firstMatch.tap()
    return app
  }

  private func row(_ id: String, in app: XCUIApplication) -> XCUIElement {
    app.descendants(matching: .any).matching(identifier: "services.row.\(id)").firstMatch
  }

  // MARK: - The tab itself

  func testServicesTabJoinsTheFourUnraidTabsWithoutDisturbingThem() {
    let app = XCUIApplication()
    app.launchArguments = ["--uitest-seed-dashboard"]
    app.launch()

    for tab in ["Dashboard", "Docker", "VMs", "Shares", "Services"] {
      XCTAssertTrue(
        app.buttons[tab].firstMatch.waitForExistence(timeout: 10),
        "the \(tab) tab is missing")
    }

    // The four Unraid tabs still open onto their own content, not the hub's.
    app.buttons["Docker"].firstMatch.tap()
    XCTAssertTrue(
      app.descendants(matching: .any).matching(identifier: "tab.docker.content")
        .firstMatch.waitForExistence(timeout: 10))

    app.buttons["Services"].firstMatch.tap()
    XCTAssertTrue(
      app.descendants(matching: .any).matching(identifier: "tab.services.content")
        .firstMatch.waitForExistence(timeout: 10))
  }

  // MARK: - Rows and grouping

  func testEveryEnabledInstanceIsListed() {
    let app = launchOnServices()

    for id in [Seed.radarr, Seed.sonarr, Seed.nzbget, Seed.tautulli] {
      XCTAssertTrue(
        row(id, in: app).waitForExistence(timeout: 10),
        "services.row.\(id) never appeared")
    }
  }

  func testDisabledInstancesAreHidden() {
    // Prowlarr is configured and disabled. It must not appear — and neither
    // must its category header, since it is that category's only member.
    let app = launchOnServices()
    XCTAssertTrue(row(Seed.radarr, in: app).waitForExistence(timeout: 10))

    XCTAssertFalse(row(Seed.prowlarr, in: app).exists)
    XCTAssertFalse(app.staticTexts["Requests & indexers"].exists)
  }

  func testRowsAreGroupedIntoServiceCategories() {
    let app = launchOnServices()
    XCTAssertTrue(row(Seed.radarr, in: app).waitForExistence(timeout: 10))

    for header in ["Media management", "Downloads", "Monitoring"] {
      XCTAssertTrue(
        app.staticTexts[header].waitForExistence(timeout: 5),
        "the \(header) section header is missing")
    }
  }

  // MARK: - Status

  func testARejectedKeyAndAnUnreachableHostReadDifferently() {
    // The whole point of three states rather than two: these two rows must not
    // say the same thing, because their recoveries are different screens.
    let app = launchOnServices()
    let sonarr = row(Seed.sonarr, in: app)
    let nzbget = row(Seed.nzbget, in: app)
    XCTAssertTrue(sonarr.waitForExistence(timeout: 10))

    XCTAssertTrue(waitForLabel(sonarr, containing: "Credentials rejected"))
    XCTAssertTrue(waitForLabel(nzbget, containing: "Unreachable"))
    XCTAssertFalse(sonarr.label.contains("Unreachable"))
  }

  func testASlowServiceDoesNotHoldUpTheHealthyRows() {
    // NZBGet's check takes five seconds. Radarr's row has to be showing
    // "Connected" well before that lands — a hub that awaited every check
    // together would leave all four rows saying "Checking…" for the full five.
    //
    // The window is deliberately wide (five seconds against a check that
    // resolves immediately): the time XCUITest itself spends launching and
    // querying eats most of a two-second margin, and the "still checking" half
    // then fails. The wide delay keeps the assertion about Tower rather than
    // about how fast the test harness is today.
    let app = launchOnServices()
    let radarr = row(Seed.radarr, in: app)
    XCTAssertTrue(radarr.waitForExistence(timeout: 10))

    XCTAssertTrue(
      waitForLabel(radarr, containing: "Connected", timeout: 3),
      "Radarr was still unresolved while the slow service was checking")
    XCTAssertTrue(row(Seed.nzbget, in: app).label.contains("Checking"))
  }

  // MARK: - Empty state

  func testTheEmptyStateRendersWhenNothingIsConfigured() {
    let app = launchOnServices(state: "empty")

    XCTAssertTrue(
      app.descendants(matching: .any).matching(identifier: "services.empty")
        .firstMatch.waitForExistence(timeout: 10))
    XCTAssertFalse(row(Seed.radarr, in: app).exists)
  }

  // MARK: - Detail

  func testARowOpensThatInstancesScreen() {
    // Tautulli, not Radarr: a Radarr row opens the *arr shell (which
    // `ArrShellUITests` covers). The UI-test factory returns `nil` for
    // Tautulli, so this exercises the fallback configuration screen.
    let app = launchOnServices()
    let tautulli = row(Seed.tautulli, in: app)
    XCTAssertTrue(tautulli.waitForExistence(timeout: 10))

    tautulli.tap()

    XCTAssertTrue(
      app.descendants(matching: .any).matching(identifier: "services.detail")
        .firstMatch.waitForExistence(timeout: 10))
    XCTAssertTrue(app.navigationBars["Tautulli"].waitForExistence(timeout: 5))
  }

  // MARK: - iPad

  func testTheSidebarListsEachInstanceByName() throws {
    // Regular width only: the per-instance section is a sidebar affordance and
    // has nowhere to live in a tab bar. Runs on the iPad simulator only — a
    // run targets it with `--simulator-name "Tower iPad"`.
    try XCTSkipUnless(
      UIDevice.current.userInterfaceIdiom == .pad, "the sidebar section is iPad-only")
    // Deliberately *not* via the Services tab. With the sidebar showing there
    // are two things labelled "Services" — the hub tab and the section header —
    // and tapping the header collapses the section, which fails this test
    // whenever it runs after one that has already opened the sidebar.
    let app = XCUIApplication()
    app.launchArguments = ["--uitest-seed-dashboard"]
    app.launch()
    showSidebar(in: app)

    for name in ["Radarr", "Sonarr 4K", "NZBGet", "Tautulli"] {
      XCTAssertTrue(
        sidebarEntry(name, in: app).waitForExistence(timeout: 10),
        "the sidebar has no entry for \(name)")
    }
    // Disabled instances are absent from the sidebar too, not just the hub.
    XCTAssertFalse(sidebarEntry("Prowlarr", in: app).exists)
  }

  func testTappingASidebarInstanceOpensItDirectly() throws {
    // "One tap from anywhere": the tap starts on the Dashboard tab, not on the
    // hub, and lands on that instance's screen without going through it.
    try XCTSkipUnless(
      UIDevice.current.userInterfaceIdiom == .pad, "the sidebar section is iPad-only")
    let app = XCUIApplication()
    app.launchArguments = ["--uitest-seed-dashboard"]
    app.launch()
    showSidebar(in: app)
    let tautulli = sidebarEntry("Tautulli", in: app)
    XCTAssertTrue(tautulli.waitForExistence(timeout: 10))

    tautulli.tap()

    XCTAssertTrue(
      app.descendants(matching: .any).matching(identifier: "services.detail")
        .firstMatch.waitForExistence(timeout: 10))
    XCTAssertTrue(app.navigationBars["Tautulli"].waitForExistence(timeout: 5))
  }

  /// iPadOS opens `.sidebarAdaptable` on the *top tab bar*, not the sidebar —
  /// the sidebar (and with it the Services section) is behind this toggle.
  /// Confirmed from the real accessibility tree, which is also where these
  /// identifiers came from.
  ///
  /// **Idempotent on purpose.** iPadOS remembers the tab-bar/sidebar choice
  /// across app launches, so an unconditional tap flips whatever the *previous
  /// test* left behind: a test that passes in isolation fails in the full
  /// class, because the sidebar is already showing and the tap hides it again.
  private func showSidebar(in app: XCUIApplication) {
    if app.buttons["Hide Sidebar"].firstMatch.exists { return }
    let toggle = app.buttons["ToggleSideBar"].firstMatch
    XCTAssertTrue(toggle.waitForExistence(timeout: 10), "no sidebar toggle in the tab bar")
    toggle.tap()
  }

  /// Sidebar rows are `Cell`s whose *identifier* is the SF Symbol name and
  /// whose label is the instance name, so they are matched on the label.
  private func sidebarEntry(_ name: String, in app: XCUIApplication) -> XCUIElement {
    app.cells.matching(NSPredicate(format: "label == %@", name)).firstMatch
  }

  /// Waits for an element's label to contain `text` — the status lines arrive
  /// asynchronously, one per check.
  ///
  /// An `XCTWaiter` over a predicate rather than a hand-rolled poll: a `while`
  /// loop re-reading `.label` spins on the accessibility server as fast as it
  /// can answer, which competes with the app's own main thread for exactly the
  /// updates the test is waiting on.
  private func waitForLabel(
    _ element: XCUIElement, containing text: String, timeout: TimeInterval = 10
  ) -> Bool {
    let predicate = NSPredicate(format: "label CONTAINS %@", text)
    let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
    return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
  }
}
