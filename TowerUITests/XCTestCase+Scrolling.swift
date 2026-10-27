import XCTest

extension XCTestCase {
  /// Scrolls until `element` exists, up to `attempts` swipes.
  ///
  /// **Why `exists` and not `isHittable`.** A SwiftUI `List` doesn't render rows
  /// it hasn't scrolled to, so a row below the fold is genuinely *absent* from the
  /// accessibility tree — `waitForExistence` times out rather than finding a
  /// hidden element, which reads like a missing feature.
  ///
  /// This bites hardest on iPad, where a sheet is a **centered form sheet** —
  /// narrower *and shorter* than the device, so more of a list sits below the fold
  /// than on an iPhone. Settings' theme picker and Sign Out are both below it there.
  @MainActor
  @discardableResult
  func scrollTo(
    _ element: XCUIElement,
    in app: XCUIApplication,
    attempts: Int = 5
  ) -> Bool {
    var remaining = attempts
    while !element.exists, remaining > 0 {
      app.swipeUp()
      remaining -= 1
    }
    return element.exists
  }

  /// Scrolls until `element` can actually be *tapped*, in both directions.
  ///
  /// `scrollTo` stops at `exists`, and that is not the same thing. A SwiftUI
  /// `List` keeps rows it has already rendered in the accessibility tree after
  /// they scroll off screen, so an element the list has passed reports
  /// `exists == true` from off screen — and `tap()` then synthesises a touch at
  /// coordinates outside the window, which lands on nothing and reports
  /// success. On iPad, that is how a tap in the hub's list column lands on
  /// empty space.
  ///
  /// Searches forward first, then back, because a list's scroll position is
  /// whatever the previous test or screen left behind.
  /// **`within` matters on iPad and nowhere else.** `app.swipeUp()` swipes at
  /// the centre of the *screen*, which in a split view is the detail column —
  /// so a list in the narrow leading column never moves, and the loop spins
  /// until it gives up. Passing an element inside the column scrolls that
  /// column instead. On iPhone the two are the same gesture.
  @MainActor
  @discardableResult
  func scrollUntilHittable(
    _ element: XCUIElement,
    in app: XCUIApplication,
    within scroller: XCUIElement? = nil,
    attempts: Int = 8
  ) -> Bool {
    if element.exists, element.isHittable { return true }
    let target = scroller ?? app
    for _ in 0..<attempts {
      target.swipeUp()
      if element.exists, element.isHittable { return true }
    }
    for _ in 0..<(attempts * 2) {
      target.swipeDown()
      if element.exists, element.isHittable { return true }
    }
    return element.exists && element.isHittable
  }
}
