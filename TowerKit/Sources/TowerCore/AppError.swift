import Foundation

public enum AppError: Error, Equatable, Sendable {
  case unauthorized
  case localNetworkDenied
  case offline
  case serverUnreachable
  case invalidServerURL
  case insecureConnection
  case graphQL([String])
  case decoding(String)
  /// A mutation the server accepted, answered successfully, and then declined
  /// to perform. Unraid's `VmMutations` actions all return `Boolean!` rather
  /// than a domain object (unlike `DockerMutations`), and `false` is a
  /// refusal — no GraphQL error, no transport failure, nothing for
  /// `.graphQL`/`.serverUnreachable` to describe. Collapsing it into
  /// `.unknown` would put `String(describing:)` noise in front of a user who
  /// needs one fact: the thing they pressed did not happen.
  case actionRefused(String)
  /// An optional Unraid service, named by the associated value, that is
  /// disabled or stopped, so the server cannot answer for it at all. Docker
  /// is the one that throws it today: with the service off, the containers
  /// resolver fails with "Docker socket unavailable.". Named for the
  /// condition rather than for Docker, for the reason `actionRefused`'s
  /// recovery text gives.
  case serviceUnavailable(String)
  /// A load the user (or a superseding request) cancelled.
  ///
  /// Deliberately a failure rather than a return to `.idle`: every screen already
  /// renders `.failed` with a "Try Again" button, so a cancelled load lands
  /// somewhere with a way forward instead of back on an indefinite spinner. It is
  /// also not `.unknown` — nothing went wrong, and a user who pressed Cancel
  /// should not be shown an error that reads like a fault.
  case cancelled
  case unknown(String)

  public var message: String {
    switch self {
    case .unauthorized:
      "The server rejected these credentials."
    case .localNetworkDenied:
      "Tower can't reach devices on your local network."
    case .offline:
      "This device isn't connected to a network."
    case .serverUnreachable:
      "Couldn't reach the server."
    case .invalidServerURL:
      "That doesn't look like a valid server address."
    case .insecureConnection:
      "Tower couldn't establish a secure connection to the server."
    case .graphQL(let messages):
      messages.joined(separator: "\n")
    case .decoding(let detail):
      "The server sent something Tower couldn't read. \(detail)"
    case .actionRefused(let detail):
      detail
    case .serviceUnavailable(let service):
      "\(service) isn't available on this server."
    case .cancelled:
      "Cancelled."
    case .unknown(let detail):
      detail
    }
  }

  public var recoverySuggestion: String? {
    switch self {
    case .unauthorized:
      "Check the API key in Unraid under Settings ▸ Management Access."
    case .localNetworkDenied:
      "Allow local network access in Settings ▸ Tower."
    case .offline:
      "Connect to Wi-Fi or cellular, then try again."
    case .serverUnreachable:
      "Check the address and make sure you're on the same network or VPN."
    case .invalidServerURL:
      // Describes the shape rather than naming an address. `normalizedURL`
      // rejects exactly two things — a missing scheme and a missing host — so
      // the suggestion names both instead of showing one example IP that is
      // only ever right for one person's network.
      "Include http:// or https:// and the server's address or hostname."
    case .insecureConnection:
      "Unraid servers often use a self-signed certificate. Try the http:// address instead of https://."
    case .actionRefused:
      // Deliberately not "the VM may already be…": `AppError` is shared by
      // every feature, and a case that names one of them would read wrong the
      // first time something else refuses an action. The two causes below are
      // the real ones for Unraid's `Boolean!` mutations — a state that makes
      // the action meaningless, or an API key without the action's permission
      // (`UPDATE_ANY`/`VMS` for the VM actions). `NZBGetRPC`, which signs in
      // with a username and password, and `ProwlarrRepository` throw it too,
      // which is why the message says "or password".
      "It may already be in that state, or this API key or password may not have permission for that action."
    case .serviceUnavailable:
      "It may be disabled or stopped. Start it in Unraid, then try again."
    case .cancelled:
      "Tap Try Again when you're ready."
    case .graphQL, .decoding, .unknown:
      nil
    }
  }
}

extension AppError {
  /// Normalises any thrown error into an `AppError`.
  ///
  /// **Routes `URLError` through `from(transport:)`.** Without that, every
  /// transport failure in every store — unreachable server, denied local network,
  /// self-signed certificate — becomes `.unknown(String(describing:))`. That
  /// renders an `NSURLErrorDomain` string with no recovery text, which is exactly
  /// the outcome the `AppError` cases with recovery text exist to prevent.
  public static func wrapping(_ error: Error) -> AppError {
    if let appError = error as? AppError { return appError }
    if error is URLError { return from(transport: error) }
    // Swift's own cancellation, as opposed to `URLSession`'s — a `Task` cancelled
    // before its request started throws this instead of `URLError.cancelled`.
    if error is CancellationError { return .cancelled }
    return .unknown(String(describing: error))
  }

  /// Maps a transport-level failure to a case with recovery text.
  ///
  /// Lives in `TowerCore` rather than `TowerData` so `wrapping` can reach it —
  /// see that method. `URLError` is Foundation, so this needs nothing Apollo.
  public static func from(transport error: Error) -> AppError {
    guard let urlError = error as? URLError else {
      return .unknown(String(describing: error))
    }
    switch urlError.code {
    case .notConnectedToInternet:
      // No network interface at all — airplane mode, Wi-Fi off. Distinct from
      // a denied local-network prompt: sending this user to Settings ▸ Tower
      // points them at a toggle that is not their problem.
      return .offline
    case .networkConnectionLost:
      // A denied local-network prompt surfaces here. The recovery is a
      // Settings toggle, so it must not be reported as "server unreachable".
      return .localNetworkDenied
    case .cannotConnectToHost, .cannotFindHost, .timedOut, .dnsLookupFailed:
      return .serverUnreachable
    case .badURL, .unsupportedURL:
      return .invalidServerURL
    case .cancelled:
      // A cancelled request surfaces here rather than as `CancellationError`:
      // `URLSession` reports its own cancellation through `URLError`, and
      // Apollo passes that straight through. Without this case a user pressing
      // Cancel would get "The server sent something Tower couldn't read"-adjacent
      // noise from `.unknown` instead of the state they asked for.
      return .cancelled
    case .secureConnectionFailed, .serverCertificateUntrusted,
         .serverCertificateHasBadDate, .serverCertificateHasUnknownRoot,
         .serverCertificateNotYetValid, .appTransportSecurityRequiresSecureConnection:
      // A self-signed certificate is a completely normal Unraid deployment.
      // Without this case these land in `.unknown`, which has no recovery
      // text — the user gets an OS string and no idea what to do.
      return .insecureConnection
    default:
      return .unknown(urlError.localizedDescription)
    }
  }
}
