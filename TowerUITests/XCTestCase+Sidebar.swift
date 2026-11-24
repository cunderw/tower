import XCTest

extension XCTestCase {
  /// Puts the iPad back on the **top tab bar** before a test navigates by tab.
  ///
  /// iPadOS opens `.sidebarAdaptable` on the tab bar, but it remembers whichever
  /// the user last chose — and that memory survives app launches *and whole
  /// test runs*, because it lives in the simulator rather than the app. So a
  /// class that shows the sidebar deliberately (`ServicesHubUITests`) leaves
  /// every later class, and every later run, starting in the sidebar layout.
  ///
  /// That matters because with the sidebar showing there are **two elements
  /// labelled "Services"** — the tab and the collapsible section header — and
  /// `app.buttons["Services"].firstMatch` finds the header, whose tap collapses
  /// the section. The rows stay in the accessibility tree while being nowhere on
  /// screen, so the failure reads as "the row exists but is never hittable"
  /// several steps later.
  ///
  /// Idempotent, and a no-op on iPhone, where there is no toggle at all.
  ///
  /// **The toggle's identifier changes case with its state** — `ToggleSideBar`
  /// while the tab bar is showing, `ToggleSidebar` (lowercase b) once the
  /// sidebar is, as a real accessibility snapshot shows. Guarding on one state
  /// and then tapping the other state's identifier silently does nothing, so
  /// this addresses the button by the identifier it carries in the state we
  /// want to leave.
  ///
  /// Not by its label, "Hide Sidebar": the Services hub's split view has a
  /// column toggle with that label too, and no identifier. A label query taps
  /// the hub's toggle when the tab bar is already showing.
  @MainActor
  func useTabBarLayout(in app: XCUIApplication) {
    let hide = tabViewSidebarToggle(identifier: "ToggleSidebar", in: app)
    guard hide.exists else { return }
    hide.tap()
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
  @MainActor
  func showSidebar(in app: XCUIApplication) {
    if tabViewSidebarToggle(identifier: "ToggleSidebar", in: app).exists { return }
    let toggle = tabViewSidebarToggle(identifier: "ToggleSideBar", in: app)
    XCTAssertTrue(toggle.waitForExistence(timeout: 10), "no sidebar toggle in the tab bar")
    toggle.tap()
  }

  /// The `TabView`'s own sidebar toggle in one of its two states, matched on the
  /// identifier with a case-sensitive predicate, because the two states differ
  /// only in the case of one letter. See `useTabBarLayout(in:)`.
  @MainActor
  private func tabViewSidebarToggle(identifier: String, in app: XCUIApplication) -> XCUIElement {
    app.buttons.matching(NSPredicate(format: "identifier == %@", identifier)).firstMatch
  }
}
