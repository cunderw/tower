import Foundation

/// Root of the per-instance repository family.
///
/// Each service has its own protocol refining this one
/// (`RadarrRepository`, `NZBGetRepository`, …) with live and demo
/// conformances. This one holds only the instance, so the factory in
/// `AppEnvironment` — and the per-instance stores created on navigation — have
/// one type to hand around whatever the service.
public protocol ServiceRepository: Sendable {
  var instance: ServiceInstance { get }
}

/// Builds the repository for a configured instance.
///
/// Returns `nil` for a kind that has no client. Every kind has one today, but
/// the optional keeps "configured but not supported" expressible without a
/// placeholder that answers every call with an error.
public typealias ServiceRepositoryFactory = @Sendable (ServiceInstance) -> (any ServiceRepository)?
