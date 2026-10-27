import XCTest

/// The VMs tab, driven end to end against `FakeVMRepository`.
///
/// Mirrors `DockerUITests`' structure. Every test relaunches the app — XCUITest
/// gives no way to reset app state in-process — so this file keeps its
/// assertions to the behaviours that only a running app can prove, and leaves
/// action-availability rules to `VMActionCatalogTests`, which covers all nine
/// states in milliseconds rather than three of them in a minute.
@MainActor
final class VMUITests: XCTestCase {
  override func setUp() {
    super.setUp()
    continueAfterFailure = false
  }

  private func launchOnVMs(state: String? = nil) -> XCUIApplication {
    let app = XCUIApplication()
    app.launchArguments = ["--uitest-seed-dashboard"]
    if let state { app.launchEnvironment["UITEST_VMS_STATE"] = state }
    app.launch()
    app.buttons["VMs"].firstMatch.tap()
    return app
  }

  private func row(_ id: String, in app: XCUIApplication) -> XCUIElement {
    app.descendants(matching: .any).matching(identifier: "vms.row.\(id)").firstMatch
  }

  /// Matches by label substring rather than exact string — for system-supplied
  /// copy like `ContentUnavailableView.search`'s title, which isn't this app's to
  /// own and gains the query text on some OS versions. Mirrors `DockerUITests`.
  private func element(labelContains substring: String, in app: XCUIApplication) -> XCUIElement {
    app.descendants(matching: .any)
      .matching(NSPredicate(format: "label CONTAINS[c] %@", substring))
      .firstMatch
  }

  // MARK: - List

  func testListRendersEverySeededVM() {
    let app = launchOnVMs()

    for id in ["uitest-vm-1", "uitest-vm-2", "uitest-vm-3", "uitest-vm-4", "uitest-vm-5"] {
      XCTAssertTrue(row(id, in: app).waitForExistence(timeout: 10), "vms.row.\(id) never appeared")
    }
  }

  func testRowStatesReadAsWordsNotOnlyColours() {
    // A state is conveyed in text, not colour alone: the state dot's colour is
    // never the only signal. Each row's merged accessibility label
    // must contain the state's own wording.
    let app = launchOnVMs()

    XCTAssertTrue(row("uitest-vm-1", in: app).waitForExistence(timeout: 10))
    XCTAssertTrue(
      row("uitest-vm-1", in: app).label.contains("Running"),
      "a running VM's row didn't say 'Running': \(row("uitest-vm-1", in: app).label)"
    )
    XCTAssertTrue(
      row("uitest-vm-2", in: app).label.contains("Paused"),
      "a paused VM's row didn't say 'Paused': \(row("uitest-vm-2", in: app).label)"
    )
    XCTAssertTrue(
      row("uitest-vm-4", in: app).label.contains("Shutting Down"),
      "a shutting-down VM's row didn't say so: \(row("uitest-vm-4", in: app).label)"
    )
  }

  func testEachRowReadsAsOneMergedLabel() {
    // Without `.accessibilityElement(children: .combine)` VoiceOver stops on the
    // dot, the name, and the state separately — three swipes per row.
    //
    // Asserted on the merged *label*, not on a child count: a combined element
    // still exposes its children to XCUITest queries, so `staticTexts.count`
    // is not 0. The label is what VoiceOver reads.
    let app = launchOnVMs()
    let vm = row("uitest-vm-1", in: app)

    XCTAssertTrue(vm.waitForExistence(timeout: 10))
    XCTAssertEqual(vm.label, "Running, Arcade Box")
    // The visible subtitle repeats the state for sighted users and
    // is `accessibilityHidden`, so VoiceOver must hear it exactly once.
    XCTAssertEqual(
      vm.label.components(separatedBy: "Running").count - 1, 1,
      "state should be announced exactly once, got \"\(vm.label)\""
    )
  }

  func testSearchNarrowsToOneVMAndShowsNoResultsForAMiss() {
    let app = launchOnVMs()
    XCTAssertTrue(row("uitest-vm-1", in: app).waitForExistence(timeout: 10))

    // Reveals the field first on iPad — see `XCTestCase+Search.swift`.
    let field = searchField(prompt: "Search VMs", in: app, timeout: 10)
    XCTAssertTrue(field.waitForExistence(timeout: 10), "the search field never appeared")
    // `type(_:into:)` waits for real keyboard focus rather than typing straight
    // after the tap — see `XCTestCase+Typing.swift`.
    type("arcade", into: field)

    XCTAssertTrue(row("uitest-vm-1", in: app).waitForExistence(timeout: 10))
    XCTAssertFalse(row("uitest-vm-3", in: app).exists, "search didn't filter out non-matching VMs")

    field.typeText("-no-such-vm")
    XCTAssertTrue(
      element(labelContains: "No Results", in: app).waitForExistence(timeout: 10),
      "a search matching nothing didn't show ContentUnavailableView.search"
    )
    XCTAssertFalse(
      app.descendants(matching: .any).matching(identifier: "vms.empty").firstMatch.exists,
      "showed the \"No VMs\" empty state for a failed search — the server has five"
    )
  }

  // MARK: - Unavailable vs. empty

  func testUnavailableStateDoesNotClaimTheServerHasNoVMs() {
    // The distinction the VM data layer exists to preserve, asserted
    // where a user would actually see it: `vms.domains == null` means the VM
    // manager isn't reporting, and saying "No VMs" there is a claim about their
    // server Tower cannot make.
    let app = launchOnVMs(state: "unavailable")

    let unavailable = app.descendants(matching: .any)
      .matching(identifier: "vms.unavailable").firstMatch
    XCTAssertTrue(unavailable.waitForExistence(timeout: 10), "the VMs-unavailable state never appeared")
    XCTAssertFalse(
      app.staticTexts["No VMs"].exists,
      "an unreporting VM manager was described as a server with no VMs"
    )
  }

  func testEmptyStateSaysTheServerHasNoVMs() {
    let app = launchOnVMs(state: "empty")

    let empty = app.descendants(matching: .any).matching(identifier: "vms.empty").firstMatch
    XCTAssertTrue(empty.waitForExistence(timeout: 10), "the no-VMs state never appeared")
    XCTAssertFalse(
      app.descendants(matching: .any).matching(identifier: "vms.unavailable").firstMatch.exists,
      "a healthy server with no VMs was described as unavailable"
    )
  }

  // MARK: - Detail

  func testDetailOffersTheRunningActionSetAndNotStart() {
    let app = launchOnVMs()
    XCTAssertTrue(row("uitest-vm-1", in: app).waitForExistence(timeout: 10))
    row("uitest-vm-1", in: app).tap()

    for action in ["stop", "pause", "reboot", "forceStop", "reset"] {
      XCTAssertTrue(
        app.buttons["vmDetail.action.\(action)"].waitForExistence(timeout: 10),
        "a running VM's detail didn't offer \(action)"
      )
    }
    XCTAssertFalse(
      app.buttons["vmDetail.action.start"].exists,
      "a running VM was offered Start, which libvirt rejects"
    )
  }

  func testDetailOffersOnlyStartForAStoppedVM() {
    let app = launchOnVMs()
    XCTAssertTrue(row("uitest-vm-3", in: app).waitForExistence(timeout: 10))
    row("uitest-vm-3", in: app).tap()

    XCTAssertTrue(app.buttons["vmDetail.action.start"].waitForExistence(timeout: 10))
    for action in ["stop", "pause", "reboot", "forceStop", "reset"] {
      XCTAssertFalse(
        app.buttons["vmDetail.action.\(action)"].exists,
        "a stopped VM was offered \(action)"
      )
    }
  }

  func testDetailOffersOnlyForceStopForAShuttingDownVM() {
    // The `.indeterminate` bucket. A VM mid-shutdown is not off yet, so Start
    // would be rejected; Force Stop is the one lever that makes sense.
    let app = launchOnVMs()
    XCTAssertTrue(row("uitest-vm-4", in: app).waitForExistence(timeout: 10))
    row("uitest-vm-4", in: app).tap()

    XCTAssertTrue(app.buttons["vmDetail.action.forceStop"].waitForExistence(timeout: 10))
    for action in ["start", "stop", "pause", "resume", "reboot", "reset"] {
      XCTAssertFalse(
        app.buttons["vmDetail.action.\(action)"].exists,
        "a shutting-down VM was offered \(action)"
      )
    }
  }

  // MARK: - Actions

  func testStartingAStoppedVMChangesItsRow() {
    // The whole point of `FakeVMRepository` mutating in memory: with the actions
    // returning no state, `VMStore.perform(_:on:)` re-fetches, and this is what
    // proves the re-fetch reaches the screen.
    let app = launchOnVMs()
    let debian = row("uitest-vm-3", in: app)
    XCTAssertTrue(debian.waitForExistence(timeout: 10))
    XCTAssertTrue(debian.label.contains("Stopped"), "fixture precondition: uitest-vm-3 starts stopped")

    debian.tap()
    let start = app.buttons["vmDetail.action.start"]
    XCTAssertTrue(start.waitForExistence(timeout: 10))
    start.tap()

    // Start needs no confirmation, so the state row should flip on its own.
    let state = app.descendants(matching: .any).matching(identifier: "vmDetail.state").firstMatch
    XCTAssertTrue(state.waitForExistence(timeout: 10))
    XCTAssertTrue(
      waitForLabel(state, toContain: "Running", timeout: 10),
      "the detail screen never reflected the started VM: \(state.label)"
    )
  }

  func testARefusedActionKeepsTheListAndSurfacesTheRefusal() {
    // `uitest-vm-5` refuses every action with `AppError.actionRefused`. The list
    // has to survive it and the message has to appear — a refusal that shows
    // nothing is indistinguishable from a button that does nothing.
    let app = launchOnVMs()
    let refusingVM = row("uitest-vm-5", in: app)
    XCTAssertTrue(refusingVM.waitForExistence(timeout: 10))

    refusingVM.tap()
    let start = app.buttons["vmDetail.action.start"]
    XCTAssertTrue(start.waitForExistence(timeout: 10))
    start.tap()

    // Back to the list to read the error banner, which lives there — but only
    // where the list had to be left to reach the detail at all. On iPad the two
    // are side by side, so the banner is already on screen and there is no
    // Back button to tap.
    let banner = app.descendants(matching: .any).matching(identifier: "vms.actionError").firstMatch
    if !banner.waitForExistence(timeout: 5) {
      tapBack(in: app)
    }
    XCTAssertTrue(banner.waitForExistence(timeout: 10), "a refused action surfaced no message")
    XCTAssertTrue(
      banner.label.contains("refused"),
      "the refusal message didn't read as a refusal: \(banner.label)"
    )
    XCTAssertTrue(
      row("uitest-vm-1", in: app).exists,
      "the list was blanked by a failed action instead of being preserved"
    )
  }

  // MARK: - Helpers

  /// Polls an element's label rather than its existence — `waitForExistence`
  /// returns immediately for an element that is already there but whose text
  /// hasn't updated yet, which is exactly the case when waiting for a state
  /// change on a screen that is already open.
  private func waitForLabel(
    _ element: XCUIElement, toContain text: String, timeout: TimeInterval
  ) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
      if element.exists, element.label.contains(text) { return true }
      _ = element.waitForExistence(timeout: 0.5)
    }
    return false
  }
}
