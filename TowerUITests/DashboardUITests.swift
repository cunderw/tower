import XCTest

/// Covers the two `DashboardView` scenarios no other UI test file already
/// exercises: the loaded screen's capacity ring and array-state pill
/// existing together with all three services rows, and the failed-load
/// `ContentUnavailableView` actually recovering when "Try Again" is tapped.
///
/// Deliberately does **not** duplicate:
/// - Services-row tap-to-navigate (`DashboardServicesUITests` already taps
///   `services.docker`/`.vms`/`.shares` and asserts the tab bar switches).
/// - Disk-detail push-and-title (`DiskDetailUITests` already taps the first
///   row of all three disk groups and asserts the pushed screen's title).
///
/// Taps with XCUITest's own `.tap()` because `idb ui tap` does nothing on
/// macOS 27 (see `DashboardServicesUITests`).
@MainActor
final class DashboardUITests: XCTestCase {
  /// `state` selects `FakeSystemRepository.Outcome` via
  /// `UITEST_DASHBOARD_STATE` (see `UITestSupport.swift`): `nil` for the
  /// default success fixture, `"failure"` for a permanently failed load, or
  /// `"retry-succeeds"` for a load that fails once and then recovers.
  private func launch(state: String? = nil) -> XCUIApplication {
    let app = XCUIApplication()
    app.launchArguments = ["--uitest-seed-dashboard"]
    if let state {
      app.launchEnvironment["UITEST_DASHBOARD_STATE"] = state
    }
    app.launch()
    return app
  }

  private func element(identifier: String, in app: XCUIApplication) -> XCUIElement {
    app.descendants(matching: .any).matching(identifier: identifier).firstMatch
  }

  func testLoadedDashboardShowsCapacityRingStatePillAndAllServiceRows() {
    let app = launch()

    let ring = element(identifier: "dashboard.capacityRing", in: app)
    XCTAssertTrue(ring.waitForExistence(timeout: 5), "dashboard.capacityRing never appeared on a loaded dashboard")

    let statePill = element(identifier: "array.state", in: app)
    XCTAssertTrue(statePill.waitForExistence(timeout: 5), "array.state pill never appeared on a loaded dashboard")
    // `UITestFixtures`' `ArrayStatus.uitestFixture` reports `state: "STARTED"`
    // — `ArrayHeroCard` renders it `.capitalized` as "Started".
    XCTAssertTrue(
      statePill.label.localizedCaseInsensitiveContains("started"),
      "array.state pill should reflect the array's STARTED state, got \"\(statePill.label)\""
    )

    // Existence only, deliberately: `DashboardServicesUITests` already
    // proves each row's exact label and that tapping it switches tabs. This
    // test's job is proving all three render together on a freshly loaded
    // dashboard, not re-proving their navigation behavior.
    XCTAssertTrue(element(identifier: "services.docker", in: app).waitForExistence(timeout: 5), "services.docker row missing on a loaded dashboard")
    XCTAssertTrue(element(identifier: "services.vms", in: app).exists, "services.vms row missing on a loaded dashboard")
    XCTAssertTrue(element(identifier: "services.shares", in: app).exists, "services.shares row missing on a loaded dashboard")
  }

  func testFailedDashboardShowsContentUnavailableViewAndTryAgainRecovers() throws {
    let app = launch(state: "retry-succeeds")

    // `dashboard.error`/`dashboard.retry` let this match by
    // identifier instead of string-matching user-facing copy, so a wording
    // change to the error message or button title can't break this test.
    let message = element(identifier: "dashboard.error", in: app)
    XCTAssertTrue(message.waitForExistence(timeout: 5), "dashboard.error never appeared on a failed dashboard")

    let tryAgain = element(identifier: "dashboard.retry", in: app)
    XCTAssertTrue(tryAgain.waitForExistence(timeout: 5), "dashboard.retry button never appeared on the failed dashboard")
    try saveScreenshot(named: "dashboard-error")

    // Issue #13: Try Again sits directly under the message, not down on the
    // floating tab bar. Same bound as `VMUITests`' failed-load test.
    let gap = tryAgain.frame.minY - message.frame.maxY
    XCTAssertLessThan(gap, 100, "Try Again sits \(gap) pt below the message, not directly under it")

    tryAgain.tap()

    // `FakeSystemRepository(outcome: .failFirstThenRecover)` fails only the
    // automatic initial load; this second `dashboard()` call — triggered by
    // the tap above — succeeds. A "Try Again" button that silently did
    // nothing would leave the screen on the exact same failed view forever,
    // so waiting for a loaded-only element is what actually distinguishes
    // "retried" from "did nothing": a bare re-assertion of the failed view
    // would pass either way.
    let ring = element(identifier: "dashboard.capacityRing", in: app)
    XCTAssertTrue(ring.waitForExistence(timeout: 5), "tapping Try Again never recovered the dashboard to its loaded state")
    XCTAssertFalse(message.exists, "dashboard.error still showing after a successful retry")
  }

  // MARK: - Live metrics (issue #24)

  /// Waits for `element`'s accessibility value to contain `text`. Returns
  /// false at the deadline, and every caller asserts the result.
  private func waitForValue(
    of element: XCUIElement, containing text: String, timeout: TimeInterval = 5
  ) -> Bool {
    let predicate = NSPredicate(format: "value CONTAINS %@", text)
    let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
    return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
  }

  /// Waits for `element`'s accessibility value to contain any one of `texts`.
  /// For a value that alternates: every reading satisfies the wait, so a poll
  /// that happens to land on the same phase each time still sees it.
  private func waitForValue(
    of element: XCUIElement, containingAnyOf texts: [String], timeout: TimeInterval = 5
  ) -> Bool {
    let predicate = NSCompoundPredicate(
      orPredicateWithSubpredicates: texts.map { NSPredicate(format: "value CONTAINS %@", $0) })
    let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
    return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
  }

  /// Reads `element`'s accessibility value every 0.1 s until every one of
  /// `texts` has appeared in some reading (in the order given, if `inOrder`),
  /// or `timeout` passes, and returns the readings in order with their time
  /// since the first one. An element that does not exist yet reads as
  /// "<absent>", so sampling can start before the element appears.
  /// Samples by hand, not through `XCTNSPredicateExpectation`: that one
  /// evaluates too seldom to see both phases of a value that alternates once a
  /// second (issue #57). Reads once more after the deadline.
  private func sampleValues(
    of element: XCUIElement, untilSeeing texts: [String], inOrder: Bool = false,
    timeout: TimeInterval = 5
  ) -> (sawAll: Bool, samples: [String]) {
    let start = Date()
    var samples: [String] = []
    var seen: [String] = []
    func read() -> Bool {
      // `value` on an element that does not exist fails the test, so look first.
      let value = element.exists ? (element.value as? String) ?? "" : "<absent>"
      samples.append(String(format: "%.1fs %@", Date().timeIntervalSince(start), value))
      if inOrder {
        if seen.count < texts.count, value.contains(texts[seen.count]) { seen.append(texts[seen.count]) }
      } else {
        seen += texts.filter { value.contains($0) && !seen.contains($0) }
      }
      return seen.count == texts.count
    }
    while Date().timeIntervalSince(start) < timeout {
      if read() { return (true, samples) }
      RunLoop.current.run(until: Date().addingTimeInterval(0.1))
    }
    return (read(), samples)
  }

  /// The label and value together. `LabeledContent` may publish its value
  /// in either, and this test cares only that "52°C" reaches the tree.
  private func spokenText(of element: XCUIElement) -> String {
    "\(element.label) \((element.value as? String) ?? "")"
  }

  /// Drags the dashboard up by a quarter of the screen on iPhone, so the whole
  /// System card clears the tab bar before a screenshot. The iPad shows the
  /// card in full without it. A slow drag held at its end, not `swipeUp()`,
  /// so no fling carries the card's header under the navigation bar.
  private func revealSystemCard(in app: XCUIApplication) {
    guard UIDevice.current.userInterfaceIdiom == .phone else { return }
    app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.75)).press(
      forDuration: 0.1,
      thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)),
      withVelocity: .slow,
      thenHoldForDuration: 0.5
    )
  }

  /// `FakeMetricsStream`'s `.live` mode: CPU alternates 47% and 53% once a
  /// second over the fixture's polled 12%. Either value proves the gauge went
  /// live. Seeing both proves the gauge follows the stream while the dashboard
  /// is on screen, not that it showed one live value once.
  func testLiveMetricsReplaceThePolledGaugesAndShowTheCpuTemperature() throws {
    let app = launch(state: "live-metrics")

    let cpu = element(identifier: "dashboard.metricGauge.cpu", in: app)
    XCTAssertTrue(cpu.waitForExistence(timeout: 5), "dashboard.metricGauge.cpu never appeared")
    XCTAssertTrue(
      waitForValue(of: cpu, containingAnyOf: ["47%", "53%"]),
      "the CPU gauge never showed a live 47% or 53%, got \"\(cpu.value ?? "")\"")
    let cpuReadings = sampleValues(of: cpu, untilSeeing: ["47%", "53%"])
    XCTAssertTrue(
      cpuReadings.sawAll,
      "the CPU gauge never showed both live 47% and 53%, \(cpuReadings.samples.count) readings: \(cpuReadings.samples)")

    let memory = element(identifier: "dashboard.metricGauge.memory", in: app)
    XCTAssertTrue(waitForValue(of: memory, containing: "30%"), "the memory gauge never showed the live 30%, got \"\(memory.value ?? "")\"")
    // Used and total move with the percent, so the detail line agrees.
    XCTAssertTrue(waitForValue(of: memory, containing: "9.6 GB"), "the memory detail never followed the live reading, got \"\(memory.value ?? "")\"")

    let temperature = element(identifier: "dashboard.cpuTemperature", in: app)
    XCTAssertTrue(temperature.waitForExistence(timeout: 5), "the CPU temperature row never appeared")
    XCTAssertTrue(spokenText(of: temperature).contains("52°C"), "the CPU temperature row read \"\(spokenText(of: temperature))\"")

    revealSystemCard(in: app)
    try saveScreenshot(named: "dashboard-system-live")
  }

  /// A live stream whose server reports no CPU sensor: the gauges are live,
  /// and there is no temperature row at all, not a "—" that never fills in.
  func testNoCpuSensorHidesTheTemperatureRow() throws {
    let app = launch(state: "live-metrics-no-sensor")

    let cpu = element(identifier: "dashboard.metricGauge.cpu", in: app)
    XCTAssertTrue(cpu.waitForExistence(timeout: 5), "dashboard.metricGauge.cpu never appeared")
    XCTAssertTrue(
      waitForValue(of: cpu, containingAnyOf: ["47%", "53%"]),
      "the CPU gauge never showed a live 47% or 53%, got \"\(cpu.value ?? "")\"")
    let cpuReadings = sampleValues(of: cpu, untilSeeing: ["47%", "53%"])
    XCTAssertTrue(
      cpuReadings.sawAll,
      "the CPU gauge never showed both live 47% and 53%, \(cpuReadings.samples.count) readings: \(cpuReadings.samples)")

    XCTAssertFalse(
      element(identifier: "dashboard.cpuTemperature", in: app).exists,
      "a server with no CPU sensor must not show a temperature row")

    revealSystemCard(in: app)
    try saveScreenshot(named: "dashboard-system-no-sensor")
  }

  /// The acceptance criterion: on a websocket failure the dashboard falls
  /// back to its polled values and shows no alarming message. The fake's
  /// stream fails and stays failed; the live repository's own retry is
  /// covered in the kit tests. The live value
  /// is seen first, so a stream that never ran cannot pass this.
  func testAFailingStreamFallsBackToThePolledValuesWithoutAnError() {
    let app = launch(state: "live-metrics-fails")

    // The stream is live for only `FakeMetricsStream.failureDelay` (5 s), so
    // sample from launch: a wait for the gauge to appear first spends that
    // window (issue #57). The fixture's polled CPU is 12%, so 47% and then
    // 12% is the stream going live and then failing.
    let cpu = element(identifier: "dashboard.metricGauge.cpu", in: app)
    let cpuReadings = sampleValues(of: cpu, untilSeeing: ["47%", "12%"], inOrder: true, timeout: 15)
    XCTAssertTrue(
      cpuReadings.sawAll,
      "the CPU gauge never showed the live 47% and then the polled 12%, \(cpuReadings.samples.count) readings: \(cpuReadings.samples)")
    // Only the stream sends a temperature, and the poll has none, so the
    // last reading stays rather than the row vanishing and every card below
    // it jumping.
    let temperature = element(identifier: "dashboard.cpuTemperature", in: app)
    XCTAssertTrue(temperature.exists, "the temperature row is missing after the stream failed")
    XCTAssertTrue(spokenText(of: temperature).contains("52°C"), "the CPU temperature row read \"\(spokenText(of: temperature))\" after the stream failed")
    XCTAssertFalse(
      app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "Couldn't reach the server")).firstMatch.exists,
      "a failed live stream must not show the stream's error")
    XCTAssertFalse(element(identifier: "dashboard.error", in: app).exists, "a failed live stream must not fail the dashboard")
  }
}
