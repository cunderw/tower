import Foundation
import TowerCore
import TowerData

/// Demo mode's Overseerr.
///
/// Mutations are real, in memory, on the same rule as every other demo
/// repository: App Review walks this path, and a demo where Approve does
/// nothing is a demo that shows the app not working.
private enum DemoOverseerrLatency {
  static let read = Duration.milliseconds(450)
  static let write = Duration.milliseconds(700)

  static func read() async { try? await Task.sleep(for: read) }
  static func write() async { try? await Task.sleep(for: write) }
}

@MainActor
final class DemoOverseerrServer {
  private(set) var requests: [OverseerrRequest] = DemoOverseerrFixtures.requests()
  private(set) var issues: [OverseerrIssue] = DemoOverseerrFixtures.issues()
  private var nextRequestID = 600
  private var nextCommentID = 900

  func setStatus(_ status: RequestStatus, id: Int) {
    requests = requests.map { request in
      guard request.id == id else { return request }
      return request.settingStatus(
        status,
        // Approving hands it to the *arr, which starts fetching — so the media
        // status moves too, exactly as it would on a real server. A demo where
        // only the badge changed would teach the wrong thing about the screen.
        media: status == .approved ? .processing : request.mediaStatus)
    }
  }

  func add(_ request: SubmitRequest, title: String, posterURL: URL?) -> OverseerrRequest {
    let created = OverseerrRequest(
      id: nextRequestID, status: .pending, mediaType: request.mediaType,
      mediaID: request.mediaID, tmdbID: request.mediaID, tvdbID: nil, mediaStatus: .pending,
      requestedBy: "You", requestedByAvatarURL: nil, createdAt: Date(), updatedAt: Date(),
      is4K: request.is4K, seasons: request.seasons, title: title, posterURL: posterURL)
    nextRequestID += 1
    requests.insert(created, at: 0)
    return created
  }

  func addComment(_ message: String, issueID: Int) {
    let comment = OverseerrComment(
      id: nextCommentID, message: message,
      // The *server* resolves the author, which is what the real API does and
      // what the issues store's re-read exists to pick up.
      author: "You", createdAt: Date())
    nextCommentID += 1
    issues = issues.map {
      $0.id == issueID ? $0.addingComment(comment) : $0
    }
  }

  func setIssueStatus(_ status: IssueStatus, id: Int) {
    issues = issues.map { $0.id == id ? $0.settingStatus(status) : $0 }
  }
}

struct DemoOverseerrRepository: OverseerrRepositoryProtocol {
  let instance: ServiceInstance
  let server: DemoOverseerrServer

  /// Matches the live repository's page size, so the demo pages the same way.
  private static let pageSize = 20

  func requests(filter: RequestFilter, page: Int) async throws -> OverseerrRequestPage {
    await DemoOverseerrLatency.read()
    let all = await server.requests.filter { filter.matches($0) }
    let start = max(0, page - 1) * Self.pageSize
    let slice = start < all.count
      ? Array(all[start..<min(start + Self.pageSize, all.count)])
      : []
    return OverseerrRequestPage(
      requests: slice, page: page,
      pages: max(1, (all.count + Self.pageSize - 1) / Self.pageSize),
      totalResults: all.count)
  }

  func request(id: Int) async throws -> OverseerrRequest {
    await DemoOverseerrLatency.read()
    guard let match = await server.requests.first(where: { $0.id == id }) else {
      throw AppError.unknown("That request is no longer in \(instance.name).")
    }
    return match
  }

  func approve(requestID: Int) async throws {
    await DemoOverseerrLatency.write()
    await server.setStatus(.approved, id: requestID)
  }

  func decline(requestID: Int) async throws {
    await DemoOverseerrLatency.write()
    await server.setStatus(.declined, id: requestID)
  }

  func search(term: String) async throws -> [OverseerrSearchResult] {
    await DemoOverseerrLatency.read()
    return DemoOverseerrFixtures.searchResults(
      matching: term, existing: await server.requests)
  }

  func seasons(tmdbID: Int) async throws -> [OverseerrSeason] {
    await DemoOverseerrLatency.read()
    return DemoOverseerrFixtures.seasons
  }

  @discardableResult
  func submit(_ request: SubmitRequest) async throws -> OverseerrRequest {
    await DemoOverseerrLatency.write()
    let candidate = DemoOverseerrFixtures.searchResults(matching: "", existing: [])
      .first { $0.id == request.mediaID }
    return await server.add(
      request, title: candidate?.title ?? "Requested media", posterURL: candidate?.posterURL)
  }

  func issues(includeResolved: Bool) async throws -> [OverseerrIssue] {
    await DemoOverseerrLatency.read()
    let all = await server.issues
    return includeResolved ? all : all.filter { $0.status != .resolved }
  }

  func comment(issueID: Int, message: String) async throws {
    await DemoOverseerrLatency.write()
    await server.addComment(message, issueID: issueID)
  }

  func setIssueResolved(_ isResolved: Bool, issueID: Int) async throws {
    await DemoOverseerrLatency.write()
    await server.setIssueStatus(isResolved ? .resolved : .open, id: issueID)
  }
}

extension RequestFilter {
  /// The demo's own reading of each filter, matching what Overseerr returns.
  fileprivate func matches(_ request: OverseerrRequest) -> Bool {
    switch self {
    case .all: true
    case .pending: request.status == .pending
    case .approved: request.status == .approved
    case .declined: request.status == .declined
    case .processing: request.mediaStatus == .processing
    case .available: request.mediaStatus == .available
    case .failed: request.status == .failed
    }
  }
}

extension OverseerrRequest {
  fileprivate func settingStatus(
    _ status: RequestStatus, media: MediaAvailability
  ) -> OverseerrRequest {
    OverseerrRequest(
      id: id, status: status, mediaType: mediaType, mediaID: mediaID, tmdbID: tmdbID,
      tvdbID: tvdbID, mediaStatus: media, requestedBy: requestedBy,
      requestedByAvatarURL: requestedByAvatarURL, createdAt: createdAt, updatedAt: Date(),
      is4K: is4K, seasons: seasons, title: title, posterURL: posterURL)
  }
}

extension OverseerrIssue {
  fileprivate func settingStatus(_ status: IssueStatus) -> OverseerrIssue {
    OverseerrIssue(
      id: id, type: type, status: status, mediaType: mediaType, tmdbID: tmdbID,
      createdBy: createdBy, createdAt: createdAt, comments: comments, title: title)
  }

  fileprivate func addingComment(_ comment: OverseerrComment) -> OverseerrIssue {
    OverseerrIssue(
      id: id, type: type, status: status, mediaType: mediaType, tmdbID: tmdbID,
      createdBy: createdBy, createdAt: createdAt, comments: comments + [comment], title: title)
  }
}

// MARK: - Fixtures

/// The dataset demo mode's Overseerr presents.
///
/// A pending request to approve, approved history, and an open issue. Nothing
/// here names a real person or title.
enum DemoOverseerrFixtures {
  static func requests() -> [OverseerrRequest] {
    [
      request(
        id: 501, status: .pending, media: .pending, type: .movie, tmdb: 700_010,
        title: "Harbour Lights", by: "Priya Raman", hoursAgo: 2),
      request(
        id: 502, status: .pending, media: .pending, type: .tv, tmdb: 700_002,
        title: "Northern Lights", by: "Sam Okafor", hoursAgo: 9, seasons: [3]),
      request(
        id: 503, status: .approved, media: .processing, type: .movie, tmdb: 700_011,
        title: "Second Wind", by: "Priya Raman", hoursAgo: 26),
      request(
        id: 504, status: .approved, media: .available, type: .movie, tmdb: 700_001,
        title: "The Cartographer", by: "Jo Vance", hoursAgo: 74, is4K: true),
      request(
        id: 505, status: .declined, media: .unknown, type: .movie, tmdb: 700_012,
        title: "Quarry", by: "Sam Okafor", hoursAgo: 120),
    ]
  }

  private static func request(
    id: Int, status: RequestStatus, media: MediaAvailability, type: OverseerrMediaType,
    tmdb: Int, title: String, by: String, hoursAgo: Double, seasons: [Int] = [],
    is4K: Bool = false
  ) -> OverseerrRequest {
    OverseerrRequest(
      id: id, status: status, mediaType: type, mediaID: id, tmdbID: tmdb, tvdbID: nil,
      mediaStatus: media, requestedBy: by, requestedByAvatarURL: nil,
      createdAt: Date().addingTimeInterval(-hoursAgo * 3_600),
      updatedAt: Date().addingTimeInterval(-hoursAgo * 3_600), is4K: is4K, seasons: seasons,
      title: title, posterURL: nil)
  }

  static func issues() -> [OverseerrIssue] {
    [
      OverseerrIssue(
        id: 12, type: .audio, status: .open, mediaType: .movie, tmdbID: 700_001,
        createdBy: "Jo Vance", createdAt: Date().addingTimeInterval(-5_400),
        comments: [
          OverseerrComment(
            id: 44, message: "Audio drifts out of sync about twelve minutes in.",
            author: "Jo Vance", createdAt: Date().addingTimeInterval(-5_400))
        ],
        title: "The Cartographer"),
      OverseerrIssue(
        id: 13, type: .subtitles, status: .resolved, mediaType: .tv, tmdbID: 700_002,
        createdBy: "Sam Okafor", createdAt: Date().addingTimeInterval(-172_800),
        comments: [], title: "Northern Lights"),
    ]
  }

  /// Search candidates. One is already available, so the sheet's
  /// already-in-library state is reachable in the demo.
  static func searchResults(
    matching term: String, existing: [OverseerrRequest]
  ) -> [OverseerrSearchResult] {
    let candidates:
      [(id: Int, type: OverseerrMediaType, title: String, year: Int, status: MediaAvailability?)] = [
        (700_013, .movie, "Winter Ledger", 2022, nil),
        (700_014, .tv, "Coastal Watch", 2026, nil),
        (700_001, .movie, "The Cartographer", 2024, .available),
      ]
    let query = term.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    return candidates
      .filter { query.isEmpty || $0.title.lowercased().contains(query) }
      .map { candidate in
        // A candidate already requested in this session reads as pending, the
        // way Overseerr's own `mediaInfo` would after a re-query.
        let alreadyRequested = existing.contains { $0.tmdbID == candidate.id }
        return OverseerrSearchResult(
          id: candidate.id, mediaType: candidate.type, title: candidate.title,
          overview: candidate.type == .tv
            ? DemoArrFixtures.seriesOverview(candidate.id)
            : DemoArrFixtures.filmOverview(candidate.id),
          posterURL: nil,
          releaseDate: Calendar(identifier: .gregorian)
            .date(from: DateComponents(year: candidate.year, month: 6, day: 1)),
          mediaStatus: candidate.status ?? (alreadyRequested ? .pending : nil))
      }
  }

  static let seasons: [OverseerrSeason] = [
    OverseerrSeason(seasonNumber: 1, name: "Season 1", episodeCount: 12, airDate: nil),
    OverseerrSeason(seasonNumber: 2, name: "Season 2", episodeCount: 12, airDate: nil),
    OverseerrSeason(seasonNumber: 3, name: "Season 3", episodeCount: 10, airDate: nil),
  ]
}
