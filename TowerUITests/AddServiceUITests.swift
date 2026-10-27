import XCTest

/// The Add Service flow, end to end against the in-memory directory and
/// `FakeServiceStatusChecker`.
///
/// The fake decides an unseeded instance's outcome from what was typed — an API
/// key of `bad` is rejected, a host containing `down` is unreachable — because a
/// service added through the form has a random id no fixture can name.
@MainActor
final class AddServiceUITests: XCTestCase {
  override func setUp() {
    super.setUp()
    continueAfterFailure = false
  }

  /// Starts with nothing configured, so the empty state's own Add Service
  /// button is the way in and a saved row is unambiguous.
  private func launchOnEmptyServices() -> XCUIApplication {
    let app = XCUIApplication()
    app.launchArguments = ["--uitest-seed-dashboard"]
    app.launchEnvironment["UITEST_SERVICES_STATE"] = "empty"
    app.launch()
    app.buttons["Services"].firstMatch.tap()
    return app
  }

  private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
    app.descendants(matching: .any).matching(identifier: identifier).firstMatch
  }

  /// Opens the form from the empty state's own button.
  ///
  /// Queried as `app.buttons["services.empty"]`, not by an identifier of its
  /// own: `ContentUnavailableView` propagates the container's identifier down
  /// over its children, so the button *is* `services.empty` in the tree. Taken
  /// from a real accessibility dump rather than assumed.
  private func openAddService(in app: XCUIApplication) {
    let emptyAdd = app.buttons["services.empty"].firstMatch
    XCTAssertTrue(emptyAdd.waitForExistence(timeout: 10), "the empty state has no Add Service button")
    emptyAdd.tap()
    XCTAssertTrue(element("addService.name", in: app).waitForExistence(timeout: 10))
  }

  /// Taps Test, and reveals the result.
  ///
  /// **Both halves matter on iPad.** The form is a centered form sheet there,
  /// shorter than the device, and the keyboard left up by the last field
  /// covers the bottom of it — so Test itself can be off screen, and the
  /// result row below it certainly is. Dismissing the keyboard and scrolling
  /// is what makes this the same test on both devices rather than one that
  /// silently only runs on a phone.
  private func tapTest(in app: XCUIApplication) {
    dismissKeyboard(in: app)
    let test = element("addService.test", in: app)
    XCTAssertTrue(scrollTo(test, in: app, attempts: 8), "the form had no Test button")
    test.tap()
  }

  /// Returns whatever the Test row is now saying, scrolling to it first.
  private func testResult(in app: XCUIApplication) -> XCUIElement {
    let result = element("addService.testResult", in: app)
    XCTAssertTrue(
      scrollTo(result, in: app, attempts: 8), "testing the connection reported nothing")
    return result
  }

  /// Puts the keyboard away so it can't cover the rows below the fields. The
  /// form sheet has no Done button, so a tap on the sheet's own title bar is
  /// the reliable dismissal on both devices.
  private func dismissKeyboard(in app: XCUIApplication) {
    guard app.keyboards.firstMatch.exists else { return }
    app.navigationBars.firstMatch.tap()
  }

  /// Fills the form for an API-key service. `key` selects the fake's outcome.
  private func fillRadarr(in app: XCUIApplication, host: String = "192.0.2.9:7878", key: String) {
    // The field is prefilled with the kind's name; replace it.
    replaceText(in: element("addService.name", in: app), with: "Radarr HD")

    type("http://\(host)", into: element("addService.url", in: app))
    type(key, into: app.secureTextFields.firstMatch)
  }

  // MARK: - Test connection

  func testTestReportsARejectedKeyDistinctlyFromAnUnreachableHost() {
    let app = launchOnEmptyServices()
    openAddService(in: app)
    fillRadarr(in: app, key: "bad")

    tapTest(in: app)
    let rejectedCopy = testResult(in: app).label
    XCTAssertTrue(
      rejectedCopy.contains("rejected"),
      "a wrong key should say the credentials were rejected, got: \(rejectedCopy)")

    // Same form, an address that refuses the connection instead.
    replaceText(in: element("addService.url", in: app), with: "http://down.example:7878")
    tapTest(in: app)

    let unreachable = testResult(in: app)
    XCTAssertNotEqual(
      unreachable.label, rejectedCopy,
      "an unreachable host and a rejected key must not read the same")
    XCTAssertTrue(unreachable.label.contains("reach"))
  }

  // MARK: - Saving

  func testASavedServiceAppearsOnTheHubImmediately() {
    let app = launchOnEmptyServices()
    openAddService(in: app)
    fillRadarr(in: app, key: "good")

    element("addService.save", in: app).tap()

    // Back on the hub, with a row and a resolved status — the empty state gone.
    let row = app.descendants(matching: .any)
      .matching(NSPredicate(format: "identifier BEGINSWITH 'services.row.'")).firstMatch
    XCTAssertTrue(row.waitForExistence(timeout: 10), "the saved service never appeared on the hub")
    XCTAssertTrue(row.label.contains("Radarr HD"))
    XCTAssertFalse(element("services.empty", in: app).exists)
  }

  // MARK: - Fields follow the kind

  func testTheCredentialFieldsFollowTheSelectedKind() {
    let app = launchOnEmptyServices()
    openAddService(in: app)

    // Radarr: one secure field (the API key), no username.
    XCTAssertTrue(element("addService.apiKey", in: app).waitForExistence(timeout: 5))
    XCTAssertFalse(element("addService.username", in: app).exists)

    element("addService.kind", in: app).tap()
    app.buttons["NZBGet"].firstMatch.tap()

    // NZBGet: username and password, and no API key row at all.
    XCTAssertTrue(element("addService.username", in: app).waitForExistence(timeout: 5))
    XCTAssertTrue(element("addService.password", in: app).exists)
    XCTAssertFalse(element("addService.apiKey", in: app).exists)
  }

  // MARK: - Docker-assisted prefill

  func testARunningServiceContainerIsOfferedAndPrefillsTheAddress() {
    // The candidate's host is `UITestFixtures.server`'s, and its port is the
    // container's *published* 18989 rather than Sonarr's stock 8989 — the
    // remapping is the part a hand-written default would get wrong.
    let app = XCUIApplication()
    app.launchArguments = ["--uitest-seed-dashboard"]
    app.launchEnvironment["UITEST_SERVICES_STATE"] = "empty"
    app.launchEnvironment["UITEST_DOCKER_STATE"] = "service-containers"
    app.launch()
    app.buttons["Services"].firstMatch.tap()
    openAddService(in: app)

    let candidate = element("addService.candidate.uitest-container-sonarr", in: app)
    XCTAssertTrue(candidate.waitForExistence(timeout: 10), "the running Sonarr was not offered")
    // The stopped Radarr must not be offered: a candidate whose test can only
    // fail teaches nothing about what the user typed.
    XCTAssertFalse(element("addService.candidate.uitest-container-radarr", in: app).exists)
    // Nor may an unrelated container appear.
    XCTAssertFalse(element("addService.candidate.uitest-container-1", in: app).exists)

    candidate.tap()

    let url = element("addService.url", in: app)
    XCTAssertTrue(url.waitForExistence(timeout: 5))
    XCTAssertEqual(url.value as? String, "http://uitest.invalid:18989")
    // And no credential was invented: Save stays disabled until one is typed.
    // Queried as a `Button`, not through `descendants(matching: .any)` — the
    // enclosing element matched by identifier reports `isEnabled == true` even
    // when the button inside it is disabled.
    XCTAssertFalse(app.buttons["addService.save"].firstMatch.isEnabled)
  }

  func testTheFormWorksUnchangedWhenNoContainerIsRecognised() {
    // The default fixture list has no media services in it, so this is also the
    // "container list unavailable" shape: no section, no error, form usable.
    let app = launchOnEmptyServices()
    openAddService(in: app)

    XCTAssertTrue(element("addService.name", in: app).waitForExistence(timeout: 10))
    XCTAssertFalse(app.staticTexts["Found on Your Server"].exists)

    fillRadarr(in: app, key: "good")
    XCTAssertTrue(app.buttons["addService.save"].firstMatch.isEnabled)
  }

  // MARK: - Settings entry point

  func testAddServiceIsAlsoReachableFromSettings() {
    let app = launchOnEmptyServices()
    element("toolbar.settings", in: app).tap()

    let settingsAdd = element("settings.addService", in: app)
    // Scrolls first: on iPad the Settings sheet is a *centered form sheet*,
    // shorter than the device, so this row starts below the fold — and a
    // SwiftUI `List` doesn't render rows it hasn't scrolled to, which reads as
    // a missing feature rather than a hidden one.
    XCTAssertTrue(
      scrollTo(settingsAdd, in: app, attempts: 8), "Settings had no Add Service row")
    settingsAdd.tap()

    XCTAssertTrue(element("addService.name", in: app).waitForExistence(timeout: 10))
  }
}
