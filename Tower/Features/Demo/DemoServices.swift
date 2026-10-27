import Foundation
import TowerCore
import TowerData

/// The nine services demo mode presents, at least one per kind.
///
/// **Every service is populated.** Demo mode is the only path a reviewer
/// without a server has through this app — no reviewer has a Radarr — so an
/// empty hub is a hub a reviewer never sees working.
///
/// Shaped like a real stack rather than nine identical green rows: a 4K Radarr
/// alongside the main one is the reason multi-instance exists, and one service
/// is unreachable because a media stack with a container down is the normal
/// case, and the badge is worth seeing.
enum DemoServices {
  /// TEST-NET-1 (RFC 5737), as with `DemoData.server`: reserved for
  /// documentation and guaranteed never to route, so a screenshot can't leak an
  /// address and a bug that somehow reached the network would fail immediately.
  private static let host = "192.0.2.10"

  /// One instance of every kind, plus a second Radarr. Ports are each service's
  /// stock port, which is what a reader recognises.
  static let instances: [ServiceInstance] = [
    instance(.radarr, "Radarr"),
    instance(.radarr, "Radarr 4K", port: 7879),
    instance(.sonarr, "Sonarr"),
    instance(.lidarr, "Lidarr"),
    instance(.bazarr, "Bazarr"),
    instance(.overseerr, "Overseerr"),
    instance(.prowlarr, "Prowlarr"),
    instance(.nzbget, "NZBGet"),
    instance(.tautulli, "Tautulli"),
  ]

  /// The directory demo mode hands to the hub. In-memory, so nothing demo mode
  /// does can reach the keychain, and rebuilt on every entry — a reviewer who
  /// deleted a service and came back sees the intended stack again.
  static func directory() -> ServiceDirectory {
    .inMemory(instances)
  }

  private static func instance(
    _ kind: ServiceKind, _ name: String, port: Int? = nil
  ) -> ServiceInstance {
    let resolved = port ?? ServiceDiscovery.defaultPort(for: kind)
    return ServiceInstance(
      id: UUID(uuidString: "D0000000-0000-0000-0000-0000000000\(idSuffix(name))")!,
      kind: kind,
      name: name,
      baseURL: URL(string: "http://\(host):\(resolved)")!,
      // Visibly fake, and never displayed: the form is the only place a
      // credential is shown, and demo mode's records exist to populate a list.
      credentials: kind.credentialStyle == .apiKey
        ? .apiKey("demo-mode-no-key")
        : .usernamePassword(username: "demo", password: "demo-mode-no-password")
    )
  }

  /// Stable ids so a demo instance keeps its identity across a rebuild of the
  /// environment — otherwise a reviewer's selected row would change under them
  /// when the demo is re-entered.
  ///
  /// The empty string holds slot 08 as a reserved id, so NZBGet and Tautulli
  /// keep 09 and 10. UI tests address demo instances by these ids, so a slot
  /// never moves.
  private static func idSuffix(_ name: String) -> String {
    let index = ["Radarr", "Radarr 4K", "Sonarr", "Lidarr", "Bazarr", "Overseerr",
                 "Prowlarr", "", "NZBGet", "Tautulli"]
      .firstIndex(of: name) ?? 0
    return String(format: "%02d", index + 1)
  }
}

/// Demo health for the seeded services: everything up except one, and no
/// network call of any kind.
///
/// The unreachable one is deliberate. A hub of nine identical "Connected" rows
/// shows a reviewer nothing about what the badge means, and a stack where
/// something is down is the ordinary case, not the exception.
struct DemoServiceStatusChecker: ServiceStatusChecking {
  /// Matches `DemoLatency.read` in `DemoRepositories` — without it the rows
  /// snap to resolved and the "Checking…" state is never seen.
  private static let latency = Duration.milliseconds(450)

  func status(for instance: ServiceInstance) async -> ServiceStatus {
    try? await Task.sleep(for: Self.latency)
    switch instance.kind {
    // One service down on purpose: a hub of uniformly green rows advertises
    // less than one that shows Tower noticing something is wrong.
    //
    // **Sonarr, not Lidarr.** The App Store listing shows the hub and, later,
    // Lidarr's library working, so marking Lidarr unreachable would put a
    // contradiction in the store's own set. Sonarr's screens appear nowhere in
    // the listing, so the error treatment stays visible in the hub shot
    // without disagreeing with anything.
    case .sonarr:
      return .unreachable(.serverUnreachable)
    // Each kind reports its own version. Radarr, Lidarr and NZBGet match the
    // version their own demo status reports.
    case .radarr:
      return .reachable(version: "5.14.0.9383")
    case .lidarr:
      return .reachable(version: "2.1.7.4030")
    case .prowlarr:
      return .reachable(version: "1.24.3.4754")
    case .bazarr:
      return .reachable(version: "1.4.5")
    case .nzbget:
      return .reachable(version: "21.1")
    default:
      return .reachable(version: nil)
    }
  }
}
