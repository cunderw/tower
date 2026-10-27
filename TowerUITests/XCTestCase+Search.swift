import XCTest

extension XCTestCase {
  /// Finds a `.searchable` field by its prompt, revealing it first if the
  /// platform hid it.
  ///
  /// **iPad collapses the search field into a button.** In a `NavigationStack` on
  /// iPadOS the field lives in the navigation bar and is not present as a
  /// `SearchField` until something taps its "Search" button — so a test written
  /// against iPhone's always-visible field fails on iPad with "search field never
  /// appeared". The app is not broken there; the affordance is just one tap
  /// further away, exactly as a user experiences it.
  ///
  /// On iPhone the field is already there and the reveal step is skipped, so the
  /// same call works on both.
  @MainActor
  func searchField(
    prompt: String,
    in app: XCUIApplication,
    timeout: TimeInterval = 5
  ) -> XCUIElement {
    let field = app.searchFields.matching(NSPredicate(format: "label == %@", prompt)).firstMatch
    if field.waitForExistence(timeout: timeout) { return field }

    // Reveal it. The button is labelled "Search" rather than carrying the prompt.
    let searchButton = app.buttons["Search"].firstMatch
    if searchButton.exists {
      searchButton.tap()
    }
    return field
  }
}
