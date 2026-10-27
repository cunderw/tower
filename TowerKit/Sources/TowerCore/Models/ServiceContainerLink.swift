import Foundation

/// Matches a configured service instance to the Docker container running it,
/// in both directions.
///
/// The container screen is where you restart and read logs; the service screen
/// is where you see the queue and act on media. They are two views of one thing,
/// so each links to the other, and "why is Radarr unreachable" does not mean
/// backing out to the hub and finding the container by name.
///
/// **Matched on address, never on kind alone.** Kind is wrong the moment there
/// are two Radarrs, which is the standard setup — a 4K instance alongside a
/// regular one. Two containers of the same image are distinguished only by the
/// port they publish, so the port is the identity. Kind is still checked, as a
/// consistency guard rather than as the match.
///
/// **A near miss is no link, not a guess.** A service reached through a reverse
/// proxy, a different hostname, or a Tailscale address will not match its
/// container, and that is the correct outcome: the container screen carries
/// Restart and Stop, so a link to the *wrong* container invites restarting the
/// wrong service. Silence is cheap; a confident wrong link is not.
public enum ServiceContainerLink {
  /// The container backing `instance`, or `nil`.
  ///
  /// Deliberately tolerant of a **stopped** container — see
  /// `ServiceDiscovery.candidate(for:serverURL:)`. An unreachable service is
  /// the case where this link is most wanted.
  public static func container(
    for instance: ServiceInstance,
    in containers: [Container],
    serverURL: URL
  ) -> Container? {
    containers.first { container in
      guard let candidate = ServiceDiscovery.candidate(for: container, serverURL: serverURL) else {
        return false
      }
      return matches(instance: instance, candidate: candidate)
    }
  }

  /// The configured instance `container` is running, or `nil`.
  public static func instance(
    for container: Container,
    in instances: [ServiceInstance],
    serverURL: URL
  ) -> ServiceInstance? {
    guard let candidate = ServiceDiscovery.candidate(for: container, serverURL: serverURL) else {
      return nil
    }
    return instances.first { matches(instance: $0, candidate: candidate) }
  }

  /// Host **and** port **and** kind, all three.
  ///
  /// Host comparison is case-insensitive because a hostname is, and IPv6
  /// literals are compared after `URL` has already normalised their brackets.
  /// The port is resolved through `defaultPort` on both sides so an address
  /// written without one (`http://tower:80` vs `http://tower`) still matches
  /// what the container publishes.
  private static func matches(instance: ServiceInstance, candidate: ServiceCandidate) -> Bool {
    guard instance.kind == candidate.kind else { return false }
    guard let lhs = instance.baseURL.host()?.lowercased(),
          let rhs = candidate.baseURL.host()?.lowercased(),
          lhs == rhs
    else { return false }
    return port(of: instance.baseURL) == port(of: candidate.baseURL)
  }

  /// An explicit port, or the scheme's default when the address omits one.
  private static func port(of url: URL) -> Int? {
    if let port = url.port { return port }
    switch url.scheme?.lowercased() {
    case "http": return 80
    case "https": return 443
    default: return nil
    }
  }
}
