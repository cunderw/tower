import Apollo
import Foundation
import TowerCore

/// Maps HTTP, transport, and GraphQL failures onto the app's `AppError`
/// taxonomy so the UI only ever has to reason about one error type.
extension AppError {
  public static func from(httpStatusCode code: Int) -> AppError {
    switch code {
    case 401, 403: .unauthorized
    case 500...599: .serverUnreachable
    default: .unknown("HTTP \(code)")
    }
  }

  // `from(transport:)` lives in `TowerCore`'s `AppError.swift`, not here, so
  // that `AppError.wrapping` can reach it. Without it every `URLError` that
  // reaches `wrapping` becomes `.unknown`, which renders an `NSURLErrorDomain`
  // string with no recovery text. `URLError` is Foundation, so `TowerCore` needs
  // nothing extra to hold it. `from(graphQLErrors:)` stays here, since it needs Apollo.

  public static func from(graphQLErrorMessages messages: [String]) -> AppError {
    .graphQL(messages)
  }

  /// Maps Apollo's `GraphQLError` values, inspecting `extensions["code"]`
  /// rather than just `message`.
  ///
  /// Unraid never sends HTTP 401/403 for a bad API key (see
  /// `from(httpStatusCode:)` above); it answers with HTTP 200 and a GraphQL
  /// `errors` entry whose `extensions.code` is `"UNAUTHENTICATED"` (and,
  /// presumably, `"FORBIDDEN"` for a key that's valid but lacks permission).
  /// Without this check those errors fall through to `.graphQL`, whose
  /// `recoverySuggestion` is `nil` — the user sees a raw server string
  /// ("API key validation failed") with no fix, on the app's first screen,
  /// for its single most likely error.
  ///
  /// Deliberately **not** public: `GraphQLError` is an Apollo type, and
  /// TowerData's boundary rule is that Apollo types never appear in a public
  /// signature (see the non-public `DashboardSnapshot.init(from:)` in
  /// `SystemRepository.swift`, for the same reason).
  static func from(graphQLErrors errors: [GraphQLError]) -> AppError {
    // A mixed batch (one auth error alongside an unrelated GraphQL error) is
    // still, at root, an authentication problem — the user needs to fix the
    // API key before anything else the server said matters. So any
    // UNAUTHENTICATED/FORBIDDEN entry anywhere in the batch wins over
    // whatever else is in `errors`, rather than averaging/concatenating.
    if errors.contains(where: \.isAuthFailure) {
      return .unauthorized
    }
    return .graphQL(errors.compactMap(\.message))
  }
}

extension GraphQLError {
  var isAuthFailure: Bool {
    guard let code = extensions?["code"] as? String else { return false }
    return code == "UNAUTHENTICATED" || code == "FORBIDDEN"
  }
}

extension Array where Element == GraphQLError {
  /// The errors left after dropping the ones under `vms.domains`, which the
  /// data already expresses as nulls: the whole list when the resolver
  /// throws (the VM manager disabled case), or a nullable field of one
  /// domain (`vms.domains.N.name`), which leaves `domains` non-null.
  ///
  /// With the VM manager disabled, Unraid's `domains` resolver throws
  /// ("Failed to retrieve VM domains: …"). `Vms.domains` is nullable, so the
  /// server nulls only that field and returns the rest of `data` intact. A
  /// null `domains` already maps to "VMs unavailable", so that error says
  /// nothing the data does not — treating it as fatal blanked the whole
  /// dashboard on every VM-less server (issue #8).
  ///
  /// Auth errors are kept even under `vms`: a key that cannot read VMs is
  /// still a key problem, and `from(graphQLErrors:)` must see it.
  func excludingVMDomainFailures() -> [GraphQLError] {
    filter { error in
      guard let path = error.path, path.starts(with: [.field("vms"), .field("domains")]) else {
        return true
      }
      return error.isAuthFailure
    }
  }
}
