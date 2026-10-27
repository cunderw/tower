import Foundation
import TowerCore
import TowerData

@MainActor
struct AppEnvironment {
  var serverStore: any ServerStoring
  var makeRepository: (Server) -> any SystemRepositoryProtocol
  var makeDockerRepository: (Server) -> any DockerRepositoryProtocol
  var makeVMRepository: (Server) -> any VMRepositoryProtocol
  var makeShareRepository: (Server) -> any ShareRepositoryProtocol
  var makeNotificationRepository: (Server) -> any NotificationRepositoryProtocol
  var makeLogRepository: (Server) -> any LogRepositoryProtocol

  /// The configured media-stack services. Unlike the Unraid repositories above,
  /// these are plural — several Radarrs coexist — so the environment holds the
  /// directory and a factory rather than one repository per feature.
  var serviceDirectory: any ServiceDirectoryStoring
  var serviceStatusChecker: any ServiceStatusChecking
  var makeServiceRepository: ServiceRepositoryFactory

  /// Keeps each service's top-level store alive across navigation.
  ///
  /// **Here rather than in a view** because that is the whole point: owned
  /// above the navigation hierarchy, it outlives the screens that read it. Live
  /// and demo each construct their own, which is also what guarantees nothing
  /// survives a switch between them.
  var serviceStores = ServiceStoreRegistry()

  static let live = AppEnvironment(
    serverStore: KeychainServerStore(),
    makeRepository: { server in
      LiveSystemRepository(provider: ApolloClientProvider(server: server))
    },
    makeDockerRepository: { server in
      LiveDockerRepository(provider: ApolloClientProvider(server: server))
    },
    makeVMRepository: { server in
      LiveVMRepository(provider: ApolloClientProvider(server: server))
    },
    makeShareRepository: { server in
      LiveShareRepository(provider: ApolloClientProvider(server: server))
    },
    makeNotificationRepository: { server in
      LiveNotificationRepository(provider: ApolloClientProvider(server: server))
    },
    makeLogRepository: { server in
      LiveLogRepository(provider: ApolloClientProvider(server: server))
    },
    serviceDirectory: ServiceDirectory.keychain(),
    serviceStatusChecker: LiveServiceStatusChecker(),
    // Every `ServiceKind` has a live client, so this
    // switch is exhaustive and deliberately carries no `default` — a new
    // service should fail to compile here rather than silently land on the
    // hub's fallback configuration screen.
    makeServiceRepository: { instance in
      switch instance.kind {
      case .radarr: LiveRadarrRepository(instance: instance)
      case .sonarr: LiveSonarrRepository(instance: instance)
      case .nzbget: LiveNZBGetRepository(instance: instance)
      case .overseerr: LiveOverseerrRepository(instance: instance)
      case .prowlarr: LiveProwlarrRepository(instance: instance)
      case .lidarr: LiveLidarrRepository(instance: instance)
      case .bazarr: LiveBazarrRepository(instance: instance)
      case .tautulli: LiveTautulliRepository(instance: instance)
      }
    }
  )

  /// Demo mode: every repository is a demo conformance sharing one in-memory
  /// server, and the credential store is in-memory too so nothing reaches the
  /// keychain.
  ///
  /// **One assignment, and nothing else in the app knows.** No view or store
  /// branches on whether this is the demo — that is what making repositories
  /// protocols buys.
  ///
  /// Deliberately **not** `#if DEBUG`, unlike `UITestSupport`'s fakes: demo mode
  /// ships. It is how an App Store reviewer, who has no Unraid server, sees the
  /// app at all.
  static var demo: AppEnvironment {
    // One server, six repositories, built fresh on every entry — so a reviewer who
    // stopped half the containers and came back sees the intended dataset rather
    // than the wreckage of their last visit, with no `reset()` anyone has to
    // remember to call.
    let server = DemoServer()
    return AppEnvironment(
      serverStore: InMemoryServerStore(),
      makeRepository: { _ in DemoSystemRepository(server: server) },
      makeDockerRepository: { _ in DemoDockerRepository(server: server) },
      makeVMRepository: { _ in DemoVMRepository(server: server) },
      makeShareRepository: { _ in DemoShareRepository(server: server) },
      makeNotificationRepository: { _ in DemoNotificationRepository(server: server) },
      makeLogRepository: { _ in DemoLogRepository(server: server) },
      // One instance of every kind, in memory — demo mode never touches the
      // keychain, and never leaves the device.
      serviceDirectory: DemoServices.directory(),
      serviceStatusChecker: DemoServiceStatusChecker(),
      // One shared *arr dataset per demo entry, so grabbing a release in the
      // search screen shows up in the queue: the demo path, end to end.
      makeServiceRepository: {
        [
          arrServer = DemoArrServer(),
          nzbServer = DemoNZBServer(), overseerrServer = DemoOverseerrServer(),
          prowlarrServer = DemoProwlarrServer(), lidarrServer = DemoLidarrServer(),
          bazarrServer = DemoBazarrServer(), tautulliServer = DemoTautulliServer()
        ] instance in
        switch instance.kind {
        case .radarr: DemoRadarrRepository(instance: instance, server: arrServer)
        case .sonarr: DemoSonarrRepository(instance: instance, server: arrServer)
        // One shared dataset for the client too, so the queue row's "Open in
        // NZBGet" link lands on an item that exists — the join key is
        // `DemoDownloadIDs`, referenced from both fixture sets.
        case .nzbget: DemoNZBGetRepository(instance: instance, server: nzbServer)
        case .overseerr:
          DemoOverseerrRepository(instance: instance, server: overseerrServer)
        case .prowlarr: DemoProwlarrRepository(instance: instance, server: prowlarrServer)
        // Lidarr takes the *arr dataset too: its queue and history come from
        // `ArrClientCore`, so sharing `arrServer` keeps one story across the
        // whole demo rather than a second, disagreeing set of downloads.
        case .lidarr:
          DemoLidarrRepository(instance: instance, server: lidarrServer, arrServer: arrServer)
        case .bazarr: DemoBazarrRepository(instance: instance, server: bazarrServer)
        case .tautulli: DemoTautulliRepository(instance: instance, server: tautulliServer)
        }
      }
    )
  }

  /// Clears the stored server credential. Deliberately non-throwing: a failed
  /// keychain delete must never block the caller from returning to the connect
  /// screen — leaving the app on the dashboard because `serverStore.clear()`
  /// threw would strand the user signed in while they believe their credentials
  /// are gone, which is a privacy failure, not a recoverable error. The failure
  /// is swallowed here (there is nowhere useful to surface it to the user), not
  /// propagated, so `RootView`'s `onSignOut` always runs.
  func signOut() {
    // Retained service data must not outlive the session that fetched it.
    // In memory only, so this is the whole of its lifetime.
    serviceStores.removeAll()
    do {
      try serverStore.clear()
    } catch {
      #if DEBUG
      print("AppEnvironment.signOut(): serverStore.clear() failed: \(error)")
      #endif
    }
  }
}
