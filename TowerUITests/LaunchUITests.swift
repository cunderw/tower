import XCTest

/// What the app puts on screen before it knows whether a credential is
/// stored.
///
/// Every test here passes `--uitest-slow-launch-check`, which holds the deciding
/// phase open for three seconds. Without it the decision lands within a frame or
/// two and there is nothing to assert against — the placeholder would be real
/// but unobservable, and so would `ConnectView` filling that same window.
@MainActor
final class LaunchUITests: XCTestCase {
  override func setUp() {
    super.setUp()
    continueAfterFailure = false
  }

  func testAStoredCredentialNeverShowsTheConnectForm() {
    // `--uitest-seed-dashboard` stands in for "a credential is stored": XCUITest
    // can't write the keychain, and this argument takes the same branch — resolve
    // to a server without ever passing through `.connect`.
    let app = XCUIApplication()
    app.launchArguments = ["--uitest-seed-dashboard", "--uitest-slow-launch-check"]
    app.launch()

    let placeholder = app.descendants(matching: .any)
      .matching(identifier: "launch.placeholder").firstMatch
    XCTAssertTrue(
      placeholder.waitForExistence(timeout: 10),
      "the launch placeholder never appeared"
    )
    // The launch state must tell "no credential" apart from "haven't looked
    // yet". A single `nil` for both shows the connect form in this window.
    XCTAssertFalse(
      app.textFields["connect.url"].exists,
      "the connect form was shown to a user who has a stored credential"
    )

    // And the placeholder isn't a dead end. Waits on the capacity ring's
    // identifier rather than the "Dashboard" title, which is also the tab's
    // label — and on iPad `.sidebarAdaptable` renders that twice.
    XCTAssertTrue(
      app.descendants(matching: .any).matching(identifier: "dashboard.capacityRing")
        .firstMatch.waitForExistence(timeout: 15),
      "the app never got past the launch placeholder"
    )
  }

  func testNoStoredCredentialStillReachesTheConnectForm() {
    // The other half, and the reason the test above isn't satisfiable by simply
    // never showing the form: with nothing stored, the connect screen still has
    // to arrive — after the placeholder, not instead of it.
    let app = XCUIApplication()
    app.launchArguments = ["--uitest-reset-credentials", "--uitest-slow-launch-check"]
    app.launch()

    let placeholder = app.descendants(matching: .any)
      .matching(identifier: "launch.placeholder").firstMatch
    XCTAssertTrue(placeholder.waitForExistence(timeout: 10))
    XCTAssertFalse(
      app.textFields["connect.url"].exists,
      "the connect form rendered before the credential check had finished"
    )

    XCTAssertTrue(
      app.textFields["connect.url"].waitForExistence(timeout: 15),
      "a launch with no stored credential never reached the connect screen"
    )
  }
}
