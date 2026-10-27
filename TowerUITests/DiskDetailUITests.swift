import Foundation
import XCTest

/// Proves `DiskListCard` rows actually push `DiskDetailView` — the one thing
/// a static screenshot can't verify — and that the nil-handling rules hold
/// for all three disk shapes Unraid produces:
/// a data disk (full filesystem + IO fields), a parity disk (device, media,
/// and IO fields all present; only filesystem is genuinely absent, so
/// capacity falls back to raw `size`), and a cache disk (device and
/// filesystem fields both present).
///
/// Taps with XCUITest's own `.tap()` because `idb ui tap` does nothing on
/// macOS 27 (see `DashboardServicesUITests`).
@MainActor
final class DiskDetailUITests: XCTestCase {
  private func launchOnDashboard() -> XCUIApplication {
    let app = XCUIApplication()
    app.launchArguments = ["--uitest-seed-dashboard"]
    app.launch()
    return app
  }

  /// Any element anywhere in the tree whose accessibility label contains
  /// `substring` — deliberately loose about *which* element type or exactly
  /// how `LabeledContent` groups its title/value, so this doesn't overfit to
  /// a rendering detail that isn't the point of the test.
  private func element(labelContains substring: String, in app: XCUIApplication) -> XCUIElement {
    matches(labelContains: substring, in: app).firstMatch
  }

  private func matches(labelContains substring: String, in app: XCUIApplication) -> XCUIElementQuery {
    app.descendants(matching: .any)
      .matching(NSPredicate(format: "label CONTAINS[c] %@", substring))
  }

  func testDataDiskShowsFilesystemDeviceAndIOCounters() {
    let app = launchOnDashboard()

    let row = app.descendants(matching: .any).matching(identifier: "disk.row.uitest-disk-1").firstMatch
    XCTAssertTrue(row.waitForExistence(timeout: 5), "disk.row.uitest-disk-1 never appeared")
    row.tap()

    XCTAssertTrue(app.navigationBars["disk1"].waitForExistence(timeout: 5), "tapping the data disk row never pushed its detail screen")

    XCTAssertTrue(element(labelContains: "sdb", in: app).waitForExistence(timeout: 5), "Device row (sdb) missing for a data disk")
    XCTAssertTrue(element(labelContains: "xfs", in: app).exists, "Filesystem row (xfs) missing for a data disk")
    XCTAssertTrue(element(labelContains: "Hard drive", in: app).exists, "Media row missing for a rotational data disk")

    // `List` lazily materializes off-screen rows — unlike the dashboard's
    // eager `ScrollView`/`VStack` — so the Activity section (below the
    // Capacity/Device sections already on screen) doesn't exist in the
    // accessibility tree until scrolled into view.
    app.swipeUp()

    // `numReads`/`numWrites` are real, non-nil counters here — confirms the
    // Activity section renders actual values, not just that it can omit
    // itself (covered by the parity case below).
    XCTAssertTrue(element(labelContains: "128,552,310", in: app).waitForExistence(timeout: 5), "Reads counter missing or unformatted for a data disk")
    XCTAssertTrue(element(labelContains: "4,221,009", in: app).exists, "Writes counter missing or unformatted for a data disk")
  }

  func testParityDiskShowsDeviceMediaAndIOButOmitsFilesystem() {
    let app = launchOnDashboard()

    let row = app.descendants(matching: .any).matching(identifier: "disk.row.uitest-parity-1").firstMatch
    XCTAssertTrue(row.waitForExistence(timeout: 5), "disk.row.uitest-parity-1 never appeared")
    row.tap()

    XCTAssertTrue(app.navigationBars["parity"].waitForExistence(timeout: 5), "tapping the parity row never pushed its detail screen — app may have crashed")

    // Capacity still shows (raw `size` fallback), but `fsSize` is nil, so
    // this must be the explicit "unknown" ring — never a fabricated 0%,
    // which `usedFraction` would silently produce for a nil `fsSize`.
    XCTAssertTrue(element(labelContains: "Size", in: app).exists, "Size row missing for a parity disk despite a non-nil capacityKilobytes")
    // `diskDetail.capacityRing`, not `dashboard.capacityRing` — `CapacityRing`'s
    // identifier is a parameter so the disk detail screen doesn't share the
    // dashboard's.
    let ring = app.descendants(matching: .any).matching(identifier: "diskDetail.capacityRing").firstMatch
    XCTAssertTrue(ring.waitForExistence(timeout: 5), "capacity ring missing on the parity detail screen")
    let ringValue = (ring.value as? String) ?? ""
    XCTAssertTrue(
      ringValue.hasPrefix("—"),
      "parity capacity ring should read as unknown (—…), not a fabricated percentage — got \"\(ringValue)\""
    )

    // Unraid reports `device` and `rotational` for parity disks, and
    // `Dashboard.graphql` selects them, so these rows must render.
    XCTAssertTrue(element(labelContains: "sde", in: app).waitForExistence(timeout: 5), "Device row (sde) missing for a parity disk — it genuinely reports one")
    XCTAssertTrue(element(labelContains: "Hard drive", in: app).exists, "Media row missing for a rotational parity disk")

    // Filesystem is the one thing genuinely absent for parity — it carries
    // no filesystem, so this row (and only this row) must still be omitted.
    XCTAssertFalse(element(labelContains: "Filesystem", in: app).exists, "Filesystem row rendered for a parity disk, which has none")

    // IO counters are real for parity too, so the Activity section should
    // render with them rather than being omitted entirely.
    app.swipeUp()
    XCTAssertTrue(element(labelContains: "98,112,004", in: app).waitForExistence(timeout: 5), "Reads counter missing or unformatted for a parity disk")
    XCTAssertTrue(element(labelContains: "12,500", in: app).exists, "Writes counter missing or unformatted for a parity disk")
  }

  func testCacheDiskShowsDeviceAndFilesystem() {
    let app = launchOnDashboard()

    let row = app.descendants(matching: .any).matching(identifier: "disk.row.uitest-cache-1").firstMatch
    XCTAssertTrue(row.waitForExistence(timeout: 5), "disk.row.uitest-cache-1 never appeared")
    row.tap()

    XCTAssertTrue(app.navigationBars["cache"].waitForExistence(timeout: 5), "tapping the cache row never pushed its detail screen")

    XCTAssertTrue(element(labelContains: "nvme0n1", in: app).waitForExistence(timeout: 5), "Device row (nvme0n1) missing for a cache disk, which reports a device")
    XCTAssertTrue(element(labelContains: "xfs", in: app).exists, "Filesystem row (xfs) missing for a cache disk")
    XCTAssertTrue(element(labelContains: "Solid state", in: app).exists, "Media row missing or wrong for a non-rotational cache disk")
  }

  // MARK: - Navigate by identifier

  /// The proof that navigating by identifier works: this screen must reflect a
  /// store update made *while it is open*, not just show whatever was true at
  /// push time. A pushed `ArrayDisk` value would never see the dashboard's
  /// 30-second poll again.
  ///
  /// `UITEST_DASHBOARD_STATE=disk-temp-oscillates` flips `uitest-disk-1`'s
  /// temperature between 34°C and 47°C on *every* `dashboard()` call (see
  /// `FakeSystemRepository.Outcome.diskTempOscillates`), and
  /// `UITEST_POLL_INTERVAL_MS` speeds up `DashboardView`'s poll so this
  /// doesn't have to wait out the real 30-second interval. Because the value
  /// alternates on every single call, whatever the Temperature row reads the
  /// moment this test looks, the very next poll is guaranteed to flip it —
  /// there is no timing window where "the screen happened to already be
  /// current" could be mistaken for "the screen updates live", which a
  /// change-only-once fixture could not rule out.
  func testDiskDetailReflectsStoreUpdateMadeWhileScreenIsOpen() {
    let app = XCUIApplication()
    app.launchArguments = ["--uitest-seed-dashboard"]
    app.launchEnvironment["UITEST_DASHBOARD_STATE"] = "disk-temp-oscillates"
    app.launchEnvironment["UITEST_POLL_INTERVAL_MS"] = "250"
    app.launch()

    let row = app.descendants(matching: .any).matching(identifier: "disk.row.uitest-disk-1").firstMatch
    XCTAssertTrue(row.waitForExistence(timeout: 5), "disk.row.uitest-disk-1 never appeared")
    row.tap()
    XCTAssertTrue(app.navigationBars["disk1"].waitForExistence(timeout: 5), "tapping the data disk row never pushed its detail screen")

    let temperatureRow = element(labelContains: "°C", in: app)
    XCTAssertTrue(temperatureRow.waitForExistence(timeout: 5), "Temperature row never appeared on the disk detail screen")
    let initialLabel = temperatureRow.label

    var sawChange = false
    let deadline = Date().addingTimeInterval(5)
    while Date() < deadline {
      if temperatureRow.label != initialLabel {
        sawChange = true
        break
      }
      Thread.sleep(forTimeInterval: 0.15)
    }
    XCTAssertTrue(
      sawChange,
      "disk detail screen's Temperature row never changed while open — still \"\(initialLabel)\", frozen at whatever was true when it was pushed"
    )
  }

  // Not covered here: a disk dropping out of the array while its detail screen
  // is open renders `DiskNotFoundView`. A UI test for it needs the row to be
  // found and tapped before a timed poll removes it, and XCUITest's tap
  // latency makes that ordering racy at any poll interval.
}
