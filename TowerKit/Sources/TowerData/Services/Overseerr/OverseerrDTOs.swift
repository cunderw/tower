import Foundation
import TowerCore

// Overseerr's wire types. `internal`, like every other service's DTOs.
//
// Two things shape this file:
// - **Enums are integers on the wire.** `status: 2` is "approved". The mapping
//   to named cases happens here so nothing above compares a magic number.
// - **Poster paths are TMDB-relative.** `"/abc.jpg"` has to be joined to
//   TMDB's image host, which is a transport concern and stays here.

/// TMDB serves images from its own CDN; Overseerr returns only the path.
/// `w500` is the size Overseerr's own web UI uses for posters.
///
/// **Already safe without `OpenableURL`**: the scheme and host are
/// literals here, so this cannot produce the scheme-less URL that mapping
/// exists to catch. The only remote input is a path.
enum TMDBImage {
  static func posterURL(path: String?) -> URL? {
    guard let path, !path.isEmpty else { return nil }
    return URL(string: "https://image.tmdb.org/t/p/w500\(path)")
  }
}

/// `yyyy-MM-dd`, which is what TMDB sends for release dates — not ISO 8601, so
/// the shared decoder's strategy doesn't apply.
enum TMDBDate {
  private static let formatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter
  }()

  static func parse(_ value: String?) -> Date? {
    guard let value, !value.isEmpty else { return nil }
    return formatter.date(from: value)
  }
}

// MARK: - Requests

struct RequestPageDTO: Decodable, Sendable {
  let pageInfo: PageInfoDTO?
  let results: [MediaRequestDTO]?

  struct PageInfoDTO: Decodable, Sendable {
    let pages: Int?
    let pageSize: Int?
    let results: Int?
    let page: Int?
  }
}

struct MediaRequestDTO: Decodable, Sendable {
  let id: Int
  let status: Int?
  let media: MediaInfoDTO?
  let createdAt: Date?
  let updatedAt: Date?
  let requestedBy: UserDTO?
  let is4k: Bool?
  let seasons: [SeasonRequestDTO]?

  struct SeasonRequestDTO: Decodable, Sendable {
    let seasonNumber: Int?
  }

  var domain: OverseerrRequest {
    OverseerrRequest(
      id: id,
      status: RequestStatus(apiValue: status),
      mediaType: OverseerrMediaType(apiValue: media?.mediaType),
      mediaID: media?.id ?? id,
      tmdbID: media?.tmdbId,
      tvdbID: media?.tvdbId,
      mediaStatus: MediaAvailability(apiValue: media?.status),
      requestedBy: requestedBy?.displayName,
      requestedByAvatarURL: requestedBy?.avatarURL,
      createdAt: createdAt,
      updatedAt: updatedAt,
      is4K: is4k ?? false,
      seasons: (seasons ?? []).compactMap(\.seasonNumber).sorted(),
      // Overseerr's `/request` response carries ids, not names. The repository
      // fills these in from the media detail where it can.
      title: media?.title ?? media?.name,
      posterURL: TMDBImage.posterURL(path: media?.posterPath))
  }
}

/// `MediaInfo` as Overseerr's OpenAPI spec documents it, plus the three fields
/// real Overseerr builds add and the published spec omits — `mediaType`, and
/// sometimes `title`/`name`. All optional, so a build that sends none of them
/// still decodes.
struct MediaInfoDTO: Decodable, Sendable {
  let id: Int?
  let tmdbId: Int?
  let tvdbId: Int?
  let status: Int?
  let mediaType: String?
  let title: String?
  let name: String?
  let posterPath: String?
}

struct UserDTO: Decodable, Sendable {
  let id: Int?
  let email: String?
  let username: String?
  let plexUsername: String?
  let displayName_: String?
  let avatar: String?

  enum CodingKeys: String, CodingKey {
    case id, email, username, plexUsername, avatar
    case displayName_ = "displayName"
  }

  /// Overseerr's own precedence: the display name if set, then the Plex
  /// username, then the local username, then the email. Picking a different
  /// order shows a different person's name than the web UI does.
  var displayName: String? {
    for candidate in [displayName_, plexUsername, username, email] {
      if let candidate, !candidate.isEmpty { return candidate }
    }
    return nil
  }

  /// **Deliberately not `OpenableURL`**, unlike every other URL mapping
  /// in this layer. Gravatar and Plex avatars arrive absolute, but Overseerr's
  /// *local* ones are server-relative by design and are meant to be resolved
  /// against the instance's base URL by whoever renders them. Filtering on a
  /// scheme here would throw those away rather than fix them.
  ///
  /// Nothing consumes this today — it reaches no `TowerCore` model and no view —
  /// so the resolution it describes has never been written. If an avatar is ever
  /// shown, resolve relative values against `instance.baseURL` at that point.
  var avatarURL: URL? {
    guard let avatar, !avatar.isEmpty else { return nil }
    return URL(string: avatar)
  }
}

// MARK: - Search

/// `/search` returns a mixed array of movies, TV, and people, discriminated by
/// `mediaType`. People are dropped: Tower requests media, not actors.
struct SearchPageDTO: Decodable, Sendable {
  let page: Int?
  let totalPages: Int?
  let totalResults: Int?
  let results: [SearchResultDTO]?
}

struct SearchResultDTO: Decodable, Sendable {
  let id: Int
  let mediaType: String?
  let title: String?
  let name: String?
  let overview: String?
  let posterPath: String?
  let releaseDate: String?
  let firstAirDate: String?
  let mediaInfo: MediaInfoDTO?

  /// `nil` for anything that isn't requestable — a person result, most often.
  var domain: OverseerrSearchResult? {
    let type = OverseerrMediaType(apiValue: mediaType)
    guard type != .unknown else { return nil }
    // A movie has `title`/`releaseDate`; a series has `name`/`firstAirDate`.
    guard let displayTitle = title ?? name, !displayTitle.isEmpty else { return nil }
    return OverseerrSearchResult(
      id: id,
      mediaType: type,
      title: displayTitle,
      overview: overview.flatMap { $0.isEmpty ? nil : $0 },
      posterURL: TMDBImage.posterURL(path: posterPath),
      releaseDate: TMDBDate.parse(releaseDate ?? firstAirDate),
      mediaStatus: mediaInfo?.status.map { MediaAvailability(apiValue: $0) })
  }
}

// MARK: - Details (for titles and season pickers)

struct MovieDetailsDTO: Decodable, Sendable {
  let id: Int?
  let title: String?
  let posterPath: String?
}

struct TvDetailsDTO: Decodable, Sendable {
  let id: Int?
  let name: String?
  let posterPath: String?
  let seasons: [SeasonDTO]?

  struct SeasonDTO: Decodable, Sendable {
    let seasonNumber: Int?
    let name: String?
    let episodeCount: Int?
    let airDate: String?

    var domain: OverseerrSeason {
      OverseerrSeason(
        seasonNumber: seasonNumber ?? 0,
        name: name,
        episodeCount: episodeCount ?? 0,
        airDate: TMDBDate.parse(airDate))
    }
  }
}

// MARK: - Issues

struct IssuePageDTO: Decodable, Sendable {
  let pageInfo: RequestPageDTO.PageInfoDTO?
  let results: [IssueDTO]?
}

struct IssueDTO: Decodable, Sendable {
  let id: Int
  let issueType: Int?
  let status: Int?
  let media: MediaInfoDTO?
  let createdBy: UserDTO?
  let createdAt: Date?
  let comments: [IssueCommentDTO]?

  var domain: OverseerrIssue {
    OverseerrIssue(
      id: id,
      type: IssueType(apiValue: issueType),
      status: IssueStatus(apiValue: status),
      mediaType: OverseerrMediaType(apiValue: media?.mediaType),
      tmdbID: media?.tmdbId,
      createdBy: createdBy?.displayName,
      createdAt: createdAt,
      comments: (comments ?? []).map(\.domain),
      title: media?.title ?? media?.name)
  }
}

struct IssueCommentDTO: Decodable, Sendable {
  let id: Int
  let message: String?
  let user: UserDTO?
  let createdAt: Date?

  var domain: OverseerrComment {
    OverseerrComment(
      id: id, message: message ?? "", author: user?.displayName, createdAt: createdAt)
  }
}

// MARK: - Request bodies

struct SubmitRequestBody: Encodable, Sendable {
  let mediaType: String
  let mediaId: Int
  let seasons: [Int]?
  let is4k: Bool

  init(_ request: SubmitRequest) {
    self.mediaType = request.mediaType == .tv ? "tv" : "movie"
    self.mediaId = request.mediaID
    // Omitted entirely for a movie, and for "all seasons" — Overseerr treats an
    // empty array as "none" on some builds, which would file a request for a
    // series and no episodes.
    self.seasons = request.mediaType == .tv && !request.seasons.isEmpty ? request.seasons : nil
    self.is4k = request.is4K
  }
}

struct CommentBody: Encodable, Sendable {
  let message: String
}
