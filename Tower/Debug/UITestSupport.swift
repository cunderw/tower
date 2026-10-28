#if DEBUG
import Foundation
import TowerCore
import TowerData

/// Backs the `--uitest-seed-dashboard` launch argument (see `TowerApp`).
///
/// XCUITest cannot write to the keychain, and there is no live Unraid box
/// for a test run to reach, so there is no way to drive the app to
/// `RootView` through the normal connect flow (`ConnectStore.connect()`
/// requires a server that answers `testConnection()`). `TowerApp` seeds
/// `server` from `UITestFixtures.server` and swaps `AppEnvironment
/// .makeRepository` for this type instead of the live Apollo-backed one, so
/// the tab shell renders against canned data with no network involved.
///
/// Extensible on purpose, not a single-tab-test hack: `Outcome` distinguishes
/// success from failure so a UI test can select either by setting
/// `UITEST_DASHBOARD_STATE` in `launchEnvironment` rather than inventing a
/// second mechanism. `.failFirstThenRecover` exists for this:
/// `DashboardUITests` selects it via `UITEST_DASHBOARD_STATE=retry-succeeds` to
/// prove tapping "Try Again" actually re-invokes `dashboard()`, not just that
/// the button exists.
///
/// What it cannot express: `.success`/`.failure` are fixed for the entire
/// app run, decided once at launch, so there is no way for those two to
/// succeed on the first load and fail on a later refresh (or vice versa).
struct FakeSystemRepository: SystemRepositoryProtocol {
  enum Outcome {
    case success
    case failure(AppError)
    /// Fails the first call to `dashboard()`, then succeeds on every call
    /// after. Added for `DashboardUITests`' retry test: a plain `.failure`
    /// can't distinguish "the Try Again button does nothing" from "it
    /// retried and failed the exact same way again" — both look identical
    /// from outside the app. This makes the retry's *effect* (the screen
    /// recovering from `.failed` to `.loaded`) the observable proof instead.
    case failFirstThenRecover
    /// A successful load whose `SystemInfo.cpuPercent`/`.memoryPercent` are
    /// both `nil`, so `MetricGauge`'s nil-`percent` accessibility value
    /// ("Unknown") is reachable from a UI test without disturbing
    /// `.uitestFixture`, which `DashboardServicesUITests` and others rely on
    /// staying populated.
    case unknownMetrics
    /// `uitest-disk-1`'s temperature flips between 34°C and 47°C on every
    /// `dashboard()` call, to prove that `DiskDetailView`
    /// reflects a store update made while it's open, rather than
    /// the value frozen at push time. A value that only ever changed *once*
    /// couldn't distinguish "already current when the screen opened" from
    /// "updated while the screen was open"; alternating on every call means
    /// whatever the screen shows the moment a test looks, the very next poll
    /// is guaranteed to show something else.
    case diskTempOscillates
    /// A load that never resolves on its own: a LAN address that has become
    /// unreachable, where a request neither succeeds nor fails fast.
    /// `Task.sleep` is cancellation-aware, so `cancelLoad()` reaches it exactly
    /// as a real request's cancellation would.
    case hangs
  }

  let outcome: Outcome
  /// Boxed reference, not a stored `var`: `FakeSystemRepository` is a value
  /// type, but `RootView.init` builds exactly one instance and hands it to
  /// `DashboardStore` for its whole lifetime (see `RootView`'s doc comment),
  /// so the automatic initial load and a later "Try Again" tap both call
  /// `dashboard()` on this same instance — `.failFirstThenRecover` needs a
  /// shared, mutable counter across those calls despite the struct's own
  /// storage being immutable.
  private let attempts = Attempts()

  func testConnection() async throws -> Bool {
    switch outcome {
    case .success, .failFirstThenRecover, .unknownMetrics, .diskTempOscillates, .hangs:
      return true
    case .failure(let error): throw error
    }
  }

  func dashboard() async throws -> DashboardSnapshot {
    switch outcome {
    case .success:
      return .uitestFixture
    case .unknownMetrics:
      return .uitestFixtureWithUnknownMetrics
    case .failure(let error):
      throw error
    case .failFirstThenRecover:
      if attempts.recordAndCheckFirst() {
        throw AppError.serverUnreachable
      }
      return .uitestFixture
    case .diskTempOscillates:
      return attempts.increment().isMultiple(of: 2) ? .uitestFixtureWithChangedDiskTemp : .uitestFixture
    case .hangs:
      // An hour, i.e. never within a test. Cancellation-aware, unlike a busy
      // loop — the point is for `cancelLoad()` to actually reach it.
      try await Task.sleep(for: .seconds(3_600))
      return .uitestFixture
    }
  }
}

/// A lock-protected call counter, boxed out of `FakeSystemRepository` so the
/// struct itself can stay a value type. `SystemRepositoryProtocol` carries no
/// actor requirement (only `Sendable`), so this can't assume `@MainActor`
/// isolation the way `DashboardStore` itself does — same `NSLock` pattern as
/// `TowerData`'s `InMemoryServerStore`, which has the identical shape.
private final class Attempts: @unchecked Sendable {
  private let lock = NSLock()
  private var count = 0

  /// Increments the count and reports whether this call was the first.
  func recordAndCheckFirst() -> Bool {
    lock.withLock {
      count += 1
      return count == 1
    }
  }

  /// Increments the count and returns the new total — used where every call
  /// needs to know *which* call this is (`.diskTempOscillates`), not just
  /// whether it's the first (`recordAndCheckFirst`).
  func increment() -> Int {
    lock.withLock {
      count += 1
      return count
    }
  }
}

/// Backs the `--uitest-seed-dashboard` launch argument's Docker tab, exactly
/// as `FakeSystemRepository` backs its Dashboard tab — swapped in by
/// `TowerApp` so `DockerListView`'s `DockerStore` never dials out to
/// `UITestFixtures.server`'s unreachable URL.
///
/// `uitest-container-1` is running with no update, and `-2` is stopped with no
/// update reading (`isUpdateAvailable: nil`); together they are the fixed,
/// instant list that lets `ShellUITests` and `DashboardServicesUITests` assert
/// the Docker tab shows content. `-3` (running, `isUpdateAvailable: true`) is
/// the running+update combination `DockerAccessibilityUITests` needs. `-4` is
/// `.paused` (the three-state model gives paused containers Stop *and* Resume,
/// never Start), `-5` is the one whose every action fails (drives
/// `DockerUITests`' `.actionFailed` coverage — every method below fails only
/// for this one ID and succeeds for every other), and `-6` exists purely to
/// back `UITEST_DOCKER_STATE=container-vanishes` (see `containers()`) for the
/// not-found proof. None of the six carry ports or a Web UI, so the "no ports
/// and no Web UI" state is reachable from a UI test; containers that *do*
/// publish ports/a Web UI are already covered by `ContainerDetailContent`'s own
/// `#Preview`s, which don't need a fake repository to render.
struct FakeDockerRepository: DockerRepositoryProtocol {
  /// The one container every action fails for — every method below checks
  /// this before returning its normal canned success, so `DockerUITests`
  /// can swipe/tap an action on `uitest-container-5` and observe
  /// `DockerStore.state` land in `.actionFailed` (list preserved, error
  /// surfaced) rather than mutating like every other fixture does.
  static let actionFailureContainerID = "uitest-container-5"

  /// The one container `containers()` drops from its second and every later
  /// response, but only when `UITEST_DOCKER_STATE=container-vanishes` is
  /// set — see `containers()`'s doc comment for why a launch-environment
  /// gate (rather than always-on) keeps this from surprising every other
  /// test that never asks for it.
  static let vanishingContainerID = "uitest-container-6"

  /// Boxed for the same reason `FakeSystemRepository.attempts` is: this is a
  /// value type, but `RootView.init` builds exactly one instance for
  /// `DockerStore`'s whole lifetime, and `containers()` needs a counter that
  /// survives across that one instance's repeated calls (initial load, every
  /// poll tick, every pull-to-refresh).
  private let attempts = Attempts()

  func start(id: String) async throws -> ContainerStateUpdate {
    try failIfActionFailureFixture(id)
    return ContainerStateUpdate(id: id, state: .running, status: "Up less than a second")
  }

  func stop(id: String) async throws -> ContainerStateUpdate {
    try failIfActionFailureFixture(id)
    return ContainerStateUpdate(id: id, state: .exited, status: "Exited (0) less than a second ago")
  }

  func restart(id: String) async throws -> ContainerStateUpdate {
    try failIfActionFailureFixture(id)
    return ContainerStateUpdate(id: id, state: .running, status: "Up less than a second")
  }

  func pause(id: String) async throws -> ContainerStateUpdate {
    try failIfActionFailureFixture(id)
    return ContainerStateUpdate(id: id, state: .paused, status: "Paused")
  }

  func unpause(id: String) async throws -> ContainerStateUpdate {
    try failIfActionFailureFixture(id)
    return ContainerStateUpdate(id: id, state: .running, status: "Up less than a second")
  }

  /// Shared by all five action methods above — `AppError.serverUnreachable`
  /// is as good a failure as any here (it's not the specific error being
  /// tested, only that *some* `AppError` surfaces and the list survives it).
  private func failIfActionFailureFixture(_ id: String) throws {
    guard id == Self.actionFailureContainerID else { return }
    throw AppError.serverUnreachable
  }

  /// Minimal fixed log output — enough for `ContainerLogsView`'s loaded
  /// (non-empty) branch to be reachable from a UI test. `tail`/`since` are
  /// ignored: this fixture never has more than a handful of lines, so there
  /// is no "older history" for a real UI test to page into yet.
  func logs(id: String, tail: Int?, since: String?) async throws -> ContainerLogs {
    ContainerLogs(
      containerId: id,
      lines: [
        ContainerLogLine(timestamp: Date(timeIntervalSince1970: 1_785_000_000), message: "Starting up…"),
        ContainerLogLine(timestamp: Date(timeIntervalSince1970: 1_785_000_005), message: "Ready."),
      ],
      cursor: nil
    )
  }

  /// `UITEST_DOCKER_STATE=container-vanishes` drops `uitest-container-6`
  /// starting from this method's *second* call onward — every other call
  /// (and every call when the env var is unset, which is every other UI
  /// test) returns all six fixtures unchanged. Deliberately not modeled as a
  /// timed disappearance (compare `FakeSystemRepository.Outcome
  /// .diskTempOscillates`, which flips a value every `dashboard()` call
  /// purely on a fast poll timer): racing a timed poll against "find this
  /// row and tap it" is unreliable even at generous margins, because a tap
  /// alone can take over 5 seconds. A call count gated behind an opt-in env
  /// var sidesteps that: `DockerUITests` leaves the poll interval at its real
  /// 30-second default (no test runs anywhere near that long) and instead
  /// forces the second call
  /// deterministically — backgrounding the app and reactivating it, which
  /// tears down and restarts `PollingRefresh`'s `.task(id:)` (its `id`
  /// includes `scenePhase`) and fires exactly one immediate `refresh()` on
  /// return to the foreground. That's an event, not a race: nothing here is
  /// waited out with a fixed sleep, only `waitForExistence` on the resulting
  /// `ContainerNotFoundView`.
  /// `UITEST_DOCKER_STATE=service-containers` appends two recognisable media
  /// services (a Sonarr and a Radarr) so `AddServiceUITests` can drive the
  /// Docker-assisted prefill. Opt-in rather than always-on because
  /// `DockerUITests` asserts the list is exactly six rows, and a seventh
  /// fixture would make that test about this one's fixtures.
  /// `UITEST_DOCKER_STATE=unavailable` is the one value that selects a
  /// whole-tab outcome rather than a behaviour across calls: every call throws
  /// `AppError.serviceUnavailable`, what `LiveDockerRepository` throws with the
  /// Docker service off, so `DockerUITests` can assert the "Docker Unavailable"
  /// state. `FakeSystemRepository` is unaffected and still reports 14 of 16.
  func containers() async throws -> [Container] {
    if ProcessInfo.processInfo.environment["UITEST_DOCKER_STATE"] == "unavailable" {
      throw AppError.serviceUnavailable("Docker")
    }
    let all = [
      Container(
        id: "uitest-container-1", names: ["/code-server"],
        image: "linuxserver/code-server:latest", state: .running, status: "Up 2 hours",
        autoStart: true, isUpdateAvailable: nil, isOrphaned: false, webUiURL: nil, iconURL: nil,
        projectURL: nil, supportURL: nil, registryURL: nil, templatePath: nil, networkMode: nil,
        ports: []
      ),
      Container(
        id: "uitest-container-2", names: ["/freshrss"],
        image: "linuxserver/freshrss:latest", state: .exited,
        status: "Exited (0) 3 hours ago", autoStart: false, isUpdateAvailable: nil,
        isOrphaned: false, webUiURL: nil, iconURL: nil, projectURL: nil, supportURL: nil,
        registryURL: nil, templatePath: nil, networkMode: nil, ports: []
      ),
      Container(
        id: "uitest-container-3", names: ["/webtop"],
        image: "linuxserver/webtop:latest", state: .running, status: "Up 4 hours",
        autoStart: true, isUpdateAvailable: true, isOrphaned: false, webUiURL: nil,
        iconURL: nil, projectURL: nil, supportURL: nil, registryURL: nil, templatePath: nil,
        networkMode: nil, ports: []
      ),
      // Paused: offers Stop and Resume, never Start. See
      // `ContainerRow.canStop`/`ContainerActionsSection.canStop`.
      Container(
        id: "uitest-container-4", names: ["/syncthing"],
        image: "linuxserver/syncthing:latest", state: .paused, status: "Paused",
        autoStart: true, isUpdateAvailable: false, isOrphaned: false, webUiURL: nil,
        iconURL: nil, projectURL: nil, supportURL: nil, registryURL: nil, templatePath: nil,
        networkMode: nil, ports: []
      ),
      // Every action against this one fails — see
      // `actionFailureContainerID`/`failIfActionFailureFixture(_:)` above.
      // `.exited` so its leading swipe/context-menu action is a
      // confirmation-free "Start", keeping `DockerUITests`' failed-action
      // test to a single tap.
      Container(
        id: "uitest-container-5", names: ["/emby"],
        image: "linuxserver/emby:latest", state: .exited,
        status: "Exited (1) 2 hours ago", autoStart: false, isUpdateAvailable: nil,
        isOrphaned: false, webUiURL: nil, iconURL: nil, projectURL: nil, supportURL: nil,
        registryURL: nil, templatePath: nil, networkMode: nil, ports: []
      ),
      // Backs `UITEST_DOCKER_STATE=container-vanishes` — see this method's
      // own doc comment above.
      Container(
        id: "uitest-container-6", names: ["/log-rotator"],
        image: "linuxserver/log-rotator:latest", state: .running, status: "Up 1 hour",
        autoStart: true, isUpdateAvailable: nil, isOrphaned: false, webUiURL: nil,
        iconURL: nil, projectURL: nil, supportURL: nil, registryURL: nil, templatePath: nil,
        networkMode: nil, ports: []
      ),
    ]
    if ProcessInfo.processInfo.environment["UITEST_DOCKER_STATE"] == "service-containers" {
      return all + [
        Container(
          id: "uitest-container-sonarr", names: ["/sonarr"],
          image: "linuxserver/sonarr:latest", state: .running, status: "Up 3 days",
          autoStart: true, isUpdateAvailable: nil, isOrphaned: false, webUiURL: nil, iconURL: nil,
          projectURL: nil, supportURL: nil, registryURL: nil, templatePath: nil,
          networkMode: "bridge",
          ports: [ContainerPort(ip: "0.0.0.0", privatePort: 8989, publicPort: 18989, type: "TCP")]),
        // Stopped, so it must *not* be offered.
        Container(
          id: "uitest-container-radarr", names: ["/radarr"],
          image: "linuxserver/radarr:latest", state: .exited, status: "Exited (0) 1 hour ago",
          autoStart: false, isUpdateAvailable: nil, isOrphaned: false, webUiURL: nil, iconURL: nil,
          projectURL: nil, supportURL: nil, registryURL: nil, templatePath: nil,
          networkMode: "bridge",
          ports: [ContainerPort(ip: "0.0.0.0", privatePort: 7878, publicPort: 7878, type: "TCP")]),
      ]
    }
    guard ProcessInfo.processInfo.environment["UITEST_DOCKER_STATE"] == "container-vanishes" else {
      return all
    }
    return attempts.recordAndCheckFirst() ? all : all.filter { $0.id != Self.vanishingContainerID }
  }
}

/// Backs the `--uitest-seed-dashboard` launch argument's VMs tab,
/// exactly as `FakeDockerRepository` backs its Docker tab.
///
/// Five fixtures, each earning its place — the same discipline
/// `FakeDockerRepository`'s six were grown with:
/// - `-1` running, `-2` paused, `-3` stopped: the three `VMActivity` buckets a
///   UI test needs to see different action sets for.
/// - `-4` `SHUTDOWN`: the `.indeterminate` bucket. A VM mid-shutdown must never
///   be offered Start, and this is the only fixture that can prove it.
/// - `-5` stopped and failing: every action against it throws, so a test can
///   observe `.actionFailed` (list preserved, error surfaced) rather than a
///   mutation landing. `.shutoff` so its one offered action is a
///   confirmation-free Start.
///
/// `UITEST_VMS_STATE` selects an inventory-wide outcome, mirroring
/// `UITEST_DASHBOARD_STATE` rather than `UITEST_DOCKER_STATE` (which selects a
/// behaviour *across* calls): `unavailable` returns `nil` domains — the
/// "VM manager isn't reporting" state that must not read as "no VMs" — `empty`
/// returns `[]`, and anything else returns the five fixtures.
/// Unlike `FakeDockerRepository`, this one **mutates in memory**: the VM
/// actions return `Boolean!`, so `VMStore.perform(_:on:)` re-fetches
/// `domains()` instead of merging a returned state (see its doc comment). A
/// fake whose `domains()` answered the same thing forever would make every
/// action look like a no-op, and a UI test asserting "the row reflects the
/// action" could not be written at all. Demo mode mutates in memory for the
/// same reason: a reviewer has to be able to start a VM and see it change.
struct FakeVMRepository: VMRepositoryProtocol {
  /// The one VM every action fails for.
  static let actionFailureDomainID = "uitest-vm-5"

  /// Boxed reference, not a stored `var`: this is a value type, but
  /// `RootView.init` builds exactly one instance and hands it to `VMStore` for
  /// its whole lifetime, so an action and the re-fetch that follows it must see
  /// the same storage. Same reasoning as `FakeSystemRepository.attempts`.
  private let states = MutableVMStates(seed: Self.seed)

  func domains() async throws -> VMInventory {
    switch ProcessInfo.processInfo.environment["UITEST_VMS_STATE"] {
    case "unavailable": return VMInventory(domains: nil)
    case "empty": return VMInventory(domains: [])
    default: return VMInventory(domains: states.current())
    }
  }

  /// Sorted by display name already, matching what `LiveVMRepository.domains()`
  /// guarantees — a fake returning them in a different order than the real
  /// repository would let a UI test pass against behaviour the app doesn't
  /// have.
  private static let seed: [VMDomain] = [
    VMDomain(id: "uitest-vm-1", name: "Arcade Box", state: .running),
    VMDomain(id: "uitest-vm-3", name: "Debian Build", state: .shutoff),
    VMDomain(id: "uitest-vm-5", name: "Dev Sandbox", state: .shutoff),
    VMDomain(id: "uitest-vm-2", name: "Media Server", state: .paused),
    VMDomain(id: "uitest-vm-4", name: "Windows XP", state: .shutdown),
  ]

  func start(id: String) async throws { try apply(.running, to: id) }
  func stop(id: String) async throws { try apply(.shutoff, to: id) }
  func forceStop(id: String) async throws { try apply(.shutoff, to: id) }
  func pause(id: String) async throws { try apply(.paused, to: id) }
  func resume(id: String) async throws { try apply(.running, to: id) }
  func reboot(id: String) async throws { try apply(.running, to: id) }
  func reset(id: String) async throws { try apply(.running, to: id) }

  /// `AppError.actionRefused` rather than `.serverUnreachable` (which is what
  /// `FakeDockerRepository` throws): a refusal is the failure mode unique to
  /// the VM actions' `Boolean!` responses, so the fake exercises the case the
  /// real repository actually produces. The state is left untouched on the
  /// failure path — a refused action changed nothing on the server either.
  private func apply(_ state: VMState, to id: String) throws {
    guard id != Self.actionFailureDomainID else {
      throw AppError.actionRefused("Unraid refused this VM action.")
    }
    states.set(state, for: id)
  }
}

/// Lock-protected VM state storage, boxed out of `FakeVMRepository` so the
/// struct itself can stay a value type. `VMRepositoryProtocol` carries no actor
/// requirement (only `Sendable`), so this can't assume `@MainActor` isolation —
/// same `NSLock` pattern as `Attempts` above and `TowerData`'s
/// `InMemoryServerStore`.
private final class MutableVMStates: @unchecked Sendable {
  private let lock = NSLock()
  private var domains: [VMDomain]

  init(seed: [VMDomain]) {
    domains = seed
  }

  func current() -> [VMDomain] {
    lock.withLock { domains }
  }

  func set(_ state: VMState, for id: String) {
    lock.withLock {
      domains = domains.map {
        $0.id == id ? VMDomain(id: $0.id, name: $0.name, state: state) : $0
      }
    }
  }
}

/// Backs the `--uitest-seed-dashboard` launch argument's Shares tab.
///
/// No mutation machinery, matching `ShareRepositoryProtocol` itself: shares are
/// read-only in Unraid's schema.
///
/// The five fixtures are chosen to make the *detail* screen's every branch
/// reachable, since that is where the interesting rendering lives:
/// - `appdata` — the shape of a typical share: all disks, no comment,
///   `highwater`, no split level, floor `0` ("None"), `cache` unreported.
/// - `documents` — a comment, so the row's two-line form is reachable.
/// - `domains` — split level, a non-zero floor, `cow: no`, and named
///   include/exclude disks, so the Disks section's non-"All disks" branch renders.
/// - `renamed` — the only share whose `originalName` differs, making the Identity
///   section reachable at all.
/// - `bare` — nothing reported: no allocator, no floor, no COW, no pool figures.
///   Proves the Allocation and Pool sections omit themselves rather than
///   rendering empty headers or `0 B`.
///
/// `UITEST_SHARES_STATE=empty` returns `[]` for the no-shares state.
struct FakeShareRepository: ShareRepositoryProtocol {
  func shares() async throws -> [Share] {
    guard ProcessInfo.processInfo.environment["UITEST_SHARES_STATE"] != "empty" else { return [] }
    return Self.fixtures
  }

  /// Already sorted by display name, matching what `LiveShareRepository.shares()`
  /// guarantees — a fake ordering differently would let a UI test pass against
  /// behaviour the app doesn't have.
  private static let fixtures: [Share] = [
    Share(
      id: "uitest-share-appdata", name: "appdata", originalName: nil, comment: nil,
      includedDisks: [], excludedDisks: [], isCached: nil, allocator: "highwater",
      splitLevel: nil, floorKilobytes: 0, copyOnWrite: "auto",
      poolUsedKilobytes: 412_000_000, poolFreeKilobytes: 588_000_000
    ),
    Share(
      id: "uitest-share-bare", name: "bare", originalName: nil, comment: nil,
      includedDisks: [], excludedDisks: [], isCached: nil, allocator: nil,
      splitLevel: nil, floorKilobytes: nil, copyOnWrite: nil,
      poolUsedKilobytes: nil, poolFreeKilobytes: nil
    ),
    Share(
      id: "uitest-share-documents", name: "documents", originalName: nil,
      comment: "scanned paperwork", includedDisks: [], excludedDisks: [],
      isCached: nil, allocator: "highwater", splitLevel: nil, floorKilobytes: 0,
      copyOnWrite: "auto", poolUsedKilobytes: 72_000_000_000,
      poolFreeKilobytes: 24_000_000_000
    ),
    Share(
      id: "uitest-share-domains", name: "domains", originalName: nil,
      comment: "saved VM instances", includedDisks: ["disk1", "disk2"],
      excludedDisks: ["disk3"], isCached: true, allocator: "mostfree", splitLevel: "1",
      floorKilobytes: 500_000_000, copyOnWrite: "no",
      poolUsedKilobytes: 412_000_000, poolFreeKilobytes: 588_000_000
    ),
    Share(
      id: "uitest-share-renamed", name: "renamed", originalName: "Renamed", comment: nil,
      includedDisks: [], excludedDisks: [], isCached: nil, allocator: "fillup",
      splitLevel: nil, floorKilobytes: 0, copyOnWrite: "auto",
      poolUsedKilobytes: 412_000_000, poolFreeKilobytes: 588_000_000
    ),
  ]
}

/// Backs the `--uitest-seed-dashboard` launch argument's notification bell and
/// sheet.
///
/// Mutates in memory, like `FakeVMRepository` and for the same reason: archiving
/// a notification has to move it between buckets and change the badge, or no UI
/// test could assert that anything happened.
///
/// `UITEST_NOTIFICATIONS_STATE=empty` starts with both buckets empty — the state
/// where the bell has no badge at all.
struct FakeNotificationRepository: NotificationRepositoryProtocol {
  /// The one notification whose every action fails, so a UI test can observe
  /// `.actionFailed` with the list preserved.
  static let actionFailureID = "uitest-notification-fail"

  private let box = MutableNotifications(seed: Self.seed)

  func overview() async throws -> NotificationOverview {
    box.overview()
  }

  func page(kind: NotificationKind, offset: Int, limit: Int) async throws -> NotificationPage {
    box.page(kind: kind, offset: offset, limit: limit)
  }

  func archive(id: String) async throws -> NotificationOverview {
    try failIfFixture(id)
    return box.move(id: id, to: .archive)
  }

  func markUnread(id: String) async throws -> NotificationOverview {
    try failIfFixture(id)
    return box.move(id: id, to: .unread)
  }

  func delete(id: String, kind: NotificationKind) async throws -> NotificationOverview {
    try failIfFixture(id)
    return box.remove(id: id)
  }

  func archiveAll() async throws -> NotificationOverview {
    box.archiveAll()
  }

  private func failIfFixture(_ id: String) throws {
    guard id == Self.actionFailureID else { return }
    throw AppError.serverUnreachable
  }

  /// Deliberately mirrors a real server's shape: a recurring alert appearing
  /// twice (which is what makes near-duplicate rows a real case rather than a
  /// hypothetical), one warning, one info, and an archived one.
  /// Newest first, as the server returns them.
  private static let seed: [ServerNotification] = [
    ServerNotification(
      id: "uitest-notification-1", title: "Unraid Server Alert", subject: "UPS Alert",
      description: "UPS on tower is running on battery power",
      importance: .alert, kind: .unread, linkPath: "/Settings/UPSsettings",
      timestamp: Date(timeIntervalSince1970: 1_785_380_275)
    ),
    ServerNotification(
      id: "uitest-notification-2", title: "Unraid Server Alert", subject: "UPS Alert",
      description: "UPS on tower is running on battery power",
      importance: .alert, kind: .unread, linkPath: "/Settings/UPSsettings",
      timestamp: Date(timeIntervalSince1970: 1_785_347_874)
    ),
    ServerNotification(
      id: "uitest-notification-3", title: "Unraid Status", subject: "Disk temperature",
      description: "disk2 is running at 58 °C", importance: .warning, kind: .unread,
      linkPath: nil, timestamp: Date(timeIntervalSince1970: 1_785_300_000)
    ),
    // No timestamp at all, so the row's no-timestamp branch is reachable.
    ServerNotification(
      id: "uitest-notification-fail", title: "Unraid Status", subject: "Parity check finished",
      description: "Duration 14 hours, 0 errors", importance: .info, kind: .unread,
      linkPath: nil, timestamp: nil
    ),
    ServerNotification(
      id: "uitest-notification-5", title: "Unraid Status", subject: "Array started",
      description: "The array has been started", importance: .info, kind: .archive,
      linkPath: nil, timestamp: Date(timeIntervalSince1970: 1_785_200_000)
    ),
  ]
}

/// Lock-protected notification storage, boxed out of `FakeNotificationRepository`
/// so the struct stays a value type — same pattern as `MutableVMStates`.
private final class MutableNotifications: @unchecked Sendable {
  private let lock = NSLock()
  private var notifications: [ServerNotification]

  init(seed: [ServerNotification]) {
    notifications = ProcessInfo.processInfo.environment["UITEST_NOTIFICATIONS_STATE"] == "empty"
      ? []
      : seed
  }

  func overview() -> NotificationOverview {
    lock.withLock {
      NotificationOverview(
        unread: Self.counts(of: notifications.filter { $0.kind == .unread }),
        archive: Self.counts(of: notifications.filter { $0.kind == .archive })
      )
    }
  }

  func page(kind: NotificationKind, offset: Int, limit: Int) -> NotificationPage {
    lock.withLock {
      let bucket = notifications.filter { $0.kind == kind }
      guard offset < bucket.count else {
        return NotificationPage(notifications: [], requestedLimit: max(1, limit))
      }
      let end = min(bucket.count, offset + max(1, limit))
      return NotificationPage(
        notifications: Array(bucket[offset..<end]), requestedLimit: max(1, limit)
      )
    }
  }

  func move(id: String, to kind: NotificationKind) -> NotificationOverview {
    lock.withLock {
      notifications = notifications.map { notification in
        guard notification.id == id else { return notification }
        return ServerNotification(
          id: notification.id, title: notification.title, subject: notification.subject,
          description: notification.description, importance: notification.importance,
          kind: kind, linkPath: notification.linkPath, timestamp: notification.timestamp
        )
      }
    }
    return overview()
  }

  func remove(id: String) -> NotificationOverview {
    lock.withLock { notifications.removeAll { $0.id == id } }
    return overview()
  }

  func archiveAll() -> NotificationOverview {
    lock.withLock {
      notifications = notifications.map { notification in
        guard notification.kind == .unread else { return notification }
        return ServerNotification(
          id: notification.id, title: notification.title, subject: notification.subject,
          description: notification.description, importance: notification.importance,
          kind: .archive, linkPath: notification.linkPath, timestamp: notification.timestamp
        )
      }
    }
    return overview()
  }

  private static func counts(of bucket: [ServerNotification]) -> NotificationCounts {
    NotificationCounts(
      info: bucket.filter { $0.importance == .info }.count,
      warning: bucket.filter { $0.importance == .warning }.count,
      alert: bucket.filter { $0.importance == .alert }.count,
      total: bucket.count
    )
  }
}

/// Backs the syslog viewer under the `--uitest-seed-dashboard` launch argument.
///
/// The fixtures exist to make the viewer's branches reachable: a normal file, a
/// **0-byte** one (a real server has several empty log files, and the
/// empty-log screen is otherwise unreachable), and a large one whose contents are
/// longer than the initial 200-line window so "load earlier lines" has something
/// to do.
struct FakeLogRepository: LogRepositoryProtocol {
  func logFiles() async throws -> [LogFile] {
    [
      LogFile(name: "cron", path: "/var/log/cron", sizeBytes: 0, modifiedAt: nil),
      LogFile(
        name: "docker.log", path: "/var/log/docker.log", sizeBytes: 51_432,
        modifiedAt: Date(timeIntervalSince1970: 1_785_300_000)
      ),
      LogFile(
        name: "syslog", path: "/var/log/syslog", sizeBytes: 1_204,
        modifiedAt: Date(timeIntervalSince1970: 1_785_380_000)
      ),
    ]
  }

  /// `docker.log` is seeded with 900 lines so the requested window (200 initially)
  /// is genuinely a tail — which is what makes `isTruncated`, the "load earlier
  /// lines" button, and the "Showing last N of M" footer reachable from a UI test.
  /// `syslog` is short enough to arrive whole.
  func logFile(path: String, lines: Int?) async throws -> LogFileContents {
    let requested = lines ?? Int.max
    switch path {
    case "/var/log/cron":
      return LogFileContents(path: path, lines: [], totalLines: 0, startLine: nil)
    case "/var/log/docker.log":
      let total = 900
      let count = min(total, requested)
      return LogFileContents(
        path: path,
        lines: ((total - count + 1)...total).map { "docker.log line \($0)" },
        totalLines: total,
        startLine: total - count + 1
      )
    default:
      let all = (1...12).map { "syslog line \($0)" }
      return LogFileContents(path: path, lines: all, totalLines: all.count, startLine: 1)
    }
  }
}

enum UITestFixtures {
  /// Never actually resolved — `FakeSystemRepository` answers every call
  /// this server would otherwise make, so nothing ever dials out to it.
  static let server = Server(
    name: "UI Test Server",
    url: URL(string: "http://uitest.invalid")!,
    apiKey: "uitest"
  )
}

extension ArrayStatus {
  fileprivate static let uitestFixture = ArrayStatus(
    state: "STARTED",
    capacity: ArrayCapacity(free: 1, used: 1, total: 2),
    // One disk per group, so `DiskDetailUITests` can push into all three
    // disk types and `DashboardView` exercises all three `DiskListCard`
    // calls rather than skipping them as empty. The nil patterns mirror what
    // `SystemRepository`'s real mapping produces from `DashboardQuery` for
    // each group: `parities` carries `device`, `rotational`, and IO counters
    // just like `disks` — only the filesystem fields (`fsFree`, `fsUsed`,
    // `fsSize`, `fsType`) are nil, because parity disks genuinely have no
    // filesystem. `caches` carries `device` too.
    disks: [
      ArrayDisk(
        id: "uitest-disk-1", idx: 1, name: "disk1", device: "sdb", status: "DISK_OK",
        temp: 34, size: 4_000_000_000, fsFree: 1_600_000_000, fsUsed: 2_400_000_000,
        fsSize: 4_000_000_000, fsType: "xfs", rotational: true, numReads: 128_552_310,
        numWrites: 4_221_009, numErrors: 0, type: "DATA"
      ),
      // Disabled disk: the only disk in this fixture with `!isHealthy`, so
      // `DiskListCard`'s row-subtitle status text is reachable from a UI
      // test ("disk2, sdc, 58°C, 3.9 TB of 4 TB").
      ArrayDisk(
        id: "uitest-disk-2", idx: 2, name: "disk2", device: "sdc", status: "DISK_DSBL",
        temp: 58, size: 4_000_000_000, fsFree: 100_000_000, fsUsed: 3_900_000_000,
        fsSize: 4_000_000_000, fsType: "xfs", rotational: true, numReads: 90_211,
        numWrites: 3_005, numErrors: 12, type: "DATA"
      ),
    ],
    parities: [
      ArrayDisk(
        id: "uitest-parity-1", idx: 0, name: "parity", device: "sde", status: "DISK_OK",
        temp: 37, size: 12_000_000_000, fsFree: nil, fsUsed: nil, fsSize: nil,
        fsType: nil, rotational: true, numReads: 98_112_004, numWrites: 12_500,
        numErrors: 0, type: "PARITY"
      ),
    ],
    caches: [
      ArrayDisk(
        id: "uitest-cache-1", idx: 30, name: "cache", device: "nvme0n1", status: "DISK_OK",
        temp: 38, size: 1_000_000_000, fsFree: 700_000_000, fsUsed: 300_000_000,
        fsSize: 1_000_000_000, fsType: "xfs", rotational: false, numReads: 55_002,
        numWrites: 1_204, numErrors: 0, type: "CACHE"
      ),
    ],
    // Non-nil so `SystemMetricsCard`'s populated-reading branch (not just
    // its all-nil "—" branch) is reachable from a UI test — see
    // `DashboardServicesUITests`.
    system: SystemInfo(
      distro: "Unraid OS", release: "7.3.0", bootTimestamp: "2026-01-01T00:00:00Z",
      cpuBrand: "Example 8-Core CPU", cpuCores: 8, cpuThreads: 16,
      cpuPercent: 12, memoryPercent: 88,
      memoryUsedBytes: 28_160_000_000, memoryTotalBytes: 32_000_000_000
    )
  )

  /// Backs `Outcome.unknownMetrics`: same
  /// disks/parity/services as `.uitestFixture`, but `SystemInfo.cpuPercent`
  /// is nil with no `cpuBrand`/core/thread fallback either, so `CPU`'s
  /// `MetricGauge` renders a bare "Unknown" accessibility value with no
  /// detail suffix. `memoryPercent` is nil too, but `memoryUsedBytes`/
  /// `.memoryTotalBytes` stay populated, so `Memory`'s gauge exercises the
  /// other shape: "Unknown" *with* a detail suffix still attached.
  fileprivate static let uitestFixtureWithUnknownMetrics = ArrayStatus(
    state: uitestFixture.state,
    capacity: uitestFixture.capacity,
    disks: uitestFixture.disks,
    parities: uitestFixture.parities,
    caches: uitestFixture.caches,
    system: SystemInfo(
      distro: "Unraid OS", release: "7.3.0", bootTimestamp: "2026-01-01T00:00:00Z",
      cpuBrand: nil, cpuCores: nil, cpuThreads: nil,
      cpuPercent: nil, memoryPercent: nil,
      memoryUsedBytes: 28_160_000_000, memoryTotalBytes: 32_000_000_000
    )
  )

  /// Backs `Outcome.diskTempOscillates`:
  /// identical to `.uitestFixture` except `uitest-disk-1`'s temperature —
  /// 47°C here rather than 34°C — so a UI test can distinguish "this is the
  /// snapshot from a later poll" from "this is the one the screen was
  /// pushed with".
  fileprivate static let uitestFixtureWithChangedDiskTemp = ArrayStatus(
    state: uitestFixture.state,
    capacity: uitestFixture.capacity,
    disks: [
      ArrayDisk(
        id: "uitest-disk-1", idx: 1, name: "disk1", device: "sdb", status: "DISK_OK",
        temp: 47, size: 4_000_000_000, fsFree: 1_600_000_000, fsUsed: 2_400_000_000,
        fsSize: 4_000_000_000, fsType: "xfs", rotational: true, numReads: 128_552_310,
        numWrites: 4_221_009, numErrors: 0, type: "DATA"
      ),
      uitestFixture.disks[1],
    ],
    parities: uitestFixture.parities,
    caches: uitestFixture.caches,
    system: uitestFixture.system
  )
}

extension DashboardSnapshot {
  fileprivate static let uitestFixture = DashboardSnapshot(
    array: .uitestFixture,
    // `.running` rather than `.neverRun`: a server with no check in progress
    // never reaches `ArrayHeroCard`'s parity-progress branch, so this fixture is
    // the only way to exercise it from a UI test (see its `#Preview`s too).
    parity: ParityStatus(
      state: .running,
      progressPercent: 63,
      errors: nil,
      speed: "150 MB/s",
      lastRunTimestamp: nil,
      durationSeconds: nil,
      correcting: true
    ),
    // Non-zero so `ServicesCard`'s rows have a real "X of Y running" line to
    // assert on from a UI test, rather than "0 of 0 running" for every row.
    services: ServiceCounts(
      containersRunning: 14,
      containersTotal: 16,
      vmsRunning: 2,
      vmsTotal: 3,
      sharesTotal: 9
    )
  )

  fileprivate static let uitestFixtureWithUnknownMetrics = DashboardSnapshot(
    array: .uitestFixtureWithUnknownMetrics,
    parity: uitestFixture.parity,
    services: uitestFixture.services
  )

  fileprivate static let uitestFixtureWithChangedDiskTemp = DashboardSnapshot(
    array: .uitestFixtureWithChangedDiskTemp,
    parity: uitestFixture.parity,
    services: uitestFixture.services
  )
}
// MARK: - Services

/// Backs the Services hub under `--uitest-seed-dashboard`.
///
/// Two things here are deliberate and are what the hub's UI tests assert
/// against:
///
/// - **One disabled instance.** "Disabled instances are hidden" is otherwise
///   untestable — a hub that ignored `isEnabled` would look identical.
/// - **One slow check.** The NZBGet instance takes five seconds to answer,
///   so a test can assert that the healthy rows have already resolved while it
///   is still checking. Without a slow one, "one dead service doesn't block the
///   others" passes trivially even for a fully serial hub.
enum UITestServices {
  static let radarrID = UUID(uuidString: "A0000000-0000-0000-0000-000000000001")!
  static let sonarrID = UUID(uuidString: "A0000000-0000-0000-0000-000000000002")!
  static let nzbgetID = UUID(uuidString: "A0000000-0000-0000-0000-000000000003")!
  static let tautulliID = UUID(uuidString: "A0000000-0000-0000-0000-000000000004")!
  /// Disabled — configured, and deliberately not shown on the hub.
  static let prowlarrID = UUID(uuidString: "A0000000-0000-0000-0000-000000000005")!
  /// A second Radarr, with a different library — the only way to test that two
  /// instances of one kind hold independent store state.
  static let radarr4KID = UUID(uuidString: "A0000000-0000-0000-0000-000000000006")!

  static let instances: [ServiceInstance] = [
    ServiceInstance(
      id: radarrID, kind: .radarr, name: "Radarr",
      baseURL: URL(string: "http://192.0.2.1:7878")!, credentials: .apiKey("uitest")),
    ServiceInstance(
      id: sonarrID, kind: .sonarr, name: "Sonarr 4K",
      baseURL: URL(string: "http://192.0.2.1:8989")!, credentials: .apiKey("uitest")),
    ServiceInstance(
      id: nzbgetID, kind: .nzbget, name: "NZBGet",
      baseURL: URL(string: "http://192.0.2.1:6789")!,
      credentials: .usernamePassword(username: "uitest", password: "uitest")),
    ServiceInstance(
      id: tautulliID, kind: .tautulli, name: "Tautulli",
      baseURL: URL(string: "http://192.0.2.1:8181")!, credentials: .apiKey("uitest")),
    ServiceInstance(
      id: prowlarrID, kind: .prowlarr, name: "Prowlarr",
      baseURL: URL(string: "http://192.0.2.1:9696")!, credentials: .apiKey("uitest"),
      isEnabled: false),
    ServiceInstance(
      id: radarr4KID, kind: .radarr, name: "Radarr 4K",
      baseURL: URL(string: "http://192.0.2.1:7879")!, credentials: .apiKey("uitest")),
  ]

  /// Two instances addressed on the **fake server's own host**, so they match
  /// the containers `UITEST_DOCKER_STATE=service-containers` adds.
  ///
  /// The six above deliberately live on `192.0.2.1` while the fake server is
  /// `uitest.invalid`, so none of them matches any container — which is the
  /// correct no-link outcome and is why the cross-link needs its own fixtures
  /// rather than reusing those.
  ///
  /// The Sonarr is on the container's **published** 18989, not Sonarr's stock
  /// 8989, so a match proves the port actually decided it. The Radarr matches a
  /// container that is **stopped**, which is the case the link exists for.
  static let containerLinkedInstances: [ServiceInstance] = [
    ServiceInstance(
      id: UUID(uuidString: "A0000000-0000-0000-0000-0000000000A1")!, kind: .sonarr,
      name: "Linked Sonarr", baseURL: URL(string: "http://uitest.invalid:18989")!,
      credentials: .apiKey("uitest")),
    ServiceInstance(
      id: UUID(uuidString: "A0000000-0000-0000-0000-0000000000A2")!, kind: .radarr,
      name: "Linked Radarr", baseURL: URL(string: "http://uitest.invalid:7878")!,
      credentials: .apiKey("uitest")),
  ]

  /// `UITEST_SERVICES_STATE=empty` gives the hub nothing to show, for the
  /// empty-state test; `container-linked` seeds the two instances that
  /// correspond to the fake server's containers. Anything else seeds the six
  /// above.
  static func directory() -> ServiceDirectory {
    switch ProcessInfo.processInfo.environment["UITEST_SERVICES_STATE"] {
    case "empty": return .inMemory()
    case "container-linked": return .inMemory(containerLinkedInstances)
    default: return .inMemory(instances)
    }
  }
}

/// Canned per-instance health, with one deliberately slow check. Never touches
/// the network — `UITestServices`' addresses are documentation IPs.
struct FakeServiceStatusChecker: ServiceStatusChecking {
  func status(for instance: ServiceInstance) async -> ServiceStatus {
    switch instance.id {
    case UITestServices.sonarrID:
      return .unauthorized
    case UITestServices.nzbgetID:
      // The slow one. `Task.sleep` is cancellation-aware, so leaving the tab
      // mid-check behaves as a real request would.
      try? await Task.sleep(for: .seconds(5))
      return .unreachable(.serverUnreachable)
    default:
      return unseededStatus(for: instance)
    }
  }

  /// An instance the add-service flow just built, which has a random id no
  /// fixture can name. Decided from what was typed instead, so
  /// `AddServiceUITests` can drive all three outcomes:
  /// an API key or password of `bad` is rejected, a host containing `down` is
  /// unreachable, anything else connects.
  private func unseededStatus(for instance: ServiceInstance) -> ServiceStatus {
    let secret = switch instance.credentials {
    case .apiKey(let key): key
    case .usernamePassword(_, let password): password
    }
    // Host first, then credentials — the order the real world imposes: a
    // service you cannot reach never gets as far as rejecting your key.
    if instance.baseURL.host()?.contains("down") == true { return .unreachable(.serverUnreachable) }
    if secret == "bad" { return .unauthorized }
    return .reachable(version: "1.2.3")
  }
}
/// Canned Radarr and Sonarr libraries for the *arr shell's UI tests.
///
/// Two Radarr instances are seeded with *different* libraries on purpose: "two
/// instances of the same kind hold independent store state" is otherwise
/// untestable — with identical data, a shell that shared one store would look
/// exactly right.
final class FakeRadarrRepository: RadarrRepositoryProtocol, @unchecked Sendable {
  let instance: ServiceInstance
  var arr: ArrClientCore {
    ArrClientCore(client: ServiceHTTPClient(instance: instance))
  }

  private let lock = NSLock()
  private var movies: [RadarrMovie]
  private var queueItems: [ArrQueueItem] = FakeRadarrRepository.seededQueue()

  /// One of each state the queue screen has to tell apart.
  private static func seededQueue() -> [ArrQueueItem] {
    [
      ArrQueueItem(
        id: 41, title: "Downloaded Film (2024) 1080p", mediaID: 10,
        sizeBytes: 24_696_061_952, sizeLeftBytes: 8_232_020_650, timeLeft: "00:12:34",
        estimatedCompletionTime: nil, status: .downloading, trackedStatus: .ok,
        trackedState: .downloading, errorMessage: nil, statusMessages: [],
        downloadProtocol: .usenet, downloadClient: "NZBGet",
        indexer: "Example Indexer", quality: "WEBDL-1080p"),
      ArrQueueItem(
        id: 42, title: "Missing Film (2021) 2160p", mediaID: 11,
        sizeBytes: 68_719_476_736, sizeLeftBytes: 0, timeLeft: nil,
        estimatedCompletionTime: nil, status: .warning, trackedStatus: .warning,
        trackedState: .importBlocked, errorMessage: nil,
        statusMessages: ["No files found are eligible for import"],
        downloadProtocol: .usenet, downloadClient: "NZBGet",
        indexer: "Example Usenet", quality: "WEBDL-2160p"),
      ArrQueueItem(
        id: 43, title: "Another Film (2019) 1080p", mediaID: 12,
        sizeBytes: 8_589_934_592, sizeLeftBytes: 0, timeLeft: nil,
        estimatedCompletionTime: nil, status: .completed, trackedStatus: .ok,
        trackedState: .importPending, errorMessage: nil, statusMessages: [],
        downloadProtocol: .usenet, downloadClient: "NZBGet",
        indexer: "Example Indexer", quality: "WEBDL-1080p"),
    ]
  }

  init(instance: ServiceInstance) {
    self.instance = instance
    // The 4K instance holds a deliberately different (and tiny) library: "two
    // instances of the same kind hold independent state" is untestable when
    // both show the same rows.
    movies = instance.id == UITestServices.radarr4KID
      ? [Self.movie(id: 1, title: "Only In 4K", year: 2022, hasFile: true, size: 68_719_476_736)]
      : Self.seededLibrary()
  }

  /// **60 movies, not three.** The library screen's search, sort, and filters
  /// are only meaningfully exercised against a list that doesn't fit on one
  /// screen — a three-row fixture makes every one of them look like it works.
  /// Titles are generated but the *interesting* rows are explicit, so tests can
  /// name them.
  private static func seededLibrary() -> [RadarrMovie] {
    var library: [RadarrMovie] = [
      movie(id: 10, title: "Downloaded Film", year: 2024, hasFile: true, size: 24_696_061_952,
            studio: "Example Pictures"),
      movie(id: 11, title: "Missing Film", year: 2021, hasFile: false, available: true),
      movie(id: 12, title: "Unreleased Film", year: 2027, hasFile: false, available: false,
            monitored: false),
      // Biggest on disk and most recently added, so `sort` has an unambiguous
      // winner to assert on.
      movie(id: 13, title: "Zulu Voyage", year: 2019, hasFile: true, size: 91_268_055_040,
            added: Date(timeIntervalSince1970: 1_790_000_000)),
    ]
    for index in 0..<56 {
      library.append(
        movie(
          id: 100 + index,
          title: "Filler Film \(String(format: "%02d", index))",
          year: 2000 + (index % 20),
          hasFile: index.isMultiple(of: 2),
          size: index.isMultiple(of: 2) ? Int64(index + 1) * 1_073_741_824 : 0,
          available: true,
          monitored: !index.isMultiple(of: 3)))
    }
    return library
  }

  /// `UITEST_RADARR_STATE=slow-library` makes every library fetch take three
  /// seconds, which is what lets a test *prove* the store was retained.
  ///
  /// Asserting "the rows are there on re-entry" is not enough on its own: a
  /// rebuilt store would put them there too, just later. With a deliberately
  /// slow fetch, "the rows are there within a second of coming back" is only
  /// possible if the store kept the rows it already had. A retained store may
  /// still refresh in place behind them, so this proves retention, not the
  /// absence of a fetch.
  func movies() async throws -> [RadarrMovie] {
    let isSlow = ProcessInfo.processInfo.environment["UITEST_RADARR_STATE"] == "slow-library"
    try? await Task.sleep(for: isSlow ? .seconds(3) : .milliseconds(150))
    return lock.withLock { movies }
  }

  func movie(id: Int) async throws -> RadarrMovie {
    let match = lock.withLock { movies.first { $0.id == id } }
    guard let match else { throw AppError.unknown("No such movie") }
    return match
  }

  /// Two results: one addable, one already in the library — the row state the
  /// add screen has to get right.
  func lookup(term: String) async throws -> [RadarrMovieLookup] {
    try? await Task.sleep(for: .milliseconds(150))
    guard !term.trimmingCharacters(in: .whitespaces).isEmpty else { return [] }
    return [
      RadarrMovieLookup(
        tmdbID: 900_100, title: "Addable Film", year: 2025,
        overview: "A film that is not in the library yet.", posterURL: nil,
        studio: "Example Pictures", runtimeMinutes: 118, existingMovieID: nil),
      RadarrMovieLookup(
        tmdbID: 10, title: "Downloaded Film", year: 2024, overview: nil, posterURL: nil,
        studio: "Example Pictures", runtimeMinutes: 100, existingMovieID: 10),
    ]
  }

  func add(_ request: RadarrAddMovieRequest) async throws -> RadarrMovie {
    try? await Task.sleep(for: .milliseconds(150))
    if ProcessInfo.processInfo.environment["UITEST_RADARR_STATE"] == "action-fails" {
      throw AppError.serverUnreachable
    }
    return lock.withLock {
      // Search-on-add is a flag in the POST body on a real Radarr
      // (`addOptions.searchForMovie`, asserted in `RadarrRepositoryTests`), so
      // it has no visible effect here. The fake gives it one — a suffixed title
      // — because otherwise a UI test cannot tell a request that carried the
      // flag from one that dropped it.
      let added = Self.movie(
        id: 900,
        title: request.searchOnAdd ? "\(request.lookup.title) (searching)" : request.lookup.title,
        year: request.lookup.year, hasFile: false, available: true,
        monitored: request.isMonitored, studio: request.lookup.studio)
      movies.append(added)
      return added
    }
  }

  /// Only the monitor flag is exercised, and `UITEST_RADARR_STATE=action-fails`
  /// makes it fail — the `.actionFailed` path has to be reachable from a UI
  /// test or "the list survives a failed action" is an untested claim.
  func update(_ movie: RadarrMovie, with edit: RadarrMovieEdit) async throws -> RadarrMovie {
    try? await Task.sleep(for: .milliseconds(120))
    if ProcessInfo.processInfo.environment["UITEST_RADARR_STATE"] == "action-fails" {
      throw AppError.serverUnreachable
    }
    return lock.withLock {
      guard let index = movies.firstIndex(where: { $0.id == movie.id }) else { return movie }
      let updated = Self.setting(movies[index], monitored: edit.isMonitored)
      movies[index] = updated
      return updated
    }
  }

  func delete(id: Int, deleteFiles: Bool, addImportExclusion: Bool) async throws {
    try? await Task.sleep(for: .milliseconds(120))
    if ProcessInfo.processInfo.environment["UITEST_RADARR_STATE"] == "action-fails" {
      throw AppError.serverUnreachable
    }
    lock.withLock { movies.removeAll { $0.id == id } }
  }

  /// Three releases: a rejected one (whose reason has to reach the screen
  /// verbatim), an approved one, and an old one. The rejected one comes first,
  /// so the screen putting approved releases first is a visible reorder.
  func releases(movieID: Int) async throws -> [ArrRelease] {
    try? await Task.sleep(for: .milliseconds(150))
    if ProcessInfo.processInfo.environment["UITEST_RADARR_STATE"] == "no-releases" {
      return []
    }
    return [
      ArrRelease(
        id: "release-rejected", title: "Example Film (2024) 1080p",
        indexer: "Example Indexer", indexerID: 3, quality: "WEBDL-1080p",
        sizeBytes: 8_589_934_592, downloadProtocol: .usenet,
        publishDate: nil, ageHours: 12, isApproved: false,
        rejections: ["Quality WEBDL-1080p is wanted, but WEBDL-2160p is already downloaded"]),
      ArrRelease(
        id: "release-approved", title: "Example Film (2024) 2160p",
        indexer: "Example Indexer", indexerID: 3, quality: "WEBDL-2160p",
        sizeBytes: 87_241_068_544, downloadProtocol: .usenet,
        publishDate: nil, ageHours: 96, isApproved: true, rejections: []),
      ArrRelease(
        id: "release-usenet", title: "Example Film (2024) 1080p x264",
        indexer: "Example Usenet", indexerID: 5, quality: "WEBDL-1080p",
        sizeBytes: 24_696_061_952, downloadProtocol: .usenet,
        publishDate: nil, ageHours: 720, isApproved: true, rejections: []),
    ]
  }

  /// `UITEST_RADARR_STATE=grab-fails` makes the grab fail with the *arr's own
  /// rejection wording, which is what the screen has to surface.
  func grab(_ release: ArrRelease) async throws {
    try? await Task.sleep(for: .milliseconds(150))
    if ProcessInfo.processInfo.environment["UITEST_RADARR_STATE"] == "grab-fails" {
      throw AppError.unknown("Radarr returned HTTP 400: Release was rejected by the indexer")
    }
  }

  // The pickers, answered locally. Without these the edit and add sheets would
  // reach `ArrClientCore` — a real `URLSession` against a documentation IP —
  // and sit on its timeout with empty pickers.
  func qualityProfiles() async throws -> [ArrQualityProfile] {
    try? await Task.sleep(for: .milliseconds(120))
    return [
      ArrQualityProfile(id: 1, name: "Any"),
      ArrQualityProfile(id: 4, name: "HD-1080p"),
      ArrQualityProfile(id: 6, name: "Ultra-HD"),
    ]
  }

  func rootFolders() async throws -> [ArrRootFolder] {
    try? await Task.sleep(for: .milliseconds(120))
    return [
      ArrRootFolder(id: 1, path: "/data/media/movies", isAccessible: true, freeBytes: 3_221_225_472_000),
      ArrRootFolder(id: 2, path: "/data/media/movies-4k", isAccessible: true, freeBytes: 1_099_511_627_776),
    ]
  }

  func tags() async throws -> [ArrTag] {
    [ArrTag(id: 1, label: "4k"), ArrTag(id: 2, label: "kids")]
  }

  /// Three queue items: one downloading, one waiting to import, and one stuck
  /// with the *arr's own reason attached — the row the queue screen exists for.
  func queue() async throws -> ArrQueuePage {
    try? await Task.sleep(for: .milliseconds(150))
    return lock.withLock {
      ArrQueuePage(items: queueItems, page: 1, pageSize: 50, totalRecords: queueItems.count)
    }
  }

  func removeQueueItem(id: Int, removeFromClient: Bool, blocklist: Bool) async throws {
    try? await Task.sleep(for: .milliseconds(120))
    if ProcessInfo.processInfo.environment["UITEST_RADARR_STATE"] == "action-fails" {
      throw AppError.serverUnreachable
    }
    lock.withLock {
      lastBlocklisted = blocklist
      queueItems.removeAll { $0.id == id }
    }
  }

  /// Whether the last removal asked for a blocklist — the two buttons send
  /// different things, and this is how a UI test can tell them apart.
  private(set) var lastBlocklisted: Bool?

  /// Two days' worth of entries, one already downloaded — the calendar's job is
  /// to distinguish "coming" from "already here".
  func calendar(start: Date, end: Date) async throws -> [ArrCalendarEntry] {
    try? await Task.sleep(for: .milliseconds(150))
    let today = Calendar.current.startOfDay(for: Date())
    return [
      ArrCalendarEntry(
        id: 11, title: "Missing Film", subtitle: "2021",
        date: today.addingTimeInterval(11 * 3_600), isMonitored: true, hasFile: false),
      ArrCalendarEntry(
        id: 10, title: "Downloaded Film", subtitle: "2024",
        date: today.addingTimeInterval(14 * 3_600), isMonitored: true, hasFile: true),
      ArrCalendarEntry(
        id: 12, title: "Unreleased Film", subtitle: "2027",
        date: today.addingTimeInterval(3 * 86_400 + 20 * 3_600),
        isMonitored: false, hasFile: false),
    ]
  }

  /// One of each severity, and one carrying a wiki link — the health list's
  /// whole job is telling them apart.
  func health() async throws -> [ArrHealthCheck] {
    try? await Task.sleep(for: .milliseconds(120))
    return [
      ArrHealthCheck(
        id: 1, source: "IndexerStatusCheck", severity: .error,
        message: "Indexers unavailable due to failures: Example Indexer",
        wikiURL: URL(string: "https://wiki.servarr.com/radarr/system")),
      ArrHealthCheck(
        id: 2, source: "ImportListStatusCheck", severity: .warning,
        message: "Lists unavailable due to failures: Example List", wikiURL: nil),
      ArrHealthCheck(
        id: 3, source: "UpdateCheck", severity: .notice,
        message: "New update is available", wikiURL: nil),
    ]
  }

  /// Multi-TB, because that is where a wrong unit shows up.
  func diskSpace() async throws -> [ArrDiskSpace] {
    try? await Task.sleep(for: .milliseconds(120))
    return [
      ArrDiskSpace(
        path: "/data", label: "data", freeBytes: 3_221_225_472_000,
        totalBytes: 12_000_138_625_024),
      ArrDiskSpace(path: "/config", label: nil, freeBytes: 48_318_382_080, totalBytes: 107_374_182_400),
    ]
  }

  func systemStatus() async throws -> ArrSystemStatus {
    try? await Task.sleep(for: .milliseconds(120))
    return ArrSystemStatus(
      appName: "Radarr", instanceName: "Radarr", version: "5.14.0.9383", osName: "ubuntu",
      osVersion: "24.04", isDocker: true,
      startTime: Date().addingTimeInterval(-3 * 86_400))
  }

  /// `UITEST_RADARR_STATE=command-fails` makes commands fail, so the failure
  /// path is reachable.
  func runCommand(_ name: String) async throws -> ArrCommand {
    try? await Task.sleep(for: .milliseconds(200))
    if ProcessInfo.processInfo.environment["UITEST_RADARR_STATE"] == "command-fails" {
      throw AppError.unknown("Radarr refused the command")
    }
    return ArrCommand(
      id: 1, name: name, status: .queued, message: nil, started: nil, ended: nil)
  }

  /// Grabbed, imported, and failed — the three events the feed exists to show,
  /// with one carrying a media id so the drill-in is reachable.
  func history(page: Int) async throws -> ArrHistoryPage {
    try? await Task.sleep(for: .milliseconds(150))
    let records = [
      ArrHistoryRecord(
        id: 9001, event: .grabbed, sourceTitle: "Downloaded Film (2024) 1080p",
        mediaID: 10, date: Date().addingTimeInterval(-3_600), quality: "WEBDL-1080p"),
      ArrHistoryRecord(
        id: 9002, event: .downloadFolderImported,
        sourceTitle: "Downloaded Film (2024) 1080p", mediaID: 10,
        date: Date().addingTimeInterval(-7_200), quality: "WEBDL-1080p"),
      ArrHistoryRecord(
        id: 9003, event: .downloadFailed, sourceTitle: "Missing Film (2021) 2160p",
        mediaID: 11, date: Date().addingTimeInterval(-86_400), quality: "WEBDL-2160p"),
    ]
    return ArrHistoryPage(records: records, page: 1, pageSize: 50, totalRecords: records.count)
  }

  /// Renames the film when Radarr's search command runs, which is how a UI
  /// test can see that an automatic search from the detail screen reached the
  /// service — the command itself has no visible effect otherwise. Search on
  /// add travels in the add request instead; `add(_:)` says how a UI test
  /// sees that. Fails under
  /// `UITEST_RADARR_STATE=action-fails` like every other mutation, so a failed
  /// search is reachable from a UI test too.
  func search(movieID: Int) async throws {
    if ProcessInfo.processInfo.environment["UITEST_RADARR_STATE"] == "action-fails" {
      throw AppError.serverUnreachable
    }
    lock.withLock {
      guard let index = movies.firstIndex(where: { $0.id == movieID }) else { return }
      let movie = movies[index]
      movies[index] = Self.movie(
        id: movie.id, title: "\(movie.title) (searching)", year: movie.year,
        hasFile: movie.hasFile, size: movie.sizeOnDiskBytes, available: movie.isAvailable,
        monitored: movie.isMonitored, studio: movie.studio)
    }
  }

  private static func setting(_ movie: RadarrMovie, monitored: Bool) -> RadarrMovie {
    RadarrMovie(
      id: movie.id, tmdbID: movie.tmdbID, imdbID: movie.imdbID, title: movie.title,
      sortTitle: movie.sortTitle, year: movie.year, overview: movie.overview,
      studio: movie.studio, runtimeMinutes: movie.runtimeMinutes,
      certification: movie.certification, genres: movie.genres, status: movie.status,
      minimumAvailability: movie.minimumAvailability, isMonitored: monitored,
      hasFile: movie.hasFile, isAvailable: movie.isAvailable,
      sizeOnDiskBytes: movie.sizeOnDiskBytes, qualityProfileID: movie.qualityProfileID,
      path: movie.path, rootFolderPath: movie.rootFolderPath, tagIDs: movie.tagIDs,
      added: movie.added, inCinemas: movie.inCinemas, digitalRelease: movie.digitalRelease,
      physicalRelease: movie.physicalRelease, posterURL: movie.posterURL,
      fanartURL: movie.fanartURL, file: movie.file)
  }

  private static func movie(
    id: Int, title: String, year: Int?, hasFile: Bool, size: Int64 = 0,
    available: Bool = true, monitored: Bool = true, studio: String? = nil,
    added: Date = Date(timeIntervalSince1970: 1_700_000_000)
  ) -> RadarrMovie {
    RadarrMovie(
      id: id, tmdbID: id, imdbID: nil, title: title, sortTitle: title.lowercased(), year: year,
      overview: hasFile ? "A film that exists only in a fixture." : nil, studio: studio,
      runtimeMinutes: 100, certification: "PG-13", genres: ["Drama"],
      status: available ? .released : .announced, minimumAvailability: .released,
      isMonitored: monitored, hasFile: hasFile, isAvailable: available, sizeOnDiskBytes: size,
      qualityProfileID: 1, path: nil, rootFolderPath: nil, tagIDs: [], added: added,
      inCinemas: nil, digitalRelease: nil, physicalRelease: nil, posterURL: nil, fanartURL: nil,
      file: hasFile
        ? RadarrMovieFile(
          id: id, relativePath: "\(title).mkv", sizeBytes: size, quality: "WEBDL-1080p",
          releaseGroup: "GROUP", videoCodec: "HEVC", audioCodec: "TrueHD", audioChannels: 7.1,
          resolution: "1920x1080", runtime: "1:40:00", languages: ["eng"], dateAdded: added)
        : nil)
  }
}

/// A Sonarr with two series, seasons, and episodes — enough to walk
/// series → season → episode and toggle monitoring at each level.
final class FakeSonarrRepository: SonarrRepositoryProtocol, @unchecked Sendable {
  let instance: ServiceInstance
  var arr: ArrClientCore {
    ArrClientCore(client: ServiceHTTPClient(instance: instance))
  }

  private let lock = NSLock()
  private var series: [SonarrSeries]
  private var episodes: [SonarrEpisode]

  init(instance: ServiceInstance) {
    self.instance = instance
    series = [
      Self.show(
        id: 1, title: "Complete Show", files: 20, aired: 20, size: 53_687_091_200,
        seasons: [
          Self.season(0, monitored: false, files: 0, aired: 0, total: 2, size: 0),
          Self.season(1, monitored: true, files: 10, aired: 10, total: 10, size: 26_843_545_600),
          Self.season(2, monitored: true, files: 10, aired: 10, total: 10, size: 26_843_545_600),
        ]),
      Self.show(
        id: 2, title: "Partial Show", files: 6, aired: 10, size: 32_212_254_720,
        monitored: false,
        seasons: [Self.season(1, monitored: true, files: 6, aired: 10, total: 12, size: 32_212_254_720)]),
    ]
    episodes = Self.seededEpisodes()
  }

  /// Series 1's episodes. Season 1 has one downloaded, one aired-and-missing
  /// and one unaired — the three episode states the screens have to tell
  /// apart — and season 2 has one downloaded episode.
  private static func seededEpisodes() -> [SonarrEpisode] {
    [
      episode(
        id: 101, series: 1, season: 1, number: 1, title: "Beginnings", hasFile: true,
        aired: Date(timeIntervalSince1970: 1_700_000_000), size: 5_368_709_120),
      episode(
        id: 102, series: 1, season: 1, number: 2, title: "Middles", hasFile: false,
        aired: Date(timeIntervalSince1970: 1_700_600_000)),
      episode(
        id: 103, series: 1, season: 1, number: 3, title: "TBA", hasFile: false,
        aired: Date(timeIntervalSince1970: 4_900_000_000), monitored: true),
      episode(
        id: 201, series: 1, season: 2, number: 1, title: "Returns", hasFile: true,
        aired: Date(timeIntervalSince1970: 1_720_000_000), size: 4_294_967_296),
    ]
  }

  func series() async throws -> [SonarrSeries] {
    try? await Task.sleep(for: .milliseconds(150))
    return lock.withLock { series }
  }

  func series(id: Int) async throws -> SonarrSeries {
    guard let match = lock.withLock({ series.first { $0.id == id } }) else {
      throw AppError.unknown("No such series")
    }
    return match
  }

  func episodes(seriesID: Int) async throws -> [SonarrEpisode] {
    try? await Task.sleep(for: .milliseconds(120))
    return lock.withLock { episodes.filter { $0.seriesID == seriesID } }
  }

  func lookup(term: String) async throws -> [SonarrSeriesLookup] {
    try? await Task.sleep(for: .milliseconds(150))
    guard !term.trimmingCharacters(in: .whitespaces).isEmpty else { return [] }
    return [
      SonarrSeriesLookup(
        tvdbID: 777_100, title: "Addable Series", year: 2026,
        overview: "Not in the library yet.", network: "Example Network", status: .upcoming,
        posterURL: nil, existingSeriesID: nil),
      SonarrSeriesLookup(
        tvdbID: 1, title: "Complete Show", year: 2023, overview: nil,
        network: "Example Network", status: .continuing, posterURL: nil, existingSeriesID: 1),
    ]
  }

  func add(_ request: SonarrAddSeriesRequest) async throws -> SonarrSeries {
    try? await Task.sleep(for: .milliseconds(150))
    if ProcessInfo.processInfo.environment["UITEST_SONARR_STATE"] == "action-fails" {
      throw AppError.serverUnreachable
    }
    return lock.withLock {
      let added = Self.show(
        id: 900,
        title: request.searchOnAdd ? "\(request.lookup.title) (searching)" : request.lookup.title,
        files: 0, aired: 0, size: 0, monitored: request.monitorOption != .none, seasons: [])
      series.append(added)
      return added
    }
  }

  func update(_ show: SonarrSeries, with edit: SonarrSeriesEdit) async throws -> SonarrSeries {
    try? await Task.sleep(for: .milliseconds(120))
    if ProcessInfo.processInfo.environment["UITEST_SONARR_STATE"] == "action-fails" {
      throw AppError.serverUnreachable
    }
    return lock.withLock {
      guard let index = series.firstIndex(where: { $0.id == show.id }) else { return show }
      let updated = Self.setting(series[index], monitored: edit.isMonitored)
      series[index] = updated
      return updated
    }
  }

  func delete(id: Int, deleteFiles: Bool, addImportExclusion: Bool) async throws {
    lock.withLock { series.removeAll { $0.id == id } }
  }

  /// Season monitoring applies to the season *and* its episodes, exactly as
  /// Sonarr does it server-side — which is what makes "toggling a season
  /// updates its episodes after refresh" a real assertion rather than a
  /// restatement of the flag.
  func setSeasonMonitored(_ isMonitored: Bool, seriesID: Int, seasonNumber: Int) async throws {
    try? await Task.sleep(for: .milliseconds(120))
    if ProcessInfo.processInfo.environment["UITEST_SONARR_STATE"] == "action-fails" {
      throw AppError.serverUnreachable
    }
    lock.withLock {
      guard let index = series.firstIndex(where: { $0.id == seriesID }) else { return }
      let show = series[index]
      let seasons = show.seasons.map { season in
        season.seasonNumber == seasonNumber
          ? SonarrSeason(
            seasonNumber: season.seasonNumber, isMonitored: isMonitored,
            episodeFileCount: season.episodeFileCount, episodeCount: season.episodeCount,
            totalEpisodeCount: season.totalEpisodeCount,
            sizeOnDiskBytes: season.sizeOnDiskBytes, nextAiring: season.nextAiring)
          : season
      }
      series[index] = Self.replacingSeasons(show, with: seasons)
      episodes = episodes.map {
        $0.seriesID == seriesID && $0.seasonNumber == seasonNumber
          ? $0.settingMonitored(isMonitored)
          : $0
      }
    }
  }

  func setEpisodesMonitored(_ isMonitored: Bool, episodeIDs: [Int]) async throws {
    try? await Task.sleep(for: .milliseconds(100))
    if ProcessInfo.processInfo.environment["UITEST_SONARR_STATE"] == "action-fails" {
      throw AppError.serverUnreachable
    }
    lock.withLock {
      episodes = episodes.map {
        episodeIDs.contains($0.id) ? $0.settingMonitored(isMonitored) : $0
      }
    }
  }

  func releases(episodeID: Int) async throws -> [ArrRelease] {
    try? await Task.sleep(for: .milliseconds(150))
    return [
      ArrRelease(
        id: "sonarr-release", title: "Example Series S01E02 1080p",
        indexer: "Example Indexer", indexerID: 3, quality: "WEBDL-1080p",
        sizeBytes: 3_221_225_472, downloadProtocol: .usenet,
        publishDate: nil, ageHours: 8, isApproved: true, rejections: []),
    ]
  }

  func grab(_ release: ArrRelease) async throws {}

  /// The three automatic searches have no visible effect, so they only matter
  /// when they fail: `UITEST_SONARR_STATE=action-fails` makes them throw.
  func searchSeries(id: Int) async throws { try Self.failIfAsked() }
  func searchSeason(seriesID: Int, seasonNumber: Int) async throws { try Self.failIfAsked() }
  func searchEpisodes(ids: [Int]) async throws { try Self.failIfAsked() }

  private static func failIfAsked() throws {
    if ProcessInfo.processInfo.environment["UITEST_SONARR_STATE"] == "action-fails" {
      throw AppError.serverUnreachable
    }
  }

  func qualityProfiles() async throws -> [ArrQualityProfile] {
    [ArrQualityProfile(id: 1, name: "Any"), ArrQualityProfile(id: 4, name: "HD-1080p")]
  }

  func rootFolders() async throws -> [ArrRootFolder] {
    [ArrRootFolder(id: 1, path: "/data/media/tv", isAccessible: true, freeBytes: 3_221_225_472_000)]
  }

  func tags() async throws -> [ArrTag] { [ArrTag(id: 1, label: "anime")] }

  /// Deliberately empty: the queue's empty state has to be reachable from a UI
  /// test too, and this Sonarr is where it lives.
  func queue() async throws -> ArrQueuePage {
    try? await Task.sleep(for: .milliseconds(120))
    return ArrQueuePage(items: [], page: 1, pageSize: 50, totalRecords: 0)
  }

  func removeQueueItem(id: Int, removeFromClient: Bool, blocklist: Bool) async throws {}

  /// Empty on purpose — the calendar and history empty states have to be
  /// reachable from a UI test, and this Sonarr is where they live.
  func calendar(start: Date, end: Date) async throws -> [ArrCalendarEntry] {
    try? await Task.sleep(for: .milliseconds(120))
    return []
  }

  func history(page: Int) async throws -> ArrHistoryPage {
    try? await Task.sleep(for: .milliseconds(120))
    return ArrHistoryPage(records: [], page: 1, pageSize: 50, totalRecords: 0)
  }

  /// A healthy Sonarr — the "no warnings" state has to be reachable too.
  func health() async throws -> [ArrHealthCheck] { [] }

  func diskSpace() async throws -> [ArrDiskSpace] {
    [ArrDiskSpace(path: "/data", label: "data", freeBytes: 1_099_511_627_776, totalBytes: 4_398_046_511_104)]
  }

  func systemStatus() async throws -> ArrSystemStatus {
    ArrSystemStatus(
      appName: "Sonarr", instanceName: "Sonarr", version: "4.0.10.2544", osName: "ubuntu",
      osVersion: "24.04", isDocker: true, startTime: Date().addingTimeInterval(-86_400))
  }

  func runCommand(_ name: String) async throws -> ArrCommand {
    ArrCommand(id: 1, name: name, status: .queued, message: nil, started: nil, ended: nil)
  }

  // MARK: - Fixtures

  private static func replacingSeasons(
    _ show: SonarrSeries, with seasons: [SonarrSeason]
  ) -> SonarrSeries {
    SonarrSeries(
      id: show.id, tvdbID: show.tvdbID, imdbID: show.imdbID, title: show.title,
      sortTitle: show.sortTitle, year: show.year, overview: show.overview,
      network: show.network, runtimeMinutes: show.runtimeMinutes,
      certification: show.certification, genres: show.genres, status: show.status,
      seriesType: show.seriesType, isMonitored: show.isMonitored,
      usesSeasonFolders: show.usesSeasonFolders, qualityProfileID: show.qualityProfileID,
      path: show.path, rootFolderPath: show.rootFolderPath, tagIDs: show.tagIDs,
      added: show.added, nextAiring: show.nextAiring, previousAiring: show.previousAiring,
      posterURL: show.posterURL, fanartURL: show.fanartURL, seasons: seasons,
      statistics: show.statistics)
  }

  private static func setting(_ show: SonarrSeries, monitored: Bool) -> SonarrSeries {
    SonarrSeries(
      id: show.id, tvdbID: show.tvdbID, imdbID: show.imdbID, title: show.title,
      sortTitle: show.sortTitle, year: show.year, overview: show.overview,
      network: show.network, runtimeMinutes: show.runtimeMinutes,
      certification: show.certification, genres: show.genres, status: show.status,
      seriesType: show.seriesType, isMonitored: monitored,
      usesSeasonFolders: show.usesSeasonFolders, qualityProfileID: show.qualityProfileID,
      path: show.path, rootFolderPath: show.rootFolderPath, tagIDs: show.tagIDs,
      added: show.added, nextAiring: show.nextAiring, previousAiring: show.previousAiring,
      posterURL: show.posterURL, fanartURL: show.fanartURL, seasons: show.seasons,
      statistics: show.statistics)
  }

  private static func season(
    _ number: Int, monitored: Bool, files: Int, aired: Int, total: Int, size: Int64
  ) -> SonarrSeason {
    SonarrSeason(
      seasonNumber: number, isMonitored: monitored, episodeFileCount: files,
      episodeCount: aired, totalEpisodeCount: total, sizeOnDiskBytes: size, nextAiring: nil)
  }

  private static func episode(
    id: Int, series: Int, season: Int, number: Int, title: String, hasFile: Bool,
    aired: Date, size: Int64 = 0, monitored: Bool = true
  ) -> SonarrEpisode {
    SonarrEpisode(
      id: id, seriesID: series, seasonNumber: season, episodeNumber: number, title: title,
      overview: "An episode that exists only in a fixture.", airDate: aired,
      runtimeMinutes: 45, hasFile: hasFile, isMonitored: monitored,
      file: hasFile
        ? SonarrEpisodeFile(
          id: id, relativePath: "Season \(season)/\(title).mkv", sizeBytes: size,
          quality: "WEBDL-1080p", releaseGroup: "GROUP", videoCodec: "h264",
          audioCodec: "EAC3", resolution: "1920x1080", languages: ["eng"], dateAdded: aired)
        : nil)
  }

  private static func show(
    id: Int, title: String, files: Int, aired: Int, size: Int64, monitored: Bool = true,
    seasons: [SonarrSeason] = []
  ) -> SonarrSeries {
    SonarrSeries(
      id: id, tvdbID: id, imdbID: nil, title: title, sortTitle: title.lowercased(), year: 2023,
      overview: "A series that exists only in a fixture.", network: "Example Network",
      runtimeMinutes: 45, certification: "TV-MA", genres: ["Drama"], status: .continuing,
      seriesType: .standard, isMonitored: monitored, usesSeasonFolders: true,
      qualityProfileID: 1, path: "/data/media/tv/\(title)", rootFolderPath: "/data/media/tv",
      tagIDs: [], added: Date(timeIntervalSince1970: 1_690_000_000), nextAiring: nil,
      previousAiring: nil, posterURL: nil, fanartURL: nil, seasons: seasons,
      statistics: SonarrSeriesStatistics(
        seasonCount: max(seasons.count, 1), episodeFileCount: files, episodeCount: aired,
        totalEpisodeCount: aired + 2, sizeOnDiskBytes: size))
  }
}

/// Demo mode's NZBGet with its two history actions made to fail, for the one
/// case demo data cannot reach: a failed retry or delete on the History tab.
///
/// Built only under `UITEST_NZBGET_STATE=action-fails`; otherwise the seeded
/// NZBGet keeps its generic instance screen. Everything else is the
/// demo repository's, so the queue and history load as they do in demo mode.
struct FakeNZBGetRepository: NZBGetRepositoryProtocol {
  private let base: DemoNZBGetRepository

  init?(instance: ServiceInstance, server: DemoNZBServer) {
    guard ProcessInfo.processInfo.environment["UITEST_NZBGET_STATE"] == "action-fails" else {
      return nil
    }
    base = DemoNZBGetRepository(instance: instance, server: server)
  }

  var instance: ServiceInstance { base.instance }

  func queue() async throws -> [NZBGroup] { try await base.queue() }
  func history() async throws -> [NZBHistoryItem] { try await base.history() }
  func status() async throws -> NZBServerStatus { try await base.status() }
  func pause(ids: [Int]) async throws { try await base.pause(ids: ids) }
  func resume(ids: [Int]) async throws { try await base.resume(ids: ids) }
  func setPriority(_ priority: NZBPriority, ids: [Int]) async throws {
    try await base.setPriority(priority, ids: ids)
  }
  func delete(ids: [Int]) async throws { try await base.delete(ids: ids) }
  func pauseAll() async throws { try await base.pauseAll() }
  func resumeAll() async throws { try await base.resumeAll() }
  func setSpeedLimit(bytesPerSecond: Int64?) async throws {
    try await base.setSpeedLimit(bytesPerSecond: bytesPerSecond)
  }

  func retryHistory(ids: [Int]) async throws { throw AppError.serverUnreachable }
  func deleteHistory(ids: [Int]) async throws { throw AppError.serverUnreachable }
}

#endif
