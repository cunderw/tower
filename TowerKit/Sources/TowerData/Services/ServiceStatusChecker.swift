import Foundation
import TowerCore

/// The hub's health ping for configured instances.
public protocol ServiceStatusChecking: Sendable {
  func status(for instance: ServiceInstance) async -> ServiceStatus
  /// Checks every instance concurrently. One dead service must not hold up the
  /// rest of the hub, so this returns only when all of them have answered or
  /// timed out — never in sequence.
  func statuses(for instances: [ServiceInstance]) async -> [UUID: ServiceStatus]
}

extension ServiceStatusChecking {
  public func statuses(for instances: [ServiceInstance]) async -> [UUID: ServiceStatus] {
    await withTaskGroup(of: (UUID, ServiceStatus).self) { group in
      for instance in instances {
        group.addTask { (instance.id, await status(for: instance)) }
      }
      var result: [UUID: ServiceStatus] = [:]
      for await (id, status) in group {
        result[id] = status
      }
      return result
    }
  }
}

/// The cheapest call each service offers that still proves the credentials are
/// good: the *arrs' `system/status`, Overseerr's `auth/me`, Tautulli's `status`
/// command, and NZBGet's `version`.
///
/// Deliberately one request per instance. The hub fans this out across every
/// configured service on appear, and a two-call probe would double that for a
/// version string nothing depends on.
public struct LiveServiceStatusChecker: ServiceStatusChecking {
  private let makeClient: @Sendable (ServiceInstance) -> ServiceHTTPClient

  /// - Parameter timeout: 10s rather than the client's usual 30. This is a
  ///   glanceable badge on a list — a service that hasn't answered in ten
  ///   seconds is a problem the user wants told about now, and the row can be
  ///   refreshed.
  public init(
    sessionConfiguration: URLSessionConfiguration? = nil,
    timeout: TimeInterval = 10
  ) {
    self.init { instance in
      ServiceHTTPClient(
        instance: instance,
        sessionConfiguration: sessionConfiguration,
        timeout: timeout
      )
    }
  }

  /// Seam for tests.
  init(makeClient: @escaping @Sendable (ServiceInstance) -> ServiceHTTPClient) {
    self.makeClient = makeClient
  }

  public func status(for instance: ServiceInstance) async -> ServiceStatus {
    let client = makeClient(instance)
    do {
      return try await probe(instance.kind, client)
    } catch AppError.unauthorized {
      return .unauthorized
    } catch {
      return .unreachable(AppError.wrapping(error))
    }
  }

  private func probe(_ kind: ServiceKind, _ client: ServiceHTTPClient) async throws -> ServiceStatus {
    switch kind {
    case .radarr, .sonarr:
      // The *arr v3 surface.
      return .reachable(version: try await client.send(
        "api/v3/system/status", as: ArrStatusProbeDTO.self).version)
    case .lidarr, .prowlarr:
      // **Same shape, different version.** Lidarr and Prowlarr answer the
      // *arr status resource at v1. Probed at v3 with the group above, a Lidarr
      // is badged unreachable on the hub while every one of its screens loads,
      // because `LiveLidarrRepository` uses `api/v1`. A badge that is
      // wrong in the pessimistic direction is worse than no badge: it sends
      // someone to fix a service that is working.
      return .reachable(version: try await client.send(
        "api/v1/system/status", as: ArrStatusProbeDTO.self).version)
    case .bazarr:
      // Bazarr wraps everything in `data` and names its version field itself.
      return .reachable(version: try await client.send(
        "api/system/status", as: BazarrSystemStatus.self).data.bazarrVersion)
    case .overseerr:
      // `api/v1/status` answers without a key at all, so it cannot tell a good
      // key from a bad one. `auth/me` is the cheapest call that 401s.
      _ = try await client.send("api/v1/auth/me", as: OverseerrUser.self)
      return .reachable(version: nil)
    case .tautulli:
      return try await tautulliStatus(client)
    case .nzbget:
      return .reachable(version: try await client.send(
        "jsonrpc/version", as: NZBGetVersion.self).result)
    }
  }

  /// Tautulli answers **HTTP 200 for a bad API key**, with the failure only in
  /// the body — so a status check that trusted the status code would report a
  /// wrong key as healthy.
  private func tautulliStatus(_ client: ServiceHTTPClient) async throws -> ServiceStatus {
    let response = try await client.send(
      "api/v2", query: [URLQueryItem(name: "cmd", value: "status")],
      as: TautulliEnvelope.self
    ).response
    guard response.result == "success" else {
      let message = response.message ?? ""
      // Tautulli's wording for a rejected key is "Invalid apikey"; anything
      // else it refuses is a service-side problem, not a credential one.
      if message.replacingOccurrences(of: " ", with: "").lowercased().contains("apikey") {
        return .unauthorized
      }
      throw AppError.unknown(message.isEmpty ? "Tautulli refused the request." : message)
    }
    return .reachable(version: nil)
  }

}

#if DEBUG
/// Answers every instance with the same status, without a network call. A test
/// double, so it is compiled into Debug builds only. Demo mode does not use it;
/// it has its own `DemoServiceStatusChecker` in the app target.
public struct StaticServiceStatusChecker: ServiceStatusChecking {
  private let fixed: ServiceStatus

  public init(_ fixed: ServiceStatus = .reachable(version: nil)) {
    self.fixed = fixed
  }

  public func status(for instance: ServiceInstance) async -> ServiceStatus { fixed }
}
#endif

// MARK: - Probe DTOs

// Internal to `TowerData`, like every other DTO — these mirror each service's
// JSON and never leave this layer.

/// Just the version, for the health ping. Named for the probe rather than the
/// endpoint because `ArrSystemStatus` is a `TowerCore` domain type — an
/// internal DTO of the same name shadows it inside this module and produces
/// errors nowhere near the collision.
struct ArrStatusProbeDTO: Decodable, Sendable {
  let version: String?
}

struct BazarrSystemStatus: Decodable, Sendable {
  struct Payload: Decodable, Sendable {
    let bazarrVersion: String?

    private enum CodingKeys: String, CodingKey {
      case bazarrVersion = "bazarr_version"
    }
  }
  let data: Payload
}

struct OverseerrUser: Decodable, Sendable {
  let id: Int
}

struct NZBGetVersion: Decodable, Sendable {
  let result: String?
}

struct TautulliEnvelope: Decodable, Sendable {
  struct Response: Decodable, Sendable {
    let result: String
    let message: String?
  }
  let response: Response
}
