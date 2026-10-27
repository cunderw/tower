import SwiftUI
import TowerCore
import TowerData

/// Resolves an instance to the screen that can manage it.
///
/// The hub pushes this; it asks the environment's factory for a repository and
/// builds the matching shell. A kind with no client falls through to the
/// configuration/status screen, which is what `nil` from the factory means.
///
/// **Stores come from the registry, not from here.** A store constructed
/// inline in the `@ViewBuilder` below would live only as long as this view's
/// body evaluation: navigating away and back would build a new one — the cold
/// load on every re-entry — and, worse, so would any change to
/// `servicesStore.instances`, which this view reads for `downloadClients`. A
/// populated library would blank mid-session with no navigation involved.
///
/// Two Radarrs are still two `RadarrLibraryStore`s with independent state; the
/// registry keys by instance id, and the `.id()` below still stops SwiftUI
/// reusing one screen for the other.
struct ArrServiceScreen: View {
  let instance: ServiceInstance
  let servicesStore: ServicesStore
  let makeRepository: ServiceRepositoryFactory
  /// Passed explicitly, like `servicesStore` and `makeRepository` — this app
  /// hands `AppEnvironment`'s pieces down rather than putting them in the
  /// SwiftUI environment, and one member reached a different way would be the
  /// odd one out.
  let serviceStores: ServiceStoreRegistry

  /// Reads the retained store for this instance, building it once.
  private func store<Store: AnyObject>(_ make: () -> Store) -> Store {
    serviceStores.store(for: instance.id, make: make)
  }

  var body: some View {
    content
      .id(instance.id)
  }

  /// The queue rows' way into whichever download client is fetching them.
  /// Built from the hub's own instance list, so a client the user has
  /// not configured in Tower simply produces no match.
  private var downloadClients: DownloadClientNavigator {
    DownloadClientNavigator(
      instances: servicesStore.instances, makeRepository: makeRepository)
  }

  @ViewBuilder
  private var content: some View {
    switch makeRepository(instance) {
    case let radarr as any RadarrRepositoryProtocol:
      RadarrServiceView(
        instance: instance, store: store { RadarrLibraryStore(repository: radarr) },
        downloadClients: downloadClients)
    case let sonarr as any SonarrRepositoryProtocol:
      SonarrServiceView(
        instance: instance, store: store { SonarrLibraryStore(repository: sonarr) },
        downloadClients: downloadClients)
    case let nzbget as any NZBGetRepositoryProtocol:
      NZBGetServiceView(
        instance: instance, store: store { NZBGetStore(repository: nzbget) })
    case let overseerr as any OverseerrRepositoryProtocol:
      OverseerrServiceView(
        instance: instance, store: store { OverseerrRequestsStore(repository: overseerr) })
    case let lidarr as any LidarrRepositoryProtocol:
      LidarrServiceView(
        instance: instance, store: store { LidarrLibraryStore(repository: lidarr) },
        downloadClients: downloadClients)
    case let bazarr as any BazarrRepositoryProtocol:
      BazarrServiceView(
        instance: instance, store: store { BazarrStore(repository: bazarr) })
    case let tautulli as any TautulliRepositoryProtocol:
      TautulliServiceView(
        instance: instance, store: store { TautulliActivityStore(repository: tautulli) })
    case let prowlarr as any ProwlarrRepositoryProtocol:
      ProwlarrServiceView(
        instance: instance, store: store { ProwlarrIndexersStore(repository: prowlarr) })
    default:
      ServiceInstanceDetailView(store: servicesStore, instanceID: instance.id)
    }
  }
}
