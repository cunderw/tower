import XCTest

/// Confirms two accessibility properties actually reach the accessibility
/// tree, which a compiler can't check: `MetricGauge` announces its title once
/// with an explicit accessibility value, and an unhealthy disk's status is
/// conveyed in text rather than by an icon with an empty accessibility title.
///
/// Nothing here taps anything, so the synthetic-tap limitation
/// `DashboardServicesUITests`/`DiskDetailUITests` document doesn't apply;
/// this only reads `label`/`value` off `XCUIElement`, which is unaffected.
@MainActor
final class DashboardAccessibilityUITests: XCTestCase {
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

  /// `UITestFixtures`' default fixture reports real CPU/memory readings
  /// (`cpuPercent: 12`, `memoryPercent: 88`), so this is the everyday case:
  /// both gauges should announce their title exactly once (no more "CPU,
  /// CPU" / "Memory, Memory") with a value that folds in the percentage and,
  /// where present, the detail line — never leaving VoiceOver's default
  /// `Gauge` behaviour to invent something from the raw `value:`.
  func testMetricGaugesAnnounceTitleOnceWithASensibleValue() {
    let app = launch()

    let cpu = element(identifier: "dashboard.metricGauge.cpu", in: app)
    XCTAssertTrue(cpu.waitForExistence(timeout: 5), "dashboard.metricGauge.cpu never appeared")
    XCTAssertEqual(cpu.label, "CPU", "CPU gauge's accessibility label should read exactly \"CPU\", not the title duplicated")
    let cpuValue = (cpu.value as? String) ?? ""
    XCTAssertTrue(cpuValue.contains("12%"), "CPU gauge's accessibility value should include its percentage, got \"\(cpuValue)\"")
    XCTAssertTrue(cpuValue.contains("cores"), "CPU gauge's accessibility value should still include its detail line, got \"\(cpuValue)\"")

    let memory = element(identifier: "dashboard.metricGauge.memory", in: app)
    XCTAssertTrue(memory.exists, "dashboard.metricGauge.memory never appeared")
    XCTAssertEqual(memory.label, "Memory", "Memory gauge's accessibility label should read exactly \"Memory\", not the title duplicated")
    let memoryValue = (memory.value as? String) ?? ""
    XCTAssertTrue(memoryValue.contains("88%"), "Memory gauge's accessibility value should include its percentage, got \"\(memoryValue)\"")
    XCTAssertTrue(memoryValue.contains("GB"), "Memory gauge's accessibility value should still include its detail line, got \"\(memoryValue)\"")
  }

  /// `UITEST_DASHBOARD_STATE=nil-metrics` selects `Outcome.unknownMetrics`
  /// (`FakeSystemRepository`/`UITestFixtures`), a successful load with a nil
  /// `cpuPercent`/`memoryPercent`. The rule "unknown must not read as a
  /// number" has to hold for VoiceOver too — with no explicit
  /// `.accessibilityValue`, whether VoiceOver says "—" or a derived "0
  /// percent" for `Gauge(value: 0)` is left to SwiftUI. This proves the
  /// explicit value actually wins.
  func testMetricGaugeAnnouncesUnknownValueForANilMetric() {
    let app = launch(state: "nil-metrics")

    let cpu = element(identifier: "dashboard.metricGauge.cpu", in: app)
    XCTAssertTrue(cpu.waitForExistence(timeout: 5), "dashboard.metricGauge.cpu never appeared")
    XCTAssertEqual(cpu.label, "CPU")
    // No `cpuBrand`/core/thread fallback in this fixture either, so the CPU
    // gauge's value should be the bare "Unknown" with no detail suffix.
    XCTAssertEqual(cpu.value as? String, "Unknown", "a nil percent with no detail must announce as exactly \"Unknown\", not a derived number")

    let memory = element(identifier: "dashboard.metricGauge.memory", in: app)
    XCTAssertTrue(memory.exists, "dashboard.metricGauge.memory never appeared")
    XCTAssertEqual(memory.label, "Memory")
    // `memoryUsedBytes`/`.memoryTotalBytes` are still populated in this
    // fixture, so the Memory gauge's value should be "Unknown" *with* its
    // detail line still attached — nil `percent` doesn't mean nil `detail`.
    let memoryValue = (memory.value as? String) ?? ""
    XCTAssertTrue(memoryValue.hasPrefix("Unknown"), "a nil percent must announce as \"Unknown\", got \"\(memoryValue)\"")
    XCTAssertTrue(memoryValue.contains("GB"), "the detail line should still be announced alongside \"Unknown\", got \"\(memoryValue)\"")
  }

  /// `UITestFixtures` seeds a second data disk (`uitest-disk-2`,
  /// `status: "DISK_DSBL"`) precisely so this is reachable. An icon alone,
  /// `Label("", systemImage: "exclamationmark.triangle.fill")`, is not enough:
  /// an empty title contributes nothing to a merged accessibility label, so a
  /// VoiceOver user would hear no indication the disk was unhealthy at all.
  func testUnhealthyDiskRowConveysStatusInText() {
    let app = launch()

    let unhealthyRow = element(identifier: "disk.row.uitest-disk-2", in: app)
    XCTAssertTrue(unhealthyRow.waitForExistence(timeout: 5), "disk.row.uitest-disk-2 never appeared")
    XCTAssertTrue(
      unhealthyRow.label.contains("DSBL"),
      "unhealthy disk row's merged accessibility label should convey its status, got \"\(unhealthyRow.label)\""
    )

    // A healthy row (same card, same fixture) is the control: it must not
    // mention a disabled status it doesn't have.
    let healthyRow = element(identifier: "disk.row.uitest-disk-1", in: app)
    XCTAssertTrue(healthyRow.exists, "disk.row.uitest-disk-1 never appeared")
    XCTAssertFalse(
      healthyRow.label.contains("DSBL"),
      "a healthy disk row should not mention a disabled status, got \"\(healthyRow.label)\""
    )
  }
}
