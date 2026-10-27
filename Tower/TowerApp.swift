import SwiftUI
import TowerCore

@main
struct TowerApp: App {
  @State private var environment = AppEnvironment.live
  @State private var phase: LaunchPhase = .checking
  /// Owned here because it applies to the whole scene, including the connect
  /// screen — a user who picked Dark shouldn't get a white flash on sign-out.
  @State private var theme = ThemePreference()

  var body: some Scene {
    WindowGroup {
      content
        // Applied at the scene root so it covers the connect screen too, not just
        // the tab shell. `nil` for `.system`, which is how SwiftUI spells "follow
        // the device". Covering `.checking` as well is what keeps a Dark-mode
        // user from getting a white launch placeholder.
        .preferredColorScheme(theme.theme.colorScheme)
    }
  }

  /// Which of the three root surfaces is on screen.
  ///
  /// Not a `Server?`, because a `nil` there would do two jobs: "there is no
  /// stored credential" and "we haven't looked yet". The look happens in a
  /// `.task`, which runs *after* the first frame, so every launch with a saved
  /// credential would render `ConnectView` for a beat before `RootView`
  /// replaced it, telling the user they were signed out when they weren't.
  /// A third case makes "haven't looked yet" unrepresentable as
  /// "signed out".
  private enum LaunchPhase {
    case checking
    case connect
    case connected(Server)
  }

  /// Extracted so `.preferredColorScheme` has a single view to attach to rather
  /// than being duplicated across all three branches.
  @ViewBuilder
  private var content: some View {
    switch phase {
    case .checking:
      LaunchPlaceholderView()
        .task { await resolveLaunchPhase() }

    case .connect:
      ConnectView(
        store: ConnectStore(
          serverStore: environment.serverStore,
          makeRepository: environment.makeRepository
        ),
        onConnected: { phase = .connected($0) },
        onTryDemo: {
          // Swapping the environment *before* setting the phase matters:
          // `RootView.init` builds all seven stores from it, so a reversed order
          // would hand the demo screen live repositories pointed at a
          // documentation IP.
          environment = .demo
          phase = .connected(DemoData.server)
        }
      )

    case .connected(let server):
      RootView(
        server: server,
        environment: environment,
        theme: theme,
        // Straight to `.connect`, never back through `.checking` — the
        // credential has just been cleared, so there is nothing to look up and a
        // placeholder here would be a spinner in front of a known answer.
        onSignOut: { phase = .connect }
      )
    }
  }

  /// Decides what the app opens onto. Runs once, from `.checking`, with nothing
  /// but the launch placeholder on screen.
  private func resolveLaunchPhase() async {
    #if DEBUG
    let arguments = ProcessInfo.processInfo.arguments
    // UI-test launch argument: holds this phase open long enough for a test to
    // assert what is on screen during it. Without it the keychain read finishes
    // within a frame or two, so the placeholder is real but unobservable, and
    // a connect form filling this window instead would have nothing to assert
    // against. Debug-only for the same reason as
    // the two arguments below.
    if arguments.contains("--uitest-slow-launch-check") {
      try? await Task.sleep(for: .seconds(3))
    }
    // UI-test launch argument: guarantees a clean, credential-free
    // starting state for XCUITest runs. Debug-only: in a shipped or
    // TestFlight build this would let anyone able to pass launch
    // arguments (Xcode attached, simctl, an MDM launch profile)
    // silently wipe the user's stored credential.
    if arguments.contains("--uitest-reset-credentials") {
      try? environment.serverStore.clear()
      phase = .connect
      return
    }
    // UI-test launch argument: reaches `RootView` without a live
    // Unraid box or keychain access. XCUITest can't write the
    // keychain (closing off the normal connect flow) and there is no
    // real server for `ConnectStore.connect()`'s `testConnection()`
    // to reach, so this seeds the phase directly from
    // `UITestFixtures.server` and swaps `environment.makeRepository`
    // for `FakeSystemRepository`, which returns canned data instead
    // of making a network call. `UITEST_DASHBOARD_STATE` in
    // `launchEnvironment` selects the outcome: unset/anything else is
    // `.success`, `failure` is a permanent failed load,
    // `retry-succeeds` fails only the first `dashboard()` call so
    // `DashboardUITests` can prove tapping "Try Again" actually
    // recovers the screen, `nil-metrics` is a successful load with
    // no CPU/memory percent so `MetricGauge`'s nil-`percent`
    // accessibility value is reachable from a UI test, and
    // `disk-temp-oscillates` backs `DiskDetailUITests`' liveness proof
    // that the disk detail screen reflects a store update
    // made while it's open.
    // Debug-only for the same reason as the argument above: it can
    // force a shipped app to skip authentication entirely.
    if arguments.contains("--uitest-seed-dashboard") {
      let outcome: FakeSystemRepository.Outcome
      switch ProcessInfo.processInfo.environment["UITEST_DASHBOARD_STATE"] {
      case "failure": outcome = .failure(.serverUnreachable)
      case "retry-succeeds": outcome = .failFirstThenRecover
      case "nil-metrics": outcome = .unknownMetrics
      case "disk-temp-oscillates": outcome = .diskTempOscillates
      case "hangs": outcome = .hangs
      default: outcome = .success
      }
      environment.makeRepository = { _ in FakeSystemRepository(outcome: outcome) }
      // The Docker tab is a real `DockerListView` — without this it would
      // try to reach `UITestFixtures.server`'s unreachable URL for real. Its
      // own `UITEST_DOCKER_STATE` is read inside `FakeDockerRepository
      // .containers()` rather than switched on here, because it selects
      // fixture variations rather than a repository-wide outcome the way
      // `UITEST_DASHBOARD_STATE` does above: `container-vanishes` is a
      // behaviour *across* calls (one container disappearing after the
      // first response), and `service-containers` adds media-service
      // containers to the list. See that method's doc comment.
      environment.makeDockerRepository = { _ in FakeDockerRepository() }
      // Same reason as the Docker line above: the VMs tab is a real
      // `VMListView`. Its own `UITEST_VMS_STATE` is read
      // inside `FakeVMRepository.domains()` — it selects an
      // inventory-wide outcome (`unavailable`, `empty`, or the seeded
      // five), and reading it there rather than switching on it here
      // keeps the "VMs unavailable" case a property of the fixture data
      // rather than a third launch argument.
      environment.makeVMRepository = { _ in FakeVMRepository() }
      // The Shares tab. Its own
      // `UITEST_SHARES_STATE` is read inside `FakeShareRepository.shares()`,
      // matching how the Docker and VM fakes read theirs.
      environment.makeShareRepository = { _ in FakeShareRepository() }
      // `UITEST_NOTIFICATIONS_STATE` is read inside the fake, same as the
      // other three.
      environment.makeNotificationRepository = { _ in FakeNotificationRepository() }
      environment.makeLogRepository = { _ in FakeLogRepository() }
      // The Services hub. Its directory is in-memory rather than the
      // keychain — XCUITest can't write one — and its checker is canned, so no
      // request leaves the simulator. `UITEST_SERVICES_STATE` is read inside
      // `UITestServices.directory()`, matching how the other fakes read theirs.
      environment.serviceDirectory = UITestServices.directory()
      environment.serviceStatusChecker = FakeServiceStatusChecker()
      // The *arr shells run against canned libraries — the seeded
      // instances' addresses are documentation IPs and are never dialled.
      // NZBGet is demo data with failing history actions, and only under
      // `UITEST_NZBGET_STATE=action-fails`; otherwise it has no repository.
      environment.makeServiceRepository = { [nzbServer = DemoNZBServer()] instance in
        switch instance.kind {
        case .radarr: FakeRadarrRepository(instance: instance)
        case .sonarr: FakeSonarrRepository(instance: instance)
        case .nzbget: FakeNZBGetRepository(instance: instance, server: nzbServer)
        default: nil
        }
      }
      phase = .connected(UITestFixtures.server)
      return
    }
    #endif
    // Skip the connect screen when credentials are already stored.
    if let server = try? environment.serverStore.load() {
      phase = .connected(server)
    } else {
      phase = .connect
    }
  }
}
