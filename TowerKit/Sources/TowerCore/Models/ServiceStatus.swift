import Foundation

/// The health of one configured service, as the hub row shows it.
///
/// Three states, not two: a rejected API key and an unreachable host need
/// different recoveries — one sends the user to the instance's credentials, the
/// other to the address or the network — and collapsing them into "offline" is
/// how a mistyped key turns into an hour of network debugging.
public enum ServiceStatus: Equatable, Sendable {
  /// The service answered and accepted the credentials. `version` is whatever
  /// the probe reported, when it reports one.
  case reachable(version: String?)
  /// The service answered and rejected the credentials.
  case unauthorized
  /// The service could not be reached, or answered in a way Tower can't read.
  case unreachable(AppError)

  public var isReachable: Bool {
    if case .reachable = self { return true }
    return false
  }

  /// Whether the hub should badge this row red.
  public var isProblem: Bool { !isReachable }

  /// One short line for the row.
  public var summary: String {
    switch self {
    case .reachable(let version):
      version.map { "Connected · v\($0)" } ?? "Connected"
    case .unauthorized:
      "Credentials rejected"
    case .unreachable:
      "Unreachable"
    }
  }

  /// The underlying failure, for the row's detail or an alert.
  public var error: AppError? {
    switch self {
    case .reachable: nil
    case .unauthorized: .unauthorized
    case .unreachable(let error): error
    }
  }
}
