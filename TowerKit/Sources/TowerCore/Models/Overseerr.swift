import Foundation

// Overseerr's domain types. Plain `TowerCore`, like every other service.
//
// **Overseerr encodes its enums as integers**, which is the one thing to know
// about this API: a request's status is `2`, not `"approved"`. Those numbers
// are mapped to named cases here so nothing above `TowerData` compares against
// a magic number — and, as everywhere else, an unrecognised value degrades to
// `.unknown` rather than failing the decode.

/// A request's lifecycle. The numbers are Overseerr's own.
public enum RequestStatus: Int, Sendable, Hashable, CaseIterable {
  case pending = 1
  case approved = 2
  case declined = 3
  case failed = 4
  case unknown = 0

  public init(apiValue: Int?) {
    self = RequestStatus(rawValue: apiValue ?? 0) ?? .unknown
  }

  public var displayName: String {
    switch self {
    case .pending: "Pending"
    case .approved: "Approved"
    case .declined: "Declined"
    case .failed: "Failed"
    case .unknown: "Unknown"
    }
  }

  /// Whether this request is still waiting on a decision — the whole reason the
  /// pending list exists, and the only status where approve/decline apply.
  public var isActionable: Bool { self == .pending }
}

/// How far the *media* has got, which is a separate axis from the request's
/// own status: an approved request can still be unavailable while it downloads.
public enum MediaAvailability: Int, Sendable, Hashable {
  case unknown = 1
  case pending = 2
  case processing = 3
  case partiallyAvailable = 4
  case available = 5

  public init(apiValue: Int?) {
    self = MediaAvailability(rawValue: apiValue ?? 1) ?? .unknown
  }

  public var displayName: String {
    switch self {
    case .unknown: "Not requested"
    case .pending: "Pending"
    case .processing: "Processing"
    case .partiallyAvailable: "Partly available"
    case .available: "Available"
    }
  }
}

public enum OverseerrMediaType: String, Sendable, Hashable {
  case movie, tv, unknown

  public init(apiValue: String?) {
    self = OverseerrMediaType(rawValue: apiValue ?? "") ?? .unknown
  }

  public var displayName: String {
    switch self {
    case .movie: "Movie"
    case .tv: "Series"
    case .unknown: "Media"
    }
  }
}

/// One request.
///
/// **`title` is optional and often absent.** Overseerr's `/request` response
/// carries the media's *ids*, not its name — the title lives in TMDB behind a
/// second call. The repository fills it in where it can; a row with no title
/// falls back to the media type and id rather than blocking the list on a fan
/// of detail requests.
public struct OverseerrRequest: Sendable, Hashable, Identifiable {
  public let id: Int
  public let status: RequestStatus
  public let mediaType: OverseerrMediaType
  public let mediaID: Int
  public let tmdbID: Int?
  public let tvdbID: Int?
  public let mediaStatus: MediaAvailability
  public let requestedBy: String?
  public let requestedByAvatarURL: URL?
  public let createdAt: Date?
  public let updatedAt: Date?
  public let is4K: Bool
  /// Season numbers, for a TV request. Empty for a movie.
  public let seasons: [Int]
  public var title: String?
  public var posterURL: URL?

  public var displayTitle: String {
    if let title, !title.isEmpty { return title }
    return "\(mediaType.displayName) #\(tmdbID ?? mediaID)"
  }

  public init(
    id: Int, status: RequestStatus, mediaType: OverseerrMediaType, mediaID: Int, tmdbID: Int?,
    tvdbID: Int?, mediaStatus: MediaAvailability, requestedBy: String?,
    requestedByAvatarURL: URL?, createdAt: Date?, updatedAt: Date?, is4K: Bool,
    seasons: [Int], title: String? = nil, posterURL: URL? = nil
  ) {
    self.id = id
    self.status = status
    self.mediaType = mediaType
    self.mediaID = mediaID
    self.tmdbID = tmdbID
    self.tvdbID = tvdbID
    self.mediaStatus = mediaStatus
    self.requestedBy = requestedBy
    self.requestedByAvatarURL = requestedByAvatarURL
    self.createdAt = createdAt
    self.updatedAt = updatedAt
    self.is4K = is4K
    self.seasons = seasons
    self.title = title
    self.posterURL = posterURL
  }
}

/// A page of requests.
///
/// Overseerr paginates with `take`/`skip` and reports the totals in
/// `pageInfo`. Modelled explicitly because the all-requests list is the one
/// screen that genuinely needs more than one page.
public struct OverseerrRequestPage: Sendable, Hashable {
  public let requests: [OverseerrRequest]
  public let page: Int
  public let pages: Int
  public let totalResults: Int

  public var hasMore: Bool { page < pages }

  public init(requests: [OverseerrRequest], page: Int, pages: Int, totalResults: Int) {
    self.requests = requests
    self.page = page
    self.pages = pages
    self.totalResults = totalResults
  }
}

/// The filters the requests list offers, which are Overseerr's own query
/// values rather than a Tower invention.
public enum RequestFilter: String, Sendable, Hashable, CaseIterable, Identifiable {
  case all, pending, approved, declined, processing, available, failed

  public var id: String { rawValue }

  public var displayName: String {
    switch self {
    case .all: "All"
    case .pending: "Pending"
    case .approved: "Approved"
    case .declined: "Declined"
    case .processing: "Processing"
    case .available: "Available"
    case .failed: "Failed"
    }
  }
}

// MARK: - Search

/// A search hit, from `/search`.
public struct OverseerrSearchResult: Sendable, Hashable, Identifiable {
  /// TMDB's id, which is also what a request is filed against.
  public let id: Int
  public let mediaType: OverseerrMediaType
  public let title: String
  public let overview: String?
  public let posterURL: URL?
  public let releaseDate: Date?
  /// Where this already stands in the stack, when Overseerr knows — the reason
  /// a search result can say "already available" instead of offering a
  /// duplicate request.
  public let mediaStatus: MediaAvailability?

  public var year: Int? {
    releaseDate.map { Calendar(identifier: .gregorian).component(.year, from: $0) }
  }

  /// Whether requesting this would be a duplicate.
  public var isAlreadyInLibrary: Bool {
    switch mediaStatus {
    case .available, .partiallyAvailable, .processing, .pending: true
    case .unknown, nil: false
    }
  }

  public init(
    id: Int, mediaType: OverseerrMediaType, title: String, overview: String?, posterURL: URL?,
    releaseDate: Date?, mediaStatus: MediaAvailability?
  ) {
    self.id = id
    self.mediaType = mediaType
    self.title = title
    self.overview = overview
    self.posterURL = posterURL
    self.releaseDate = releaseDate
    self.mediaStatus = mediaStatus
  }
}

/// What the request sheet submits.
///
/// **TV requests carry their season selection**, which is the one shape
/// difference between the two media types: a movie is requested whole, a
/// series is requested by season.
public struct SubmitRequest: Sendable, Hashable {
  public let mediaType: OverseerrMediaType
  /// TMDB id.
  public let mediaID: Int
  /// Season numbers. Empty means "all seasons" for TV, and is meaningless for
  /// a movie — Overseerr wants the key omitted in both cases, which the DTO
  /// handles.
  public let seasons: [Int]
  public let is4K: Bool

  public init(mediaType: OverseerrMediaType, mediaID: Int, seasons: [Int] = [], is4K: Bool = false) {
    self.mediaType = mediaType
    self.mediaID = mediaID
    self.seasons = seasons
    self.is4K = is4K
  }
}

/// A series' seasons, for the request sheet's picker.
public struct OverseerrSeason: Sendable, Hashable, Identifiable {
  public let seasonNumber: Int
  public let name: String?
  public let episodeCount: Int
  public let airDate: Date?

  public var id: Int { seasonNumber }

  public var displayName: String {
    if seasonNumber == 0 { return "Specials" }
    return name ?? "Season \(seasonNumber)"
  }

  public init(seasonNumber: Int, name: String?, episodeCount: Int, airDate: Date?) {
    self.seasonNumber = seasonNumber
    self.name = name
    self.episodeCount = episodeCount
    self.airDate = airDate
  }
}

// MARK: - Issues

public enum IssueType: Int, Sendable, Hashable, CaseIterable {
  case video = 1
  case audio = 2
  case subtitles = 3
  case other = 4

  public init(apiValue: Int?) {
    self = IssueType(rawValue: apiValue ?? 4) ?? .other
  }

  public var displayName: String {
    switch self {
    case .video: "Video"
    case .audio: "Audio"
    case .subtitles: "Subtitles"
    case .other: "Other"
    }
  }
}

public enum IssueStatus: Int, Sendable, Hashable {
  case open = 1
  case resolved = 2
  case unknown = 0

  public init(apiValue: Int?) {
    self = IssueStatus(rawValue: apiValue ?? 0) ?? .unknown
  }

  public var displayName: String {
    switch self {
    case .open: "Open"
    case .resolved: "Resolved"
    case .unknown: "Unknown"
    }
  }
}

public struct OverseerrIssue: Sendable, Hashable, Identifiable {
  public let id: Int
  public let type: IssueType
  public let status: IssueStatus
  public let mediaType: OverseerrMediaType
  public let tmdbID: Int?
  public let createdBy: String?
  public let createdAt: Date?
  public let comments: [OverseerrComment]
  public var title: String?

  public var displayTitle: String {
    if let title, !title.isEmpty { return title }
    return "\(mediaType.displayName) #\(tmdbID ?? id)"
  }

  public init(
    id: Int, type: IssueType, status: IssueStatus, mediaType: OverseerrMediaType, tmdbID: Int?,
    createdBy: String?, createdAt: Date?, comments: [OverseerrComment], title: String? = nil
  ) {
    self.id = id
    self.type = type
    self.status = status
    self.mediaType = mediaType
    self.tmdbID = tmdbID
    self.createdBy = createdBy
    self.createdAt = createdAt
    self.comments = comments
    self.title = title
  }
}

public struct OverseerrComment: Sendable, Hashable, Identifiable {
  public let id: Int
  public let message: String
  public let author: String?
  public let createdAt: Date?

  public init(id: Int, message: String, author: String?, createdAt: Date?) {
    self.id = id
    self.message = message
    self.author = author
    self.createdAt = createdAt
  }
}
