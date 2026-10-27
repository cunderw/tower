import XCTest

@MainActor
final class SmokeUITests: XCTestCase {
  // Asserts the app launches straight to `ConnectView` when there are no
  // stored credentials. `--uitest-reset-credentials` guarantees a
  // credential-free start so this assertion is deterministic regardless of
  // what a previous test run left in the keychain.
  func testAppLaunches() {
    let app = XCUIApplication()
    app.launchArguments = ["--uitest-reset-credentials"]
    app.launch()
    XCTAssertTrue(app.navigationBars["Connect to Tower"].waitForExistence(timeout: 5))
  }
}
