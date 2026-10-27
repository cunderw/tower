import XCTest

/// The Docker tab's behavioural coverage: the loaded list, search
/// narrowing and its empty state, a swipe action actually mutating a row, a
/// failed action keeping the list while surfacing the error, and the two
/// consequences of navigating by identifier on the detail screen — it
/// reflects a mutation fired from its own Actions section, and it renders
/// not-found when its container leaves the array while it is open.
///
/// Everything here drives `FakeDockerRepository` (see `UITestSupport.swift`)
/// through `--uitest-seed-dashboard`, so no Unraid server and no keychain
/// access is involved — which also means the mutation tests below are free,
/// unlike the same actions against a real server.
///
/// Like `DiskDetailUITests` and `DashboardServicesUITests`, this uses
/// XCUITest's own `.tap()`/`.swipeRight()`, which is the right tool for a test
/// regardless: real on-device event synthesis. `idb ui tap` does nothing on
/// macOS 27 (see `DashboardServicesUITests`).
///
/// **No `UITEST_POLL_INTERVAL_MS` in the mutation tests, deliberately.**
/// `FakeDockerRepository.containers()` returns the same fixed states on every
/// call, so a sped-up poll would overwrite a just-mutated row back to its
/// fixture state and make `testSwipeActionStartsAnExitedContainer` fail for a
/// reason that has nothing to do with what it tests. The real 30-second
/// default is left alone — no test here runs anywhere near that long, so the
/// poll never fires during one. The one test that *needs* a second
/// `containers()` call gets it from an event (backgrounding the app), not from
/// waiting out a timer; see `testDetailShowsNotFoundWhenContainerVanishesWhileOpen`.
@MainActor
final class DockerUITests: XCTestCase {
  /// Launches and lands on the Docker tab. `state` sets
  /// `UITEST_DOCKER_STATE`, which only `FakeDockerRepository.containers()`
  /// reads — unset (the default) means every call returns all six fixtures.
  private func launchOnDocker(state: String? = nil) -> XCUIApplication {
    let app = XCUIApplication()
    app.launchArguments = ["--uitest-seed-dashboard"]
    if let state { app.launchEnvironment["UITEST_DOCKER_STATE"] = state }
    app.launch()
    app.buttons["Docker"].firstMatch.tap()
    return app
  }

  /// `ContainerRow` sets its identifier on the merged row element, and in the
  /// compact layout `DockerListView` wraps that in a `NavigationLink` — SwiftUI
  /// puts the identifier on *both* the resulting `Button` and the merged
  /// `Other` inside it, so any query by this identifier matches two elements
  /// per row.
  /// `.firstMatch` is therefore mandatory here, and counting rows must go
  /// through `app.cells` rather than this identifier — see `rowCount(in:)`.
  ///
  /// In the iPad split layout there is no `NavigationLink`, so the same
  /// query matches one element instead of two. `.firstMatch` covers both.
  private func row(_ id: String, in app: XCUIApplication) -> XCUIElement {
    app.descendants(matching: .any).matching(identifier: "docker.row.\(id)").firstMatch
  }

  /// Waits for the row for `id` to read as `state` — the row's merged
  /// accessibility label always begins with `ContainerState.displayName`
  /// (`StateDot`'s own label comes first in the merge), so this is how a
  /// state *change* is observed without polling a label in a loop.
  private func rowExists(_ id: String, reading state: String, in app: XCUIApplication) -> XCUIElement {
    app.descendants(matching: .any)
      .matching(NSPredicate(format: "identifier == %@ AND label BEGINSWITH %@", "docker.row.\(id)", state))
      .firstMatch
  }

  /// One `List` cell per visible container. In the loaded state that is
  /// exactly the container count; in `.actionFailed` there is one extra cell
  /// for the error text `DockerListView` puts at the top of the list.
  private func rowCount(in app: XCUIApplication) -> Int { app.cells.count }

  /// Runs a row's leading Start action, whichever way the swipe resolves.
  ///
  /// A leading swipe that travels far enough **commits** its action instead of
  /// parking the row open with the button showing, and in the iPad split
  /// layout the list column is narrow enough that `swipeRight()` always goes
  /// that far: one full-width drag across `docker.row.uitest-container-2`
  /// flips it from Exited to Running with no button ever appearing. That is
  /// the swipe action working, not failing, so requiring the button to exist
  /// first would assert on the width of the column, not on the behaviour.
  ///
  /// What the caller actually cares about is unchanged and still asserted by
  /// the caller: the row's own state afterwards.
  private func startBySwipe(_ id: String, in app: XCUIApplication) {
    row(id, in: app).swipeRight()
    let start = app.buttons["Start"]
    if start.waitForExistence(timeout: 5) { start.tap() }
  }

  private func element(labelContains substring: String, in app: XCUIApplication) -> XCUIElement {
    app.descendants(matching: .any)
      .matching(NSPredicate(format: "label CONTAINS[c] %@", substring))
      .firstMatch
  }

  // MARK: - Loaded list

  /// All six fixtures render, and exactly one of them carries the Update
  /// badge — `uitest-container-3` is the only one with `isUpdateAvailable ==
  /// true`. `-4` is `false` and the rest are `nil`, and neither may render a
  /// badge: only `true` is a claim this app can make (`ContainerRow
  /// .updateBadge`'s nil/false rule).
  ///
  /// The badge is counted by its own identifier rather than by looking for
  /// the word "Update" in row labels: `ContainerRow`'s
  /// `.accessibilityElement(children: .combine)` merges the badge's text into
  /// the row label, but the badge's `StaticText` and its
  /// `docker.row.<id>.updateBadge` identifier both survive the merge in the
  /// real tree, so this asserts against the badge itself and not against a
  /// substring of prose that could match for some other reason.
  func testLoadedListShowsEveryContainerAndExactlyOneUpdateBadge() {
    let app = launchOnDocker()

    XCTAssertTrue(row("uitest-container-1", in: app).waitForExistence(timeout: 10), "the container list never loaded")
    XCTAssertEqual(rowCount(in: app), 6, "expected all six seeded containers to render as rows")

    // Every fixture, by identifier — a bare count could be satisfied by six
    // copies of the same row.
    for index in 1...6 {
      XCTAssertTrue(
        row("uitest-container-\(index)", in: app).exists,
        "docker.row.uitest-container-\(index) missing from the loaded list"
      )
    }

    let badges = app.descendants(matching: .any)
      .matching(NSPredicate(format: "identifier ENDSWITH %@", ".updateBadge"))
    XCTAssertEqual(badges.count, 1, "expected exactly one Update badge across the whole list")
    XCTAssertEqual(
      badges.firstMatch.identifier, "docker.row.uitest-container-3.updateBadge",
      "the Update badge is on the wrong container"
    )
  }

  // MARK: - Search

  /// `DockerStore.filteredContainers` matches name *or* image
  /// case-insensitively. "webtop" hits exactly one fixture, so the list must
  /// narrow to that single row — proving the `.searchable` binding actually
  /// reaches the store's filter rather than just rendering a search bar.
  func testSearchNarrowsTheListToMatchingContainers() {
    let app = launchOnDocker()
    XCTAssertTrue(row("uitest-container-1", in: app).waitForExistence(timeout: 10), "the container list never loaded")

    let searchField = self.searchField(in: app)
    XCTAssertTrue(searchField.waitForExistence(timeout: 5), "search field never appeared")
    type("webtop", into: searchField)

    // Waiting on the *disappearance* of a non-matching row is the event that
    // says filtering has been applied — asserting the count immediately after
    // `typeText` would race SwiftUI's re-render.
    let nonMatch = row("uitest-container-1", in: app)
    XCTAssertTrue(
      waitForNonExistence(of: nonMatch, timeout: 5),
      "code-server row survived a search for \"webtop\""
    )
    XCTAssertTrue(row("uitest-container-3", in: app).exists, "the matching webtop row was filtered out too")
    XCTAssertEqual(rowCount(in: app), 1, "expected exactly one row to survive the search")
  }

  /// A query matching nothing must show `ContentUnavailableView.search` —
  /// specifically *not* the "No Containers" empty state, which would tell a
  /// user with six containers that their server has none. Both branches exist
  /// in `DockerListView` precisely so this distinction holds, so this asserts
  /// the wrong one is absent as well as the right one being present.
  func testSearchWithNoMatchShowsTheSearchEmptyState() {
    let app = launchOnDocker()
    XCTAssertTrue(row("uitest-container-1", in: app).waitForExistence(timeout: 10), "the container list never loaded")

    let searchField = self.searchField(in: app)
    XCTAssertTrue(searchField.waitForExistence(timeout: 5), "search field never appeared")
    type("nosuchcontainer", into: searchField)

    // `.search`'s title is "No Results" (with or without the query appended,
    // depending on OS version) — matched by substring so this doesn't overfit
    // to a system string that isn't this app's to own.
    XCTAssertTrue(
      element(labelContains: "No Results", in: app).waitForExistence(timeout: 5),
      "a search matching nothing didn't show ContentUnavailableView.search"
    )
    XCTAssertFalse(
      app.descendants(matching: .any).matching(identifier: "docker.empty").firstMatch.exists,
      "showed the \"No Containers\" empty state for a failed search — the server has six"
    )
    XCTAssertEqual(rowCount(in: app), 0, "no container rows should survive a search that matches nothing")
  }

  // MARK: - Mutations

  /// The swipe path end to end: `uitest-container-2` is `.exited`, so its
  /// leading swipe action is Start — the one action `ContainerRow` offers with
  /// no confirmation dialog, which keeps this test to a single tap and makes
  /// the row's state change the only thing it proves.
  ///
  /// The assertion is on the row's own merged label flipping from "Exited…"
  /// to "Running…", i.e. `DockerStore.perform(_:on:)`'s
  /// `applyingStateUpdate` reaching the rendered row — not merely that a
  /// button was tappable.
  func testSwipeActionStartsAnExitedContainer() {
    let app = launchOnDocker()

    let exited = rowExists("uitest-container-2", reading: "Exited", in: app)
    XCTAssertTrue(exited.waitForExistence(timeout: 10), "freshrss never appeared as an exited row")

    // Swipes the merged row element itself rather than
    // `app.cells.containing(.button, identifier:)`: that form matches on the
    // `Button` a `NavigationLink` produces, which the iPad split layout has no
    // equivalent of, and a query that matches nothing resolves to the
    // *first* cell — so the swipe lands on code-server instead.
    // `DemoModeUITests` swipes this same merged element on both idioms.
    startBySwipe("uitest-container-2", in: app)

    XCTAssertTrue(
      rowExists("uitest-container-2", reading: "Running", in: app).waitForExistence(timeout: 5),
      "the row never became Running after its Start swipe action resolved"
    )
  }

  /// The failure path's whole point: `.actionFailed` keeps the last good list
  /// on screen *and* surfaces the error. A store that blanked the list on a
  /// failed mutation, or swallowed the error silently, would each fail exactly
  /// one half of this.
  ///
  /// `uitest-container-5` is the fixture every action fails for, and it is
  /// `.exited` so this too is a single confirmation-free Start tap.
  func testFailedActionKeepsTheListAndSurfacesTheError() {
    let app = launchOnDocker()

    let exited = rowExists("uitest-container-5", reading: "Exited", in: app)
    XCTAssertTrue(exited.waitForExistence(timeout: 10), "emby never appeared as an exited row")

    startBySwipe("uitest-container-5", in: app)

    // `AppError.serverUnreachable.message` — the specific error isn't the
    // point, only that *an* error message reaches the screen.
    XCTAssertTrue(
      element(labelContains: "Couldn't reach the server.", in: app).waitForExistence(timeout: 5),
      "a failed action surfaced no error message"
    )

    // The list survived: every row still there, and the one whose action
    // failed did not optimistically flip to Running.
    for index in 1...6 {
      XCTAssertTrue(
        row("uitest-container-\(index)", in: app).exists,
        "docker.row.uitest-container-\(index) disappeared when another row's action failed"
      )
    }
    XCTAssertTrue(
      rowExists("uitest-container-5", reading: "Exited", in: app).exists,
      "the failed row flipped to Running despite its mutation failing"
    )
    // Six rows plus the error row `DockerListView` inserts at the top.
    XCTAssertEqual(rowCount(in: app), 7, "expected six container rows plus one error row")
  }

  // MARK: - Detail (navigate by identifier)

  /// The rule's first consequence, and the one `ContainerDetailView`'s doc
  /// comment calls out as mattering more here than it did for disks: the
  /// detail screen re-resolves its container from `DockerStore` on every
  /// render, so a mutation fired from *this very screen* is reflected on it.
  /// A screen pushed with a `Container` value would still read "Exited" after
  /// the user pressed Start on it, because the mutation updates the store and
  /// not the captured snapshot.
  ///
  /// Deliberately asserted through the status string ("Exited (0) 3 hours
  /// ago" → "Up less than a second") and the action set (Start → Stop) rather
  /// than the word "Running" alone: both are things only a re-resolved
  /// container can produce, and neither collides with the navigation title or
  /// any other row on the screen.
  func testDetailReflectsAnActionFiredFromItsOwnScreen() {
    let app = launchOnDocker()

    let exited = rowExists("uitest-container-2", reading: "Exited", in: app)
    XCTAssertTrue(exited.waitForExistence(timeout: 10), "freshrss never appeared as an exited row")
    exited.tap()

    XCTAssertTrue(
      app.navigationBars["freshrss"].waitForExistence(timeout: 5),
      "tapping the container row never pushed its detail screen"
    )
    XCTAssertTrue(
      element(labelContains: "Exited (0) 3 hours ago", in: app).waitForExistence(timeout: 5),
      "the detail screen didn't show the fixture's exited status"
    )

    let startButton = app.buttons["containerDetail.startButton"]
    XCTAssertTrue(startButton.waitForExistence(timeout: 5), "an exited container's detail screen offered no Start")
    startButton.tap()

    XCTAssertTrue(
      element(labelContains: "Up less than a second", in: app).waitForExistence(timeout: 5),
      "the detail screen's Status row never updated after Start — it's frozen at push time"
    )
    XCTAssertTrue(
      app.buttons["containerDetail.stopButton"].waitForExistence(timeout: 5),
      "the Actions section still offers Start for a now-running container — it didn't re-resolve"
    )
  }

  /// The rule's other consequence: a container that leaves the array while
  /// its detail screen is open renders `ContainerNotFoundView` rather than
  /// stale data or a crash. `DiskDetailUITests` leaves this case uncovered,
  /// because a timed poll racing "find this row and tap it" is unreliable in
  /// the simulator at any interval.
  ///
  /// What makes it deterministic here is that the disappearance is driven by
  /// a *call count* rather than a clock: `UITEST_DOCKER_STATE
  /// =container-vanishes` returns all six fixtures on the first
  /// `containers()` call and drops `uitest-container-6` from every call after,
  /// so the row is guaranteed to still be there to tap. Backgrounding and
  /// reactivating the app then forces exactly one more call — `PollingRefresh`
  /// keys its `.task(id:)` on `scenePhase`, so returning to the foreground
  /// tears down the old task and starts a fresh one, and `TowerCore.poll` runs
  /// its action immediately before its first sleep. That is an event with a
  /// guaranteed effect, not a race waited out with a sleep.
  func testDetailShowsNotFoundWhenContainerVanishesWhileOpen() {
    let app = launchOnDocker(state: "container-vanishes")

    let row6 = row("uitest-container-6", in: app)
    XCTAssertTrue(row6.waitForExistence(timeout: 10), "log-rotator never appeared on the first containers() call")
    row6.tap()
    XCTAssertTrue(
      app.navigationBars["log-rotator"].waitForExistence(timeout: 5),
      "tapping the container row never pushed its detail screen"
    )

    XCUIDevice.shared.press(.home)
    app.activate()

    XCTAssertTrue(
      element(labelContains: "Container Not Found", in: app).waitForExistence(timeout: 10),
      "the detail screen kept rendering a container that had left the array"
    )
  }

  // MARK: - Helpers

  /// `.firstMatch`, not `app.searchFields["Search containers"]` directly.
  /// Activating a `.searchable` field puts a second search field in the tree
  /// (the presented, active one alongside the inline one), so a query that
  /// resolved to exactly one element before the tap becomes ambiguous after
  /// it — and resolving an ambiguous query is what XCUITest reports as
  /// "Failed to get matching snapshot: Timed out while evaluating UI query".
  /// `.firstMatch`
  /// stops resolution at the first hit, so the handle stays valid across the
  /// activation.
  private func searchField(in app: XCUIApplication) -> XCUIElement {
    // Goes through the shared helper, which reveals the field first on iPad —
    // where `.searchable` collapses into a navigation-bar button rather than
    // rendering a field.
    searchField(prompt: "Search containers", in: app)
  }

  /// `waitForExistence`'s missing twin — XCUITest ships no
  /// `waitForNonExistence` on this SDK, and a bare `!exists` check
  /// immediately after an action races SwiftUI's re-render. Expectation-based
  /// rather than a sleep loop.
  private func waitForNonExistence(of element: XCUIElement, timeout: TimeInterval) -> Bool {
    let expectation = XCTNSPredicateExpectation(
      predicate: NSPredicate(format: "exists == false"), object: element
    )
    return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
  }
}
