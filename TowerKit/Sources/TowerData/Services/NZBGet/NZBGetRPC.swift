import Foundation
import TowerCore

/// NZBGet's JSON-RPC envelope.
///
/// **This type is the whole reason nothing above `TowerData` knows the
/// transport.** NZBGet is the only one of the eight services that isn't REST,
/// and the difference is entirely contained here: `NZBGetClient` exposes
/// `call(_:params:)`, the repository calls it, and everything above the
/// repository sees plain `TowerCore` values exactly as it does for Radarr.
///
/// The dialect is JSON-RPC 1.1-ish rather than strict 2.0 — NZBGet sends
/// `"version": "1.1"`, positional params only, and reports failure with an
/// `error` object *alongside* HTTP 200. A client that trusted the status code
/// would read every failure as a success with a missing result.
struct JSONRPCRequest: Encodable, Sendable {
  let method: String
  /// Positional, always. NZBGet does not accept named parameters, and sending
  /// an object rather than an array fails with a parse error rather than
  /// anything that names the real problem.
  let params: [JSONRPCValue]
  let id = 1
  let version = "1.1"

  enum CodingKeys: String, CodingKey {
    case method, params, id, version
  }
}

/// The handful of scalar types NZBGet's methods take as parameters.
///
/// A small closed enum rather than `Any`: the params array is heterogeneous
/// (`editqueue` takes a string, an int, a string, and an array of ints), and
/// this is what lets it stay `Encodable` and `Sendable` without a wrapper at
/// every call site.
enum JSONRPCValue: Encodable, Sendable, Equatable {
  case string(String)
  case int(Int)
  case bool(Bool)
  case intArray([Int])

  func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    switch self {
    case .string(let value): try container.encode(value)
    case .int(let value): try container.encode(value)
    case .bool(let value): try container.encode(value)
    case .intArray(let value): try container.encode(value)
    }
  }
}

/// A response envelope. `result` is absent when `error` is present.
struct JSONRPCResponse<Result: Decodable & Sendable>: Decodable, Sendable {
  let result: Result?
  let error: JSONRPCError?
}

struct JSONRPCError: Decodable, Sendable, Equatable {
  let code: Int?
  let message: String?
  let name: String?
}

/// NZBGet's client: one `POST /jsonrpc`, an envelope, and basic auth.
///
/// Basic auth comes free from `ServiceHTTPClient`'s `.basic` style, which is
/// already the per-kind default for `.nzbget` — so the credentials never
/// appear in a URL or a body here.
struct NZBGetClient: Sendable {
  let instance: ServiceInstance
  private let http: ServiceHTTPClient

  init(instance: ServiceInstance, sessionConfiguration: URLSessionConfiguration? = nil) {
    self.instance = instance
    self.http = ServiceHTTPClient(
      instance: instance, sessionConfiguration: sessionConfiguration)
  }

  /// Calls a method and decodes its result.
  ///
  /// A `200` carrying an `error` object is a failure, and is mapped onto
  /// `AppError` here so no caller has to know the envelope exists.
  func call<Result: Decodable & Sendable>(
    _ method: String,
    params: [JSONRPCValue] = [],
    as type: Result.Type = Result.self
  ) async throws -> Result {
    let envelope: JSONRPCResponse<Result> = try await http.send(
      "jsonrpc",
      method: .post,
      body: JSONRPCRequest(method: method, params: params),
      as: JSONRPCResponse<Result>.self)

    if let error = envelope.error {
      throw Self.appError(for: error, instance: instance)
    }
    guard let result = envelope.result else {
      // A response with neither a result nor an error is a shape Tower can't
      // act on; saying so beats returning a silently empty list.
      throw AppError.decoding("\(instance.name) answered \(method) with no result.")
    }
    return result
  }

  /// The mutation shape: every NZBGet command answers with a bare `true` or
  /// `false`, and `false` means "refused", not "transport failed".
  func command(_ method: String, params: [JSONRPCValue] = []) async throws {
    let accepted: Bool = try await call(method, params: params, as: Bool.self)
    guard accepted else {
      throw AppError.actionRefused("\(instance.name) refused that request.")
    }
  }

  /// NZBGet reports a rejected password as an RPC error rather than a 401 on
  /// some builds, so the credential case is recognised from the envelope too —
  /// otherwise a wrong password reads as a generic server error and sends the
  /// user to the wrong screen.
  private static func appError(for error: JSONRPCError, instance: ServiceInstance) -> AppError {
    let message = error.message ?? error.name ?? "unknown error"
    let lowered = message.lowercased()
    if lowered.contains("unauthorized") || lowered.contains("access denied")
      || lowered.contains("not authorized")
    {
      return .unauthorized
    }
    return .unknown("\(instance.name) rejected the request: \(message)")
  }
}

/// NZBGet splits every byte count into two 32-bit halves — `…SizeLo` and
/// `…SizeHi` — plus a lossy `…SizeMB`. Recombining is the accurate reading, and
/// the MB field is the fallback for the few places older builds omit the pair.
///
/// Getting this wrong is invisible below 4 GB and wrong by exactly 4 GB above
/// it, which is the size range this app's users actually live in.
enum NZBSize {
  static func bytes(lo: Int64?, hi: Int64?, megabytes: Int64?) -> Int64 {
    if let lo, let hi { return hi * 4_294_967_296 + lo }
    if let lo { return lo }
    return (megabytes ?? 0) * 1_048_576
  }
}
