import XCTest

extension XCTestCase {
  /// Taps `element` and waits for it to actually gain keyboard focus before
  /// typing into it, rather than assuming the tap alone established focus.
  ///
  /// A tap registers as a touch immediately, but the responder chain accepting
  /// keyboard input can lag a run loop turn or two behind it. Call `typeText` in
  /// that window and XCTest fails event synthesis with "Neither element nor any
  /// descendant has keyboard focus."
  ///
  /// `hasKeyboardFocus` isn't part of the public `XCUIElementAttributes`
  /// protocol (only `hasFocus` is, and that's UI/VoiceOver focus, not text input
  /// focus). But it is the exact attribute XCTest's own event synthesizer checks
  /// before dispatching a keyboard event — confirmed by grepping the installed
  /// XCUIAutomation binary, where the literal predicate `"hasKeyboardFocus == 1"`
  /// is embedded verbatim, and by the failure text itself using that same
  /// phrase. It's reachable as an NSPredicate key against the element
  /// (`XCUIElement` resolves attribute predicates via the accessibility
  /// snapshot, not strict KVC), so an `XCTNSPredicateExpectation` on it waits on
  /// the real condition rather than a fixed delay.
  ///
  /// **Not a fix for every focus failure.** There are two unrelated causes of
  /// "never gained keyboard focus after tap": this race, and a wedged simulator
  /// pasteboard daemon that hangs the app inside `becomeFirstResponder`. No wait
  /// helps the second — only erasing the simulator does. If this assertion
  /// starts failing across every typing test at once, that's the one you're
  /// looking at (CLAUDE.md, "When a UI test cannot type, erase the simulator
  /// before you suspect the test").
  ///
  /// `@MainActor` because XCUITest's API is: a helper inside a `@MainActor`
  /// test class inherits that isolation, and an extension on `XCTestCase`
  /// doesn't. Without it Swift 6 warns on `tap()` and `typeText()` — caught by
  /// the warnings gate, not by the passing test run.
  @MainActor
  func type(
    _ text: String,
    into element: XCUIElement,
    timeout: TimeInterval = 5,
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    element.tap()
    let hasKeyboardFocus = NSPredicate(format: "hasKeyboardFocus == true")
    let focused = XCTNSPredicateExpectation(predicate: hasKeyboardFocus, object: element)
    XCTAssertEqual(
      XCTWaiter().wait(for: [focused], timeout: timeout), .completed,
      "\(element) never gained keyboard focus after tap",
      file: file, line: line
    )
    element.typeText(text)
  }

  /// Replaces whatever `element` holds with `text`, without the edit menu.
  ///
  /// The press-and-"Select All" route does not work on the iOS 27 runtime:
  /// a long press on the URL field shows the loupe and then no menu,
  /// so new text is appended to the old. Deleting key by key does not
  /// work either, because a tap puts the caret at a word boundary, not at the
  /// end. A triple tap selects the whole line, and typing replaces it. The
  /// result is checked, so a missed selection fails here and not later.
  @MainActor
  func replaceText(
    in element: XCUIElement,
    with text: String,
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    let current = (element.value as? String) ?? ""
    let hasText = !current.isEmpty && current != element.placeholderValue
    type("", into: element, file: file, line: line)
    if hasText { element.tap(withNumberOfTaps: 3, numberOfTouches: 1) }
    element.typeText(text)
    XCTAssertEqual(
      element.value as? String, text, "the old text was not fully replaced",
      file: file, line: line)
  }
}
