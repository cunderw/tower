import Foundation
import TowerCore

/// Everything the Tautulli screens can ask for.
///
/// One endpoint, one mutation. Tautulli's API v2 is `GET /api/v2?cmd=<name>`
/// for every call — there are no REST paths to model, so this protocol is a
/// list of commands rather than a list of resources.
public protocol TautulliRepositoryProtocol: ServiceRepository {
  /// What is playing right now.
  func activity() async throws -> TautulliActivity

  /// Tautulli's one mutation, and the reason the screen behind it asks for a
  /// confirmation: it stops somebody else's playback.
  func terminate(sessionKey: String, message: String?) async throws

  func history(
    filter: TautulliHistoryFilter, start: Int, length: Int
  ) async throws -> TautulliHistoryPage

  func users() async throws -> [TautulliUser]
  func libraries() async throws -> [TautulliLibrary]
}

extension TautulliRepositoryProtocol {
  public func history(filter: TautulliHistoryFilter = .none) async throws -> TautulliHistoryPage {
    try await history(filter: filter, start: 0, length: 50)
  }
}

/// The live conformance.
///
/// **Two Tautulli quirks are handled here and nowhere else.**
///
/// It answers **HTTP 200 for everything** — a rejected API key, an unknown
/// command, a bad parameter — and puts the reason in the body's `result` and
/// `message`. So success is read from the envelope, not the status code, and
/// a refusal that mentions the key maps to `AppError.unauthorized` so the
/// connect screen's existing recovery text applies.
///
/// And the API key travels as a **query parameter**, because Tautulli ignores
/// the header form. `ServiceHTTPClient` injects it (`ServiceAuthStyle
/// .apiKeyQuery`), which keeps it out of anything this file logs or builds by
/// hand — the key is never interpolated into a URL here.
public struct LiveTautulliRepository: TautulliRepositoryProtocol {
  public let instance: ServiceInstance
  private let client: ServiceHTTPClient

  private static let path = "api/v2"

  public init(instance: ServiceInstance, sessionConfiguration: URLSessionConfiguration? = nil) {
    self.instance = instance
    self.client = ServiceHTTPClient(
      instance: instance, sessionConfiguration: sessionConfiguration)
  }

  init(instance: ServiceInstance, client: ServiceHTTPClient) {
    self.instance = instance
    self.client = client
  }

  // MARK: - Activity

  public func activity() async throws -> TautulliActivity {
    let response: TautulliResponseDTO<TautulliActivityDTO> = try await call(
      "get_activity", as: TautulliActivityDTO.self)
    // An idle server sends `data` with zeroed counters; a `null` here means
    // Tautulli answered without one, which is still "nothing playing".
    return try Self.payload(response).map(\.domain) ?? .empty
  }

  public func terminate(sessionKey: String, message: String?) async throws {
    var query = [
      URLQueryItem(name: "cmd", value: "terminate_session"),
      URLQueryItem(name: "session_key", value: sessionKey),
    ]
    if let message, !message.isEmpty {
      // Shown on the player that gets stopped, so somebody staring at a frozen
      // screen knows why.
      query.append(URLQueryItem(name: "message", value: message))
    }
    let response = try await client.send(
      Self.path, query: query, as: TautulliEmptyResponseDTO.self)
    try Self.check(result: response.response.result, message: response.response.message)
  }

  // MARK: - History

  public func history(
    filter: TautulliHistoryFilter, start: Int, length: Int
  ) async throws -> TautulliHistoryPage {
    var query = [
      URLQueryItem(name: "start", value: String(start)),
      URLQueryItem(name: "length", value: String(length)),
      // Newest first, which is the only ordering the screen offers.
      URLQueryItem(name: "order_column", value: "date"),
      URLQueryItem(name: "order_dir", value: "desc"),
    ]
    if let userID = filter.userID {
      query.append(URLQueryItem(name: "user_id", value: String(userID)))
    }
    if let mediaType = filter.mediaType, !mediaType.isEmpty {
      query.append(URLQueryItem(name: "media_type", value: mediaType))
    }
    if let search = filter.search?.trimmingCharacters(in: .whitespacesAndNewlines),
      !search.isEmpty
    {
      // Tautulli filters in SQL. Filtering a fetched page here instead would
      // search only the fifty rows already on screen and look broken.
      query.append(URLQueryItem(name: "search", value: search))
    }

    let response: TautulliResponseDTO<TautulliTableDTO<TautulliHistoryRowDTO>> = try await call(
      "get_history", query: query, as: TautulliTableDTO<TautulliHistoryRowDTO>.self)
    let table = try Self.payload(response)
    return TautulliHistoryPage(
      records: (table?.data ?? []).map(\.domain),
      filteredCount: table?.recordsFiltered.int ?? (table?.data ?? []).count,
      totalCount: table?.recordsTotal.int ?? (table?.data ?? []).count)
  }

  // MARK: - Users and libraries

  public func users() async throws -> [TautulliUser] {
    // `get_users_table` rather than `get_users`: only the table form carries
    // the per-user play counts and last-seen times the screen is for.
    let response: TautulliResponseDTO<TautulliTableDTO<TautulliUserRowDTO>> = try await call(
      "get_users_table",
      query: [
        URLQueryItem(name: "order_column", value: "last_seen"),
        URLQueryItem(name: "order_dir", value: "desc"),
        URLQueryItem(name: "length", value: "200"),
      ],
      as: TautulliTableDTO<TautulliUserRowDTO>.self)
    return (try Self.payload(response)?.data ?? []).map(\.domain)
  }

  public func libraries() async throws -> [TautulliLibrary] {
    let response: TautulliResponseDTO<TautulliTableDTO<TautulliLibraryRowDTO>> = try await call(
      "get_libraries_table",
      query: [
        URLQueryItem(name: "order_column", value: "section_name"),
        URLQueryItem(name: "order_dir", value: "asc"),
        URLQueryItem(name: "length", value: "200"),
      ],
      as: TautulliTableDTO<TautulliLibraryRowDTO>.self)
    return (try Self.payload(response)?.data ?? []).map(\.domain)
  }

  // MARK: - The one call shape

  private func call<Payload: Decodable & Sendable>(
    _ command: String, query: [URLQueryItem] = [], as type: Payload.Type
  ) async throws -> TautulliResponseDTO<Payload> {
    try await client.send(
      Self.path,
      query: [URLQueryItem(name: "cmd", value: command)] + query,
      as: TautulliResponseDTO<Payload>.self)
  }

  private static func payload<Payload: Decodable & Sendable>(
    _ response: TautulliResponseDTO<Payload>
  ) throws -> Payload? {
    try check(result: response.response.result, message: response.response.message)
    return response.response.data
  }

  /// Tautulli's success signal, which is the body rather than the status code.
  private static func check(result: String?, message: String?) throws {
    guard (result ?? "").lowercased() != "success" else { return }
    let message = message?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    // "Invalid apikey" is its wording for a rejected key. Mapping that onto
    // `unauthorized` is what makes the connect screen offer to fix the key
    // rather than showing Tautulli's raw sentence.
    if message.replacingOccurrences(of: " ", with: "").lowercased().contains("apikey") {
      throw AppError.unauthorized
    }
    throw AppError.unknown(message.isEmpty ? "Tautulli refused the request." : message)
  }
}
