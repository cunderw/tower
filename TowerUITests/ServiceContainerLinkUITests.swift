import XCTest

/// Jumping between a service and the Docker container running it.
///
/// Both fixtures are opt-in: `UITEST_SERVICES_STATE=container-linked` seeds two
/// instances addressed on the fake server's own host, and
/// `UITEST_DOCKER_STATE=service-containers` adds the containers they match. The
/// default fixtures deliberately do *not* match each other, which is what the
/// last test here asserts.
@MainActor
final class ServiceContainerLinkUITests: XCTestCase {
  private let linkedSonarr = "A0000000-0000-0000-0000-0000000000A1"
  private let linkedRadarr = "A0000000-0000-0000-0000-0000000000A2"

  override func setUp() {
    super.setUp()
    continueAfterFailure = false
  }

  private func launch(services: String = "container-linked") -> XCUIApplication {
    let app = XCUIApplication()
    app.launchArguments = ["--uitest-seed-dashboard"]
    app.launchEnvironment["UITEST_SERVICES_STATE"] = services
    app.launchEnvironment["UITEST_DOCKER_STATE"] = "service-containers"
    app.launch()
    return app
  }

  private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
    app.descendants(matching: .any).matching(identifier: identifier).firstMatch
  }

  // MARK: - Container → service

  func testAContainerOpensTheServiceConfiguredAgainstIt() {
    let app = launch()
    app.buttons["Docker"].firstMatch.tap()

    let container = element("docker.row.uitest-container-sonarr", in: app)
    XCTAssertTrue(container.waitForExistence(timeout: 15), "the Sonarr container never appeared")
    container.tap()

    let link = element("container.service", in: app)
    XCTAssertTrue(link.waitForExistence(timeout: 10), "no service link on the container screen")
    XCTAssertTrue(link.label.contains("Linked Sonarr"), link.label)
    link.tap()

    // Landed in the Services tab, on that instance's screen — the section
    // picker only exists inside a service.
    XCTAssertTrue(
      element("arr.shell", in: app).waitForExistence(timeout: 15),
      "tapping the service link did not open the service")
  }

  // MARK: - Service → container

  func testAServiceOpensItsContainerEvenWhenStopped() {
    // The Radarr fixture's container is **stopped**, which is exactly when a
    // user wants it: the service is unreachable and the container says why.
    let app = launch()
    app.buttons["Services"].firstMatch.tap()

    let row = element("services.row.\(linkedRadarr)", in: app)
    XCTAssertTrue(row.waitForExistence(timeout: 15), "the linked Radarr row never appeared")
    // **Leading edge**, alongside Enable/Disable — the trailing one is Delete,
    // and a navigation action next to a destructive one is asking for a
    // mis-swipe. Per CLAUDE.md a leading `swipeRight` can travel far enough to
    // *commit* on a narrow iPad column, so the action is tapped only if it
    // parked open, and the assertion below is on where we ended up either way.
    row.swipeRight()

    let action = element("services.row.\(linkedRadarr).container", in: app)
    if action.waitForExistence(timeout: 5), action.isHittable {
      action.tap()
    }

    // The logs button exists only on a container detail screen.
    XCTAssertTrue(
      element("containerDetail.viewLogsButton", in: app).waitForExistence(timeout: 15),
      "tapping the container action did not open the container")
  }

  // MARK: - No match, no link

  func testAServiceThatMatchesNoContainerOffersNoAction() {
    // The default fixtures put every service on `192.0.2.1` while the fake
    // server is `uitest.invalid`, so nothing matches. **No action is the
    // correct answer** — the container screen carries Restart, and a link to
    // the wrong container is worse than none.
    let app = launch(services: "default")
    app.buttons["Services"].firstMatch.tap()

    let radarr = "A0000000-0000-0000-0000-000000000001"
    let row = element("services.row.\(radarr)", in: app)
    XCTAssertTrue(row.waitForExistence(timeout: 15))
    row.swipeRight()

    XCTAssertFalse(
      element("services.row.\(radarr).container", in: app).waitForExistence(timeout: 3),
      "offered a container link for a service on a different host")
  }
}
