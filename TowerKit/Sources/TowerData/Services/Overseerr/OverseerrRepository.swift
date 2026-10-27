import Foundation
import TowerCore

/// Everything the Overseerr screens can ask for.
public protocol OverseerrRepositoryProtocol: ServiceRepository {
  /// One page of requests. `page` is 1-based; Overseerr itself takes an offset,
  /// which the live conformance converts.
  func requests(filter: RequestFilter, page: Int) async throws -> OverseerrRequestPage
  func request(id: Int) async throws -> OverseerrRequest
  func approve(requestID: Int) async throws
  func decline(requestID: Int) async throws

  func search(term: String) async throws -> [OverseerrSearchResult]
  /// The seasons a series has, for the request sheet's picker.
  func seasons(tmdbID: Int) async throws -> [OverseerrSeason]
  @discardableResult
  func submit(_ request: SubmitRequest) async throws -> OverseerrRequest

  func issues(includeResolved: Bool) async throws -> [OverseerrIssue]
  func comment(issueID: Int, message: String) async throws
  func setIssueResolved(_ isResolved: Bool, issueID: Int) async throws
}

/// The live conformance.
public struct LiveOverseerrRepository: OverseerrRepositoryProtocol {
  public let instance: ServiceInstance
  private let client: ServiceHTTPClient

  /// Requests per page. Overseerr's own default is 10; 20 halves the round
  /// trips on a busy server without making the first page slow to arrive.
  private static let pageSize = 20

  public init(instance: ServiceInstance, sessionConfiguration: URLSessionConfiguration? = nil) {
    self.instance = instance
    self.client = ServiceHTTPClient(
      instance: instance, sessionConfiguration: sessionConfiguration)
  }

  init(instance: ServiceInstance, client: ServiceHTTPClient) {
    self.instance = instance
    self.client = client
  }

  // MARK: - Requests

  public func requests(filter: RequestFilter, page: Int) async throws -> OverseerrRequestPage {
    // Overseerr paginates by offset, not page number.
    let skip = max(0, page - 1) * Self.pageSize
    let dto: RequestPageDTO = try await client.send(
      "api/v1/request",
      query: [
        URLQueryItem(name: "take", value: String(Self.pageSize)),
        URLQueryItem(name: "skip", value: String(skip)),
        URLQueryItem(name: "filter", value: filter.rawValue),
        // Newest first, which is the order the pending queue is worked in.
        URLQueryItem(name: "sort", value: "added"),
      ],
      as: RequestPageDTO.self)

    let requests = (dto.results ?? []).map(\.domain)
    return OverseerrRequestPage(
      requests: try await titled(requests),
      // `pageInfo.page` is 0-based on some builds and absent on others; the
      // page Tower asked for is the reliable answer.
      page: page,
      pages: dto.pageInfo?.pages ?? 1,
      totalResults: dto.pageInfo?.results ?? requests.count)
  }

  public func request(id: Int) async throws -> OverseerrRequest {
    let dto: MediaRequestDTO = try await client.send(
      "api/v1/request/\(id)", as: MediaRequestDTO.self)
    return try await titled([dto.domain]).first ?? dto.domain
  }

  public func approve(requestID: Int) async throws {
    // `POST /request/{id}/{status}` — the status is a path segment, not a body.
    try await client.send("api/v1/request/\(requestID)/approve", method: .post)
  }

  public func decline(requestID: Int) async throws {
    try await client.send("api/v1/request/\(requestID)/decline", method: .post)
  }

  // MARK: - Titles
  //
  // Overseerr's `/request` response carries the media's *ids*, not its name.
  // Titles come from the media detail endpoints, one call each.

  /// Fills in the titles a request list is missing.
  ///
  /// **Concurrent and non-fatal.** A page of 20 requests would be 20
  /// extra round trips run one after another; they are issued together
  /// instead. A lookup that fails leaves that row with its fallback title
  /// rather than failing the list — a request you can still approve with the
  /// title missing beats an error screen.
  private func titled(_ requests: [OverseerrRequest]) async throws -> [OverseerrRequest] {
    let needing = requests.filter { $0.title == nil && $0.tmdbID != nil }
    guard !needing.isEmpty else { return requests }

    let resolved = await withTaskGroup(of: (Int, MediaSummary?).self) { group in
      for request in needing {
        guard let tmdbID = request.tmdbID else { continue }
        group.addTask {
          (request.id, try? await summary(mediaType: request.mediaType, tmdbID: tmdbID))
        }
      }
      var byRequestID: [Int: MediaSummary] = [:]
      for await (requestID, summary) in group {
        if let summary { byRequestID[requestID] = summary }
      }
      return byRequestID
    }

    return requests.map { request in
      guard let summary = resolved[request.id] else { return request }
      var request = request
      request.title = summary.title
      request.posterURL = request.posterURL ?? summary.posterURL
      return request
    }
  }

  private struct MediaSummary: Sendable {
    let title: String?
    let posterURL: URL?
  }

  private func summary(
    mediaType: OverseerrMediaType, tmdbID: Int
  ) async throws -> MediaSummary {
    switch mediaType {
    case .tv:
      let dto: TvDetailsDTO = try await client.send("api/v1/tv/\(tmdbID)", as: TvDetailsDTO.self)
      return MediaSummary(title: dto.name, posterURL: TMDBImage.posterURL(path: dto.posterPath))
    case .movie, .unknown:
      let dto: MovieDetailsDTO = try await client.send(
        "api/v1/movie/\(tmdbID)", as: MovieDetailsDTO.self)
      return MediaSummary(title: dto.title, posterURL: TMDBImage.posterURL(path: dto.posterPath))
    }
  }

  // MARK: - Search

  public func search(term: String) async throws -> [OverseerrSearchResult] {
    let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return [] }
    let dto: SearchPageDTO = try await client.send(
      "api/v1/search",
      query: [
        URLQueryItem(name: "query", value: trimmed),
        URLQueryItem(name: "page", value: "1"),
      ],
      as: SearchPageDTO.self)
    // `compactMap`, not `map`: `/search` mixes people in with media, and a
    // person is not something Tower can request.
    return (dto.results ?? []).compactMap(\.domain)
  }

  public func seasons(tmdbID: Int) async throws -> [OverseerrSeason] {
    let dto: TvDetailsDTO = try await client.send("api/v1/tv/\(tmdbID)", as: TvDetailsDTO.self)
    return (dto.seasons ?? [])
      .map(\.domain)
      // Specials are season 0 and sort first, which is where Sonarr puts them
      // too — and a season with no episodes is TMDB placeholder noise.
      .filter { $0.episodeCount > 0 }
      .sorted { $0.seasonNumber < $1.seasonNumber }
  }

  @discardableResult
  public func submit(_ request: SubmitRequest) async throws -> OverseerrRequest {
    let dto: MediaRequestDTO = try await client.send(
      "api/v1/request", method: .post, body: SubmitRequestBody(request),
      as: MediaRequestDTO.self)
    return dto.domain
  }

  // MARK: - Issues

  public func issues(includeResolved: Bool) async throws -> [OverseerrIssue] {
    let dto: IssuePageDTO = try await client.send(
      "api/v1/issue",
      query: [
        URLQueryItem(name: "take", value: "50"),
        URLQueryItem(name: "skip", value: "0"),
        URLQueryItem(name: "filter", value: includeResolved ? "all" : "open"),
        URLQueryItem(name: "sort", value: "added"),
      ],
      as: IssuePageDTO.self)
    return (dto.results ?? []).map(\.domain)
  }

  public func comment(issueID: Int, message: String) async throws {
    let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return }
    try await client.send(
      "api/v1/issue/\(issueID)/comment", method: .post, body: CommentBody(message: trimmed))
  }

  public func setIssueResolved(_ isResolved: Bool, issueID: Int) async throws {
    // Same path-segment shape as request approve/decline.
    try await client.send(
      "api/v1/issue/\(issueID)/\(isResolved ? "resolved" : "open")", method: .post)
  }
}
