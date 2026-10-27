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
  /// sidebar is, as a real accessibility snapshot shows. Guarding on the label
  /// and then tapping the *tab-bar* identifier silently does nothing, so this
  /// addresses the button by the label it carries in the state we want to
  /// leave: "Hide Sidebar".
  @MainActor
  func useTabBarLayout(in app: XCUIApplication) {
    let hide = app.buttons["Hide Sidebar"].firstMatch
    guard hide.exists else { return }
    hide.tap()
  }
}
