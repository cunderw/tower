import XCTest

extension XCTestCase {
  /// The navigation bar's back button, found by identity and never by index.
  ///
  /// `navigationBars` spans both split-view columns on iPad, so `firstMatch` or
  /// `element(boundBy: 0)` returns a leading-column toolbar button such as
  /// *Add Service*, and a toolbar `Menu` can come first on any device
  /// (CLAUDE.md, "`navigationBars.buttons` by index is not "back" on iPad").
  /// The back button's identifier is `BackButton`, and the `Back` label covers
  /// a bar where the identifier is missing.
  @MainActor
  func backButton(in app: XCUIApplication) -> XCUIElement {
    app.navigationBars.buttons.matching(
      NSPredicate(format: "identifier == 'BackButton' OR label == 'Back'")
    ).firstMatch
  }

  /// Taps the back button, and fails at the caller's line when there is none.
  @MainActor
  func tapBack(
    in app: XCUIApplication,
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    let back = backButton(in: app)
    XCTAssertTrue(back.waitForExistence(timeout: 5), "no back button", file: file, line: line)
    back.tap()
  }
}
