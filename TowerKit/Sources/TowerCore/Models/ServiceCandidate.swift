import Foundation

/// A service Tower recognised among the Unraid box's running containers, ready
/// to prefill the add-service form.
///
/// **Address only.** No credential is ever inferred: the API key is not read
/// from the container's environment, guessed from a template, or defaulted. The
/// user pastes it. Everything here is derived from the image name and the
/// published ports, which the container list already reports.
public struct ServiceCandidate: Identifiable, Equatable, Sendable {
  /// The container's id, so the list is stable across refreshes.
  public let id: String
  public let kind: ServiceKind
  /// The container's own name, offered as the instance name.
  public let containerName: String
  public let baseURL: URL

  public init(id: String, kind: ServiceKind, containerName: String, baseURL: URL) {
    self.id = id
    self.kind = kind
    self.containerName = containerName
    self.baseURL = baseURL
  }
}

/// Matches running containers to the eight services.
public enum ServiceDiscovery {
  /// The candidates among `containers`, addressed on `serverHost`.
  ///
  /// Only running containers: a stopped service can't be tested, and offering
  /// one produces a candidate whose connection test fails for a reason that has
  /// nothing to do with what the user typed.
  public static func candidates(in containers: [Container], serverURL: URL) -> [ServiceCandidate] {
    containers.compactMap { container in
      // **Matching** (below) has the opposite requirement and deliberately
      // does not filter on running state.
      guard container.isRunning else { return nil }
      return candidate(for: container, serverURL: serverURL)
    }
  }

  /// One container's candidate, **whatever its state**.
  ///
  /// Separate from `candidates(in:serverURL:)` because the service-to-container
  /// cross-link needs a stopped container to resolve: a service showing
  /// "unreachable" is exactly when the user wants the container that explains
  /// why, and that container is by definition not running.
  public static func candidate(for container: Container, serverURL: URL) -> ServiceCandidate? {
    guard let host = serverURL.host(), let kind = kind(forImage: container.image) else {
      return nil
    }
    guard let url = URL(string: "http://\(bracketed(host)):\(port(for: kind, in: container))")
    else { return nil }
    return ServiceCandidate(
      id: container.id, kind: kind, containerName: container.displayName, baseURL: url)
  }

  /// The kind an image name names, or `nil`.
  ///
  /// **Exact match on the image's final path component**, after dropping the
  /// registry, the tag, and any digest — so `linuxserver/sonarr:latest`,
  /// `ghcr.io/hotio/sonarr`, and a bare `sonarr` all match, while
  /// `radarr-exporter`, `sonarr-backup`, and `prowlarr-indexer-proxy` do not.
  /// A `contains` check would match all three and offer the user a Radarr that
  /// is really a metrics scraper.
  public static func kind(forImage image: String) -> ServiceKind? {
    var name = image.lowercased()
    if let digest = name.firstIndex(of: "@") { name = String(name[name.startIndex..<digest]) }
    // The tag separator is a colon in the *last* path component; a registry
    // host can carry a port colon too (`registry:5000/linuxserver/sonarr`).
    var component = name.split(separator: "/").last.map(String.init) ?? name
    if let tag = component.firstIndex(of: ":") { component = String(component[..<tag]) }
    return imageNames[component]
  }

  /// Recognised final components. Deliberately a fixed list rather than a
  /// fuzzy match — a false positive here sends someone configuring a service
  /// against a container that doesn't speak its API.
  private static let imageNames: [String: ServiceKind] = [
    "radarr": .radarr,
    "sonarr": .sonarr,
    "lidarr": .lidarr,
    "prowlarr": .prowlarr,
    "bazarr": .bazarr,
    "overseerr": .overseerr,
    "tautulli": .tautulli,
    "nzbget": .nzbget,
  ]

  /// The published port to address the service on.
  ///
  /// Prefers the published port mapped to the service's own default (a Sonarr
  /// remapped to 18989 externally is still 8989 inside the container), then any
  /// published port, and only then the default itself — which is right for
  /// `network_mode: host`, where Docker reports no port mappings at all.
  private static func port(for kind: ServiceKind, in container: Container) -> Int {
    let published = container.ports.compactMap { port -> (public: Int, private: Int?)? in
      guard let publicPort = port.publicPort else { return nil }
      return (publicPort, port.privatePort)
    }
    if let matching = published.first(where: { $0.private == defaultPort(for: kind) }) {
      return matching.public
    }
    return published.first?.public ?? defaultPort(for: kind)
  }

  /// Each service's stock port, as its own documentation ships it.
  public static func defaultPort(for kind: ServiceKind) -> Int {
    switch kind {
    case .radarr: 7878
    case .sonarr: 8989
    case .lidarr: 8686
    case .prowlarr: 9696
    case .bazarr: 6767
    case .overseerr: 5055
    case .nzbget: 6789
    case .tautulli: 8181
    }
  }

  /// An IPv6 literal needs its brackets back before it goes into a URL string.
  private static func bracketed(_ host: String) -> String {
    host.contains(":") && !host.hasPrefix("[") ? "[\(host)]" : host
  }
}
