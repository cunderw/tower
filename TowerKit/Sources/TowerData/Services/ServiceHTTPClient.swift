import Foundation
import TowerCore

public enum HTTPMethod: String, Sendable {
  case get = "GET"
  case post = "POST"
  case put = "PUT"
  /// Bazarr's "find one yourself" download is a PATCH on the media's own
  /// subtitles resource; nothing else needs the verb.
  case patch = "PATCH"
  case delete = "DELETE"
}

/// How a service expects credentials to arrive.
///
/// Derived from `ServiceKind`, and kept in `TowerData` rather than on the kind
/// itself: header names are a transport detail, and `TowerCore` is the layer
/// that must stay ignorant of them.
public enum ServiceAuthStyle: Equatable, Sendable {
  /// `X-Api-Key: <key>` — the *arrs, Bazarr and Overseerr.
  case apiKeyHeader(field: String)
  /// `?apikey=<key>` — Tautulli, which ignores the header form.
  case apiKeyQuery(name: String)
  /// `Authorization: Basic …` — NZBGet.
  case basic

  init(kind: ServiceKind) {
    switch kind {
    case .radarr, .sonarr, .lidarr, .prowlarr, .bazarr, .overseerr:
      self = .apiKeyHeader(field: "X-Api-Key")
    case .tautulli:
      self = .apiKeyQuery(name: "apikey")
    case .nzbget:
      self = .basic
    }
  }
}

/// The one place the REST services' transport invariants live: URL joining, auth
/// injection, custom headers, timeouts, JSON decoding, and the mapping from
/// transport and status failures onto `AppError`.
///
/// **Nothing below this type escapes it.** No `URLError`, no `DecodingError`, no
/// `HTTPURLResponse` — a repository, store, or view only ever sees `AppError`,
/// so the Unraid tabs' error UX (including the local-network-permission
/// recovery text) applies to all eight services without any of them knowing
/// about it.
public struct ServiceHTTPClient: Sendable {
  public let instance: ServiceInstance
  private let session: URLSession
  private let authStyle: ServiceAuthStyle

  /// - Parameters:
  ///   - timeout: 30s rather than `URLSession`'s 60s default. The hub fans these
  ///     out concurrently for every configured instance, and a service
  ///     that is down should report it inside a pull-to-refresh, not a minute
  ///     later.
  public init(
    instance: ServiceInstance,
    sessionConfiguration: URLSessionConfiguration? = nil,
    timeout: TimeInterval = 30
  ) {
    self.instance = instance
    self.authStyle = ServiceAuthStyle(kind: instance.kind)
    let configuration = sessionConfiguration ?? .towerService
    configuration.timeoutIntervalForRequest = timeout
    self.session = URLSession(configuration: configuration)
  }

  // MARK: - Sending

  /// Sends a request and decodes its body.
  @discardableResult
  public func send<Response: Decodable & Sendable>(
    _ path: String,
    method: HTTPMethod = .get,
    query: [URLQueryItem] = [],
    body: (any Encodable & Sendable)? = nil,
    as type: Response.Type = Response.self
  ) async throws -> Response {
    let data = try await data(path, method: method, query: query, body: body)
    do {
      return try Self.decoder.decode(Response.self, from: data)
    } catch {
      throw AppError.decoding(Self.decodingDetail(for: error))
    }
  }

  /// Sends a request whose response body is ignored — a 204 from an *arr
  /// delete, say. Decoding is not attempted, so an empty body is not an error.
  public func send(
    _ path: String,
    method: HTTPMethod = .get,
    query: [URLQueryItem] = [],
    body: (any Encodable & Sendable)? = nil
  ) async throws {
    _ = try await data(path, method: method, query: query, body: body)
  }

  /// The raw bytes of a response, with a JSON-encoded body when there is one.
  private func data(
    _ path: String,
    method: HTTPMethod = .get,
    query: [URLQueryItem] = [],
    body: (any Encodable & Sendable)? = nil
  ) async throws -> Data {
    var encoded: Data?
    if let body {
      do {
        encoded = try Self.encoder.encode(body)
      } catch {
        // A body Tower itself built and cannot encode is a programming error,
        // not something the user can act on; it must still arrive as AppError.
        throw AppError.unknown("Tower couldn't build that request. \(error)")
      }
    }
    return try await data(
      path, method: method, query: query, rawBody: encoded,
      contentType: encoded == nil ? nil : "application/json")
  }

  private func data(
    _ path: String,
    method: HTTPMethod,
    query: [URLQueryItem],
    rawBody: Data?,
    contentType: String?
  ) async throws -> Data {
    let (status, body) = try await perform(
      path, method: method, query: query, rawBody: rawBody, contentType: contentType)
    guard (200..<300).contains(status) else { throw mappedFailure(status: status, body: body) }
    return body
  }

  /// The request, with no status interpretation at all.
  private func perform(
    _ path: String,
    method: HTTPMethod,
    query: [URLQueryItem],
    rawBody: Data?,
    contentType: String?
  ) async throws -> (status: Int, body: Data) {
    let request = try makeRequest(
      path, method: method, query: query, rawBody: rawBody, contentType: contentType)

    let data: Data
    let response: URLResponse
    do {
      (data, response) = try await session.data(for: request)
    } catch {
      // `from(transport:)` is the Unraid tabs' mapping. Reusing it is what makes
      // the offline / local-network-denied / self-signed cases behave the same
      // here as on those tabs.
      throw AppError.wrapping(error)
    }

    guard let http = response as? HTTPURLResponse else {
      throw AppError.unknown("\(instance.name) sent a response Tower couldn't read.")
    }
    return (http.statusCode, data)
  }

  // MARK: - Request building

  private func makeRequest(
    _ path: String,
    method: HTTPMethod,
    query: [URLQueryItem],
    rawBody: Data?,
    contentType: String?
  ) throws -> URLRequest {
    var query = query
    var request = URLRequest(url: try url(path: path, query: &query))

    request.httpMethod = method.rawValue
    request.httpBody = rawBody
    if let contentType {
      request.setValue(contentType, forHTTPHeaderField: "Content-Type")
    }
    request.setValue("application/json", forHTTPHeaderField: "Accept")

    switch authStyle {
    case .apiKeyHeader(let field):
      request.setValue(try apiKey(), forHTTPHeaderField: field)
    case .basic:
      let (username, password) = try usernamePassword()
      // **No credentials means no header.** NZBGet with no
      // `ControlUsername`/`ControlPassword` serves unauthenticated, and an
      // `Authorization: Basic Og==` — the base64 of a bare colon — is a
      // malformed credential assertion rather than the absence of one. Servers
      // and proxies are entitled to reject it, and none of them owe us the
      // courtesy of ignoring it.
      if !username.isEmpty || !password.isEmpty {
        let encoded = Data("\(username):\(password)".utf8).base64EncodedString()
        request.setValue("Basic \(encoded)", forHTTPHeaderField: "Authorization")
      }
    case .apiKeyQuery:
      break  // handled in `url(path:query:)`
    }

    // Applied last, so an explicit header wins over the per-kind default: custom
    // headers exist for deployments Tower can't anticipate, and a user who sets
    // one is more likely to be right about their proxy than we are.
    for (field, value) in instance.customHeaders {
      request.setValue(value, forHTTPHeaderField: field)
    }
    return request
  }

  private func url(path: String, query: inout [URLQueryItem]) throws -> URL {
    if case .apiKeyQuery(let name) = authStyle {
      query.append(URLQueryItem(name: name, value: try apiKey()))
    }
    // `appending(path:)` collapses the trailing-slash / leading-slash cases and
    // preserves any base path the user's reverse proxy adds.
    let joined = instance.baseURL.appending(path: path)
    guard var components = URLComponents(url: joined, resolvingAgainstBaseURL: false) else {
      throw AppError.invalidServerURL
    }
    if !query.isEmpty {
      components.queryItems = (components.queryItems ?? []) + query
      // Foundation encodes a space in a query value as `+` here; services vary
      // in whether they decode that, and every one of them accepts %20.
      components.percentEncodedQuery = components.percentEncodedQuery?
        .replacingOccurrences(of: "+", with: "%20")
    }
    guard let url = components.url else { throw AppError.invalidServerURL }
    return url
  }

  private func apiKey() throws -> String {
    guard case .apiKey(let key) = instance.credentials else {
      // The add-service flow picks fields by kind, so this is a record that was
      // migrated or hand-edited. Reporting it as a credential problem points at
      // the one screen that can fix it.
      throw AppError.unauthorized
    }
    return key
  }

  private func usernamePassword() throws -> (String, String) {
    guard case .usernamePassword(let username, let password) = instance.credentials else {
      throw AppError.unauthorized
    }
    return (username, password)
  }

  // MARK: - Failure mapping

  private func mappedFailure(status: Int, body: Data) -> AppError {
    switch status {
    case 401, 403:
      return .unauthorized
    case 404:
      // Almost always a wrong address or a missing reverse-proxy base path —
      // the recovery a user can act on, and one `.unauthorized` would send them
      // hunting through the wrong screen for.
      return .unknown(
        "\(instance.name) returned HTTP 404. Check the address, including any base path.")
    default:
      let detail = Self.serviceMessage(in: body).map { ": \($0)" } ?? "."
      return .unknown("\(instance.name) returned HTTP \(status)\(detail)")
    }
  }

  /// Pulls the human-readable message out of an error body. The *arrs answer
  /// with `message`, Overseerr with `error`; anything else is
  /// left to the status code alone rather than rendering a JSON blob at a user.
  private static func serviceMessage(in body: Data) -> String? {
    guard let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else {
      return nil
    }
    for key in ["message", "error", "errorMessage"] {
      if let message = object[key] as? String, !message.isEmpty { return message }
    }
    return nil
  }

  /// A `DecodingError` describes a wire format at a developer; this turns it
  /// into the one fact worth putting in front of a user, and keeps the field
  /// path for the log.
  private static func decodingDetail(for error: Error) -> String {
    guard let decodingError = error as? DecodingError else { return String(describing: error) }
    switch decodingError {
    case .keyNotFound(let key, _):
      return "Missing field '\(key.stringValue)'."
    case .typeMismatch(_, let context), .valueNotFound(_, let context):
      let path = context.codingPath.map(\.stringValue).joined(separator: ".")
      return path.isEmpty ? "Unexpected response shape." : "Unexpected value for '\(path)'."
    case .dataCorrupted:
      return "The response wasn't valid JSON."
    @unknown default:
      return "Unexpected response shape."
    }
  }

  private static let decoder: JSONDecoder = {
    let decoder = JSONDecoder()
    // The *arrs and Overseerr emit ISO 8601; the few endpoints that don't, such
    // as Tautulli's Unix seconds, decode their dates in the DTO instead.
    decoder.dateDecodingStrategy = .iso8601
    return decoder
  }()

  private static let encoder: JSONEncoder = {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    return encoder
  }()
}

extension URLSessionConfiguration {
  /// The configuration every REST service client uses.
  ///
  /// `.ephemeral`, so any cookie jar is per-session and in memory, and nothing
  /// is shared with the rest of the process or written to disk.
  public static var towerService: URLSessionConfiguration {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.urlCache = nil
    configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
    configuration.urlCredentialStorage = nil
    return configuration
  }
}
