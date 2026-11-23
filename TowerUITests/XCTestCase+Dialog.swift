import XCTest

extension XCTestCase {
  /// A confirmation dialog's button labelled `label`.
  ///
  /// The control that opened the dialog often carries the same label
  /// ("Update" on the detail row and in the row swipe, "Update All" in the
  /// toolbar, "Cancel Check" on the parity card, "Stop Array" on the array
  /// card) and stays in the tree behind the dialog, so a plain
  /// `app.buttons[label]` can resolve to it. This skips every button that has
  /// one of those identifiers.
  @MainActor
  func dialogButton(_ label: String, in app: XCUIApplication) -> XCUIElement {
    app.buttons.matching(
      NSPredicate(
        format: "label == %@ AND NOT (identifier BEGINSWITH 'containerDetail.') "
          + "AND NOT (identifier BEGINSWITH 'parity.action.') "
          + "AND NOT (identifier BEGINSWITH 'array.action.') "
          + "AND identifier != 'docker.swipe.update' AND identifier != 'docker.updateAll'",
        label)
    ).firstMatch
  }
}
