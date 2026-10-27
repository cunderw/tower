import XCTest

@MainActor
final class ConnectFlowUITests: XCTestCase {
  func testConnectScreenShowsFormFields() {
    let app = XCUIApplication()
    app.launchArguments = ["--uitest-reset-credentials"]
    app.launch()

    XCTAssertTrue(app.textFields["connect.url"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.secureTextFields["connect.apiKey"].exists)
    XCTAssertFalse(app.buttons["connect.submit"].isEnabled)
  }

  func testAddressPlaceholderIsATemplateNotSomebodysServer() {
    // The placeholder must not be a real, working LAN address. Asserting
    // the absence of a dotted quad rather than the exact template text, for the
    // same reason as `AppErrorTests`' companion check: the wording may change,
    // shipping someone's server as the example may not.
    //
    // This cannot see the other half of that rule — the accent tint iOS applies
    // to a placeholder that parses as a URL — because XCUITest exposes no
    // colour, so that half is checked by eye.
    let app = XCUIApplication()
    app.launchArguments = ["--uitest-reset-credentials"]
    app.launch()

    let field = app.textFields["connect.url"]
    XCTAssertTrue(field.waitForExistence(timeout: 5))
    let placeholder = field.placeholderValue ?? ""
    XCTAssertFalse(placeholder.isEmpty, "the address field lost its placeholder entirely")
    XCTAssertNil(
      placeholder.range(of: #"\d+\.\d+\.\d+\.\d+"#, options: .regularExpression),
      "the placeholder names a specific address: \(placeholder)"
    )
  }

  func testInvalidURLShowsAnError() {
    let app = XCUIApplication()
    app.launchArguments = ["--uitest-reset-credentials"]
    app.launch()

    type("192.0.2.10", into: app.textFields["connect.url"])
    type("abc", into: app.secureTextFields["connect.apiKey"])
    app.buttons["connect.submit"].tap()

    // A scheme-less host is rejected by `normalizedURL` before any network
    // call, so this must surface `.invalidServerURL`. Matched on the error
    // message text rather than an element type/identifier:
    // `.accessibilityElement(children: .combine)` on ConnectView's
    // ContentUnavailableView determines which underlying element type the
    // merged accessibility node surfaces as, and asserting a specific type
    // (`otherElements`) coupled the test to that incidental detail. Matching
    // the message still proves the right error is shown, not merely that
    // some element exists.
    let message = app.staticTexts.containing(
      NSPredicate(format: "label CONTAINS[c] %@", "valid server address")
    ).firstMatch
    XCTAssertTrue(message.waitForExistence(timeout: 5))
  }
}
