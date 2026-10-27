import UIKit
import XCTest

/// Walks the seeded app and writes a PNG per screen, so a change can be
/// *looked at* rather than only asserted about.
///
/// **Why PNGs on disk and not `XCTAttachment`.** `xcodebuild`'s xcresult export
/// hangs after the suite finishes rather than producing attachments, so the
/// only reliable way out is for the test itself to write the file. A simulator
/// test process is an ordinary macOS process, so `/tmp` here is the host's
/// `/tmp`.
///
/// To write them somewhere else, set **`TEST_RUNNER_TOWER_SCREENSHOT_DIR`** in
/// the host environment — not `TOWER_SCREENSHOT_DIR`, and not
/// `launchEnvironment`. This code runs in the *runner*, not in the app under
/// test, and `xcodebuild` forwards only `TEST_RUNNER_`-prefixed host variables
/// into it (stripping the prefix). An unprefixed `TOWER_SCREENSHOT_DIR` is
/// ignored, and the tour writes to the default path.
///
/// This is the seeded screenshot tour: how work gets demonstrated, and the
/// source of the App Store screenshots (`scripts/screenshots.sh`). It grows one
/// method per screen.
///
/// It asserts, rather than only capturing: a screenshot of a blank or wrong
/// screen is worse than no screenshot, because it looks like evidence.
///
/// `@MainActor` like every other UI test class here: XCUITest's API is
/// main-actor-isolated, and without it Swift 6 emits a warning per call.
///
/// Tab taps use `.firstMatch` throughout, and so do the other UI test files. On
/// iPad, `.tabViewStyle(.sidebarAdaptable)` renders the tabs **twice** — a top
/// tab bar plus the collapsed sidebar behind its toggle — so `app.buttons["VMs"]`
/// resolves to two elements and `tap()` fails with "Multiple matching elements
/// found". On iPhone there is exactly one, so `.firstMatch` costs nothing there
/// and is what lets the same suite run on both.
@MainActor
final class ScreenshotTourUITests: XCTestCase {
  override func setUp() {
    super.setUp()
    continueAfterFailure = false
  }

  func testCaptureVMsTab() throws {
    let app = XCUIApplication()
    app.launchArguments = ["--uitest-seed-dashboard"]
    app.launch()

    app.buttons["VMs"].firstMatch.tap()

    let content = app.descendants(matching: .any).matching(identifier: "tab.vms.content").firstMatch
    XCTAssertTrue(content.waitForExistence(timeout: 10), "VMs tab never showed its content")
    // The seeded inventory, so a screenshot of an empty list can't pass as one
    // of a populated one.
    XCTAssertTrue(
      app.staticTexts["Arcade Box"].waitForExistence(timeout: 10),
      "seeded VM list never rendered"
    )

    try capture(named: "vms-list")
  }

  /// The detail screen for a running VM — the state where the full action set
  /// appears — and the Force Stop confirmation, which is the one piece of VM
  /// copy that has to be read to be trusted.
  func testCaptureVMDetailAndForceStopConfirmation() throws {
    let app = XCUIApplication()
    app.launchArguments = ["--uitest-seed-dashboard"]
    app.launch()

    app.buttons["VMs"].firstMatch.tap()

    let row = app.descendants(matching: .any).matching(identifier: "vms.row.uitest-vm-1").firstMatch
    XCTAssertTrue(row.waitForExistence(timeout: 10), "the running VM's row never appeared")
    row.tap()

    let forceStop = app.buttons["vmDetail.action.forceStop"]
    // The action rows sit under the detail's info sections, which are taller
    // than the iPad's detail column.
    XCTAssertTrue(
      scrollTo(forceStop, in: app, attempts: 8),
      "Force Stop never appeared on a running VM's detail")
    try capture(named: "vm-detail-running")

    forceStop.tap()

    // The dialog, not the button: this is the assertion that the warning copy
    // actually reaches the screen rather than only existing in the catalog.
    let warning = app.staticTexts.containing(
      NSPredicate(format: "label CONTAINS %@", "pulling the plug")
    ).firstMatch
    XCTAssertTrue(warning.waitForExistence(timeout: 10), "Force Stop's confirmation didn't explain what it does")
    try capture(named: "vm-force-stop-confirmation")

    // Deliberately does not dismiss the dialog, for two reasons:
    //
    // 1. There is no Cancel button to tap. The dialog declares
    //    `Button("Cancel", role: .cancel)`, but on iOS 26 SwiftUI renders this
    //    presentation as a popover anchored to the tapped row and drops that
    //    button entirely — dismissal is tap-outside. The declaration stays (it
    //    does render in other presentation styles, and `ContainerRow` matches),
    //    but nothing can assert on it here.
    // 2. Driving that outside-tap from XCUITest does not reliably dismiss the
    //    popover either, and chasing it further would be testing SwiftUI's
    //    popover mechanics rather than anything in this app.
    // The action is never confirmed, so nothing runs; the test ends with the
    // dialog open and the app is torn down. What this test is *for* — that the
    // warning copy reaches the screen, and a picture of it — is already
    // asserted above.
  }

  /// The Shares tab and a share's detail — specifically the Pool section, whose
  /// footer says the figures are the pool's, not the share's, because Unraid
  /// reports the pool's usage on every share in it. A screenshot is the only
  /// way to confirm the disclaimer is actually legible next to the numbers
  /// rather than merely present in the tree.
  func testCaptureSharesTabAndDetail() throws {
    let app = XCUIApplication()
    app.launchArguments = ["--uitest-seed-dashboard"]
    app.launch()

    app.buttons["Shares"].firstMatch.tap()

    let content = app.descendants(matching: .any).matching(identifier: "tab.shares.content").firstMatch
    XCTAssertTrue(content.waitForExistence(timeout: 10), "Shares tab never showed its content")
    XCTAssertTrue(
      app.staticTexts["scanned paperwork"].waitForExistence(timeout: 10),
      "the seeded share comments never rendered"
    )
    try capture(named: "shares-list")

    app.descendants(matching: .any).matching(identifier: "shares.row.uitest-share-domains")
      .firstMatch.tap()

    // The **header**, not the footer. On an iPhone this section lands at the
    // bottom of the screen, where a footer sits behind the tab bar, which is why
    // the qualifier is in the header. Asserting on `isHittable` rather than
    // `exists` is the difference: a footer scrolled off the bottom still exists.
    let header = app.descendants(matching: .any)
      .matching(identifier: "shareDetail.poolHeader").firstMatch
    XCTAssertTrue(
      header.waitForExistence(timeout: 10),
      "the Pool section shipped without the header saying these are the pool's figures"
    )
    XCTAssertTrue(
      header.isHittable,
      "the Pool qualifier is on screen but not visible without scrolling — the failure this assertion exists for"
    )
    try capture(named: "share-detail")
  }

  /// The notification sheet — the bell's badge, the bucket picker, and the rows
  /// whose importance has to read as a shape and a word, not only a tint.
  func testCaptureNotificationSheet() throws {
    let app = XCUIApplication()
    app.launchArguments = ["--uitest-seed-dashboard"]
    app.launch()

    let bell = app.buttons["toolbar.notifications"]
    XCTAssertTrue(bell.waitForExistence(timeout: 10), "the notification bell never appeared")
    try capture(named: "notification-bell")

    bell.tap()

    XCTAssertTrue(
      app.staticTexts["UPS Alert"].waitForExistence(timeout: 10),
      "the seeded notifications never rendered"
    )
    try capture(named: "notification-sheet-unread")

    app.buttons["Archive"].firstMatch.tap()
    XCTAssertTrue(
      app.staticTexts["Array started"].waitForExistence(timeout: 10),
      "switching to the archive bucket showed no archived notification"
    )
    try capture(named: "notification-sheet-archive")
  }

  /// Settings — the System section fed by the dashboard's own reading, the theme
  /// picker, and the rest of the sheet.
  func testCaptureSettings() throws {
    let app = XCUIApplication()
    app.launchArguments = ["--uitest-seed-dashboard"]
    app.launch()

    // Waits for the *dashboard* to finish loading before opening Settings. The
    // System section is fed by whatever `DashboardStore` last read, so opening the
    // sheet during the first load legitimately shows no System section. A test
    // that taps the gear immediately fails with the app behaving correctly.
    XCTAssertTrue(
      app.descendants(matching: .any).matching(identifier: "services.docker")
        .firstMatch.waitForExistence(timeout: 15),
      "the dashboard never finished loading"
    )

    let gear = app.buttons["toolbar.settings"]
    XCTAssertTrue(gear.waitForExistence(timeout: 10), "the settings gear never appeared")
    gear.tap()

    // Two traps in the query:
    //
    // 1. `LabeledContent` merges its label and value into one element, so this
    //    element's label is `"OS, Unraid OS 7.3.0"`, not the value alone —
    //    matched by substring rather than equality. Asserting on the bare value
    //    fails while the section renders correctly.
    // 2. The query has to be `app.staticTexts`, not
    //    `app.descendants(matching: .any)`. The latter with a label predicate
    //    matches nothing here even though the element is in the tree; dumping
    //    `app.staticTexts.allElementsBoundByIndex.map(\.label)` shows it.
    XCTAssertTrue(
      app.staticTexts
        .matching(NSPredicate(format: "label CONTAINS[c] %@", "Unraid OS 7.3.0"))
        .firstMatch.waitForExistence(timeout: 10),
      "the System section didn't render the dashboard's OS reading"
    )
    // Scrolls if needed. On iPhone the picker is on the first screenful; on iPad
    // the sheet is a *centered form sheet* — narrower and shorter than the device
    // — so more of the list sits below the fold, and a SwiftUI `List` doesn't
    // render rows it hasn't scrolled to. Same shape as the Sign Out case in
    // `DemoModeUITests`.
    // Uptime is the row most likely to be silently wrong: `bootTimestamp` is a
    // boot *time*, and rendering it raw would put a date where a duration
    // belongs. Asserted *before* scrolling on to the theme picker — on iPad the
    // sheet is short enough that reaching the picker scrolls Uptime off the top,
    // and a `List` drops rows it has scrolled past, so asserting it after the
    // scroll fails there while passing on a phone.
    let uptime = app.descendants(matching: .any).matching(identifier: "settings.uptime")
      .firstMatch
    XCTAssertTrue(scrollTo(uptime, in: app, attempts: 8), "the Uptime row never rendered")

    let theme = app.descendants(matching: .any).matching(identifier: "settings.theme").firstMatch
    XCTAssertTrue(scrollTo(theme, in: app, attempts: 8), "the theme picker never appeared")
    try capture(named: "settings")
  }

  /// The syslog viewer — the file list (including a 0-byte file labelled "Empty")
  /// and a truncated log's tail, with the footer that says it's a tail.
  func testCaptureSyslogViewer() throws {
    let app = XCUIApplication()
    app.launchArguments = ["--uitest-seed-dashboard"]
    app.launch()

    app.buttons["toolbar.settings"].tap()
    let logs = app.descendants(matching: .any).matching(identifier: "settings.logs").firstMatch
    // Below the fold in iPad's centered form sheet.
    XCTAssertTrue(scrollTo(logs, in: app, attempts: 8), "Settings had no Logs row")
    logs.tap()

    let dockerLog = app.descendants(matching: .any)
      .matching(identifier: "logs.row.docker.log").firstMatch
    XCTAssertTrue(dockerLog.waitForExistence(timeout: 10), "the log file list never rendered")
    // The 0-byte file has to say so in the list rather than opening to a blank
    // screen — empty log files are common.
    XCTAssertTrue(
      app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", "Empty")).firstMatch.exists,
      "a 0-byte log file wasn't labelled in the list"
    )
    try capture(named: "log-file-list")

    dockerLog.tap()

    // Waits on a *line*, not on the `ScrollView`'s own identifier: a scroll
    // container doesn't reliably surface as an addressable element, and the lines
    // are the thing this screen exists to show. Waiting on `logFile.contents`
    // times out while the viewer renders correctly.
    XCTAssertTrue(
      app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "docker.log line"))
        .firstMatch.waitForExistence(timeout: 10),
      "the log viewer never rendered any lines"
    )
    // The footer distinguishing a tail from a whole file: someone searching a log
    // needs to know which they're looking at.
    let footer = app.descendants(matching: .any).matching(identifier: "logFile.lineCount").firstMatch
    XCTAssertTrue(footer.waitForExistence(timeout: 10), "the viewer showed no line count")
    XCTAssertTrue(
      footer.label.contains("of"),
      "a truncated log's footer didn't say it was showing a subset: \(footer.label)"
    )
    try capture(named: "log-file-viewer")
  }

  /// Demo mode, from the connect screen — the path an App Store reviewer takes,
  /// and the dataset the store screenshots come from.
  ///
  /// **Capture names are semantic, and the tour does not decide the store
  /// order.** The `LISTING` array in `scripts/screenshots.sh` picks which
  /// captures ship and numbers them, so capture order here is free to follow
  /// navigation: connect comes first because tapping through it is how the
  /// tour reaches demo mode. A capture `LISTING` does not name is verification
  /// evidence and never reaches a listing.
  func testCaptureDemoMode() throws {
    let app = XCUIApplication()
    app.launchArguments = ["--uitest-reset-credentials"]
    app.launch()

    let demo = app.buttons["connect.demo"]
    XCTAssertTrue(demo.waitForExistence(timeout: 15), "the connect screen offered no demo")
    try capture(named: "connect")

    demo.tap()
    XCTAssertTrue(
      app.descendants(matching: .any).matching(identifier: "services.docker")
        .firstMatch.waitForExistence(timeout: 15),
      "the demo never reached a loaded dashboard"
    )
    try capture(named: "dashboard")

    app.buttons["Docker"].firstMatch.tap()
    XCTAssertTrue(app.staticTexts["code-server"].waitForExistence(timeout: 15))
    selectOnIPad(app.staticTexts["code-server"])
    try capture(named: "docker")

    app.buttons["VMs"].firstMatch.tap()
    XCTAssertTrue(app.staticTexts["Debian Desktop"].waitForExistence(timeout: 15))
    selectOnIPad(app.staticTexts["Debian Desktop"])
    try capture(named: "vms")

    app.buttons["Shares"].firstMatch.tap()
    XCTAssertTrue(app.staticTexts["appdata"].waitForExistence(timeout: 15))
    selectOnIPad(app.staticTexts["appdata"])
    try capture(named: "shares")

    try captureArrScreens(in: app)
  }

  /// The *arr screens, captured as part of the demo tour.
  ///
  /// A movie or series detail is deliberately left out. It is mostly a poster
  /// and a metadata list, and the demo has no artwork, so it photographs as an
  /// empty grey rectangle above text.
  private func captureArrScreens(in app: XCUIApplication) throws {
    app.buttons["Services"].firstMatch.tap()

    let radarr = app.descendants(matching: .any)
      .matching(identifier: "services.row.D0000000-0000-0000-0000-000000000001").firstMatch
    XCTAssertTrue(radarr.waitForExistence(timeout: 15), "the demo hub never offered a Radarr")
    // Both states on screen before the shutter: a hub of uniformly green rows
    // advertises less than one that shows the app noticing a service is down.
    XCTAssertTrue(
      app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Unreachable'"))
        .firstMatch.exists,
      "no failing service visible on the hub screenshot")

    // On iPad the hub is the *sidebar*, so a bare hub shot spends two thirds of
    // the frame on "No Service Selected". Prowlarr fills the detail column: it
    // is the one service with a screen that appears nowhere else in the
    // listing, so the hub shot shows the split view working without repeating
    // a later screenshot.
    selectOnIPad(
      app.descendants(matching: .any)
        .matching(identifier: "services.row.D0000000-0000-0000-0000-000000000007").firstMatch)
    // The detail column loads on selection, and a shot taken at once shows
    // "Loading indexers…".
    if UIDevice.current.userInterfaceIdiom == .pad {
      XCTAssertTrue(
        app.descendants(matching: .any)
          .matching(NSPredicate(format: "identifier BEGINSWITH 'prowlarr.toggle.'")).firstMatch
          .waitForExistence(timeout: 20),
        "the demo Prowlarr indexers never loaded beside the hub")
    }
    try capture(named: "services")

    radarr.tap()
    // A populated library, not a spinner — the whole risk with a latency-seeded
    // demo is photographing the loading state. Asserted on the first row rather
    // than a chosen film: the library sorts alphabetically, so which id leads is
    // a property of the fixture titles and not worth pinning a screenshot to.
    let row = app.descendants(matching: .any)
      .matching(NSPredicate(format: "identifier BEGINSWITH 'radarr.row.'")).firstMatch
    XCTAssertTrue(row.waitForExistence(timeout: 20), "the demo library never loaded")
    XCTAssertTrue(
      app.staticTexts["Anvil Road"].exists, "the demo library's first film never rendered")
    try capture(named: "radarr-library")

    try captureInteractiveSearch(from: row, in: app)

    app.buttons["Queue"].firstMatch.tap()
    let queued = app.descendants(matching: .any)
      .matching(NSPredicate(format: "identifier BEGINSWITH 'queue.row.'")).firstMatch
    XCTAssertTrue(queued.waitForExistence(timeout: 20), "the demo queue never loaded")
    try capture(named: "radarr-queue")

    try captureDownloadClient(in: app)
    try captureRequestsAndIndexers(in: app)
  }

  /// The interactive search sheet.
  ///
  /// The screen that separates Tower from a status dashboard: scored releases,
  /// the *arr's own rejection reasons, and a grab you can perform from a phone.
  /// Reached from the library rather than seeded, so it photographs the demo
  /// path a reviewer can follow themselves.
  private func captureInteractiveSearch(
    from row: XCUIElement, in app: XCUIApplication
  ) throws {
    row.tap()
    let search = app.descendants(matching: .any)
      .matching(identifier: "radarr.detail.interactiveSearch").firstMatch
    XCTAssertTrue(scrollTo(search, in: app, attempts: 12), "no interactive search button")
    search.tap()

    let release = app.descendants(matching: .any)
      .matching(NSPredicate(format: "identifier BEGINSWITH 'search.release.'")).firstMatch
    XCTAssertTrue(release.waitForExistence(timeout: 25), "the demo search never returned")
    try capture(named: "search")

    // Back to the library: the queue capture below navigates from the shell,
    // and a sheet plus a pushed detail would still be covering it.
    app.buttons["search.done"].firstMatch.tap()
    let back = app.navigationBars.buttons.matching(
      NSPredicate(format: "identifier == 'BackButton' OR label == 'Radarr' OR label == 'Back'")
    ).firstMatch
    if back.waitForExistence(timeout: 5), back.isHittable { back.tap() }
    XCTAssertTrue(
      app.buttons["Queue"].firstMatch.waitForExistence(timeout: 15),
      "never got back to the *arr shell after the search")
  }

  /// Overseerr's requests and Prowlarr's indexers.
  ///
  /// Requests is the screen that makes the media stack feel like something
  /// other people use, and the indexer list is the one that shows Tower
  /// noticing a problem — between them they cover both services.
  private func captureRequestsAndIndexers(in app: XCUIApplication) throws {
    app.buttons["Services"].firstMatch.tap()

    let overseerr = app.descendants(matching: .any)
      .matching(identifier: "services.row.D0000000-0000-0000-0000-000000000006").firstMatch
    XCTAssertTrue(scrollTo(overseerr, in: app), "the demo hub never offered an Overseerr")
    overseerr.tap()

    let request = app.descendants(matching: .any)
      .matching(NSPredicate(format: "identifier BEGINSWITH 'overseerr.row.'")).firstMatch
    XCTAssertTrue(request.waitForExistence(timeout: 25), "the demo requests list never loaded")
    try capture(named: "requests")

    app.buttons["Services"].firstMatch.tap()
    let prowlarr = app.descendants(matching: .any)
      .matching(identifier: "services.row.D0000000-0000-0000-0000-000000000007").firstMatch
    XCTAssertTrue(scrollTo(prowlarr, in: app), "the demo hub never offered a Prowlarr")
    prowlarr.tap()

    let indexer = app.descendants(matching: .any)
      .matching(NSPredicate(format: "identifier BEGINSWITH 'prowlarr.toggle.'")).firstMatch
    XCTAssertTrue(indexer.waitForExistence(timeout: 25), "the demo indexer list never loaded")
    // The failing-indexer banner is the point of this screenshot — a list of
    // uniformly healthy rows shows nothing the app does for you.
    XCTAssertTrue(
      app.descendants(matching: .any).matching(identifier: "prowlarr.failingCount")
        .firstMatch.exists,
      "no failing indexer visible in the indexer screenshot")
    try capture(named: "indexers")

    try captureMusic(in: app)
    try captureSubtitles(in: app)
    try captureStreams(in: app)
  }

  /// Tautulli's activity screen.
  ///
  /// The monitoring capstone, and the one demo screen that shows the server
  /// doing something rather than holding something.
  private func captureStreams(in app: XCUIApplication) throws {
    let tautulli = openHubRow("D0000000-0000-0000-0000-000000000010", in: app, named: "Tautulli")
    tautulli.tap()

    let stream = app.descendants(matching: .any)
      .matching(NSPredicate(format: "identifier BEGINSWITH 'tautulli.stream.'")).firstMatch
    XCTAssertTrue(stream.waitForExistence(timeout: 25), "the demo activity never loaded")
    // The summary is derived from the streams, so its presence is what proves
    // this is a loaded dataset rather than a spinner that happened to finish.
    XCTAssertTrue(
      app.descendants(matching: .any).matching(identifier: "tautulli.summary")
        .firstMatch.exists,
      "the activity header never rendered")
    try capture(named: "streams")
  }

  /// Finds a service hub row and gets it on screen, in both directions.
  ///
  /// `scrollTo` only ever swipes *forward*, and the hub keeps whatever scroll
  /// position the previous service left behind. A row above the fold still
  /// `exists` — SwiftUI keeps rendered rows in the tree — so tapping it lands
  /// on empty space and the tour walks on believing it navigated: tapped, no
  /// push, then a long wait for a library that was never opened.
  private func openHubRow(
    _ id: String, in app: XCUIApplication, named name: String
  ) -> XCUIElement {
    app.buttons["Services"].firstMatch.tap()
    // Back to the top first, so `scrollTo`'s forward-only search starts from a
    // known position rather than wherever the last service left it.
    for _ in 0..<4 { app.swipeDown() }

    let row = app.descendants(matching: .any)
      .matching(identifier: "services.row.\(id)").firstMatch
    XCTAssertTrue(scrollTo(row, in: app), "the demo hub never offered a \(name)")
    XCTAssertTrue(row.isHittable, "the \(name) row was in the tree but off screen")
    return row
  }

  /// Lidarr's library.
  private func captureMusic(in app: XCUIApplication) throws {
    let lidarr = openHubRow("D0000000-0000-0000-0000-000000000004", in: app, named: "Lidarr")
    lidarr.tap()

    // The Wandering Signal: the artist with albums in every state. The first
    // row is an unmonitored artist with nothing on disk, which makes an empty
    // detail column.
    let artist = app.descendants(matching: .any).matching(identifier: "lidarr.row.1").firstMatch
    XCTAssertTrue(artist.waitForExistence(timeout: 25), "the demo music library never loaded")
    // The detail column is what carries the albums on iPad; on iPhone this is
    // the library list itself.
    selectOnIPad(artist)
    try capture(named: "music")
  }

  /// Bazarr's wanted list.
  private func captureSubtitles(in app: XCUIApplication) throws {
    let bazarr = openHubRow("D0000000-0000-0000-0000-000000000005", in: app, named: "Bazarr")
    bazarr.tap()

    // The count, not just a row: "5 subtitles wanted" is what makes this
    // screenshot legible to someone who has never used Bazarr.
    XCTAssertTrue(
      app.descendants(matching: .any).matching(identifier: "bazarr.wantedCount")
        .firstMatch.waitForExistence(timeout: 25),
      "the demo wanted list never loaded")
    try capture(named: "subtitles")
  }

  /// A download client. Not in the store listing.
  private func captureDownloadClient(in app: XCUIApplication) throws {
    app.buttons["Services"].firstMatch.tap()

    let client = app.descendants(matching: .any)
      .matching(identifier: "services.row.D0000000-0000-0000-0000-000000000009").firstMatch
    XCTAssertTrue(
      scrollTo(client, in: app), "the demo hub never offered an NZBGet")
    client.tap()

    let row = app.descendants(matching: .any)
      .matching(NSPredicate(format: "identifier BEGINSWITH 'nzbget.row.'")).firstMatch
    XCTAssertTrue(row.waitForExistence(timeout: 25), "the demo NZBGet queue never loaded")
    // The header is derived from the queue, so its presence is what proves this
    // is a loaded dataset rather than a spinner that happened to finish.
    XCTAssertTrue(
      app.descendants(matching: .any).matching(identifier: "nzbget.summary")
        .firstMatch.exists,
      "the status header never rendered")
    try capture(named: "downloads")
  }

  /// Fills the iPad's detail column before a store screenshot is taken, and
  /// does nothing on iPhone, where these tabs are still a single
  /// pushing list and a tap here would capture the detail screen instead of the
  /// list the caller asked for.
  ///
  /// What the listing shows is whatever the tour happened to leave on screen,
  /// and an iPad screenshot of a list beside "No Container Selected"
  /// advertises the empty state.
  private func selectOnIPad(_ row: XCUIElement) {
    guard UIDevice.current.userInterfaceIdiom == .pad else { return }
    row.tap()
  }

  // MARK: - Capture

  private func capture(named name: String) throws {
    let directory = ProcessInfo.processInfo.environment["TOWER_SCREENSHOT_DIR"] ?? "/tmp/tower-screenshots"
    try FileManager.default.createDirectory(
      atPath: directory, withIntermediateDirectories: true
    )
    let path = (directory as NSString).appendingPathComponent("\(name).png")
    try XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: path))
    // Printed so the run's own log says where the file went — otherwise a
    // reader has to know the default path to find the evidence.
    print("[screenshot] \(path)")
  }
}
