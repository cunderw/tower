import Foundation

// Bazarr's domain types. Plain `TowerCore`, like every other service.
//
// **Bazarr is not an *arr, despite the name.** It has no `/api/v3`, no
// `system/status` shaped like the others, and no shared queue/calendar/history
// surface — so it reuses Tower's *UI* patterns and none of `ArrClientCore`.
// Holding this file separate from `ArrShared` is what keeps it that way.

/// A language Bazarr wants, as it appears on a wanted row.
///
/// Bazarr carries three orthogonal flags with a language — hearing-impaired,
/// forced, and the language itself — and a subtitle that matches the language
/// but not the flags is the wrong subtitle. They travel together for that
/// reason.
public struct SubtitleLanguage: Sendable, Hashable, Identifiable {
  /// Two- or three-letter code, e.g. `en`.
  public let code: String
  public let name: String
  public let isHearingImpaired: Bool
  public let isForced: Bool

  public var id: String { "\(code)-\(isHearingImpaired)-\(isForced)" }

  /// What a row shows: "English", "English (HI)", "English (forced)".
  public var displayName: String {
    var suffixes: [String] = []
    if isHearingImpaired { suffixes.append("HI") }
    if isForced { suffixes.append("forced") }
    guard !suffixes.isEmpty else { return name }
    return "\(name) (\(suffixes.joined(separator: ", ")))"
  }

  public init(code: String, name: String, isHearingImpaired: Bool, isForced: Bool) {
    self.code = code
    self.name = name
    self.isHearingImpaired = isHearingImpaired
    self.isForced = isForced
  }
}

/// An episode or a movie missing subtitles.
///
/// One type for both, because the wanted list mixes them and every screen
/// treats them the same — only the ids differ, and which id is set is what
/// tells the repository which endpoint to call.
public struct WantedSubtitle: Sendable, Hashable, Identifiable {
  public let title: String
  /// Series title plus episode label, for a TV row. `nil` for a movie.
  public let subtitle: String?
  /// Set for a TV item.
  public let seriesID: Int?
  public let episodeID: Int?
  /// Set for a movie.
  public let radarrID: Int?
  public let missing: [SubtitleLanguage]

  public var id: String {
    if let episodeID { return "episode-\(episodeID)" }
    if let radarrID { return "movie-\(radarrID)" }
    return "unknown-\(title)"
  }

  public var isEpisode: Bool { episodeID != nil }

  public init(
    title: String, subtitle: String?, seriesID: Int?, episodeID: Int?, radarrID: Int?,
    missing: [SubtitleLanguage]
  ) {
    self.title = title
    self.subtitle = subtitle
    self.seriesID = seriesID
    self.episodeID = episodeID
    self.radarrID = radarrID
    self.missing = missing
  }
}

/// One candidate from a manual subtitle search.
public struct SubtitleCandidate: Sendable, Hashable, Identifiable {
  public let provider: String
  public let language: SubtitleLanguage
  /// Bazarr's own match score, 0…100. The single most useful number here —
  /// a 95 is almost certainly right and a 40 almost certainly is not.
  public let score: Int
  /// The opaque handle Bazarr wants back to download this exact subtitle.
  /// Sent verbatim; Tower never parses it.
  public let subtitleID: String
  public let releaseInfo: [String]
  public let uploader: String?
  public let url: URL?
  /// Whether Bazarr matched this to the release file rather than just the
  /// title — the difference between "in sync" and "probably out of sync".
  public let matchedBy: [String]

  public var id: String { "\(provider)-\(subtitleID)" }

  /// A score band, so a row can say something rather than only showing a
  /// number.
  public var confidence: SubtitleConfidence {
    switch score {
    case 90...: .high
    case 70..<90: .medium
    default: .low
    }
  }

  public init(
    provider: String, language: SubtitleLanguage, score: Int, subtitleID: String,
    releaseInfo: [String], uploader: String?, url: URL?, matchedBy: [String]
  ) {
    self.provider = provider
    self.language = language
    self.score = score
    self.subtitleID = subtitleID
    self.releaseInfo = releaseInfo
    self.uploader = uploader
    self.url = url
    self.matchedBy = matchedBy
  }
}

public enum SubtitleConfidence: Sendable, Hashable {
  case high, medium, low

  public var displayName: String {
    switch self {
    case .high: "Strong match"
    case .medium: "Likely match"
    case .low: "Weak match"
    }
  }
}

/// A subtitle provider and whether it is working.
public struct SubtitleProvider: Sendable, Hashable, Identifiable {
  public let name: String
  /// Bazarr's own words when something is wrong; `nil` when healthy.
  public let message: String?
  /// When it will next be retried, for a provider in a back-off.
  public let retryAt: String?

  public var id: String { name }

  /// Mapped onto the same three states every other health surface in Tower
  /// uses, so the row reads the same as an indexer's or a service's.
  public var status: ProviderStatus {
    guard let message, !message.isEmpty else { return .healthy }
    // Bazarr says "Good" for a working provider rather than sending nothing.
    if message.caseInsensitiveCompare("good") == .orderedSame { return .healthy }
    return .failing
  }

  public init(name: String, message: String?, retryAt: String?) {
    self.name = name
    self.message = message
    self.retryAt = retryAt
  }
}

public enum ProviderStatus: Sendable, Hashable {
  case healthy, failing

  public var displayName: String {
    switch self {
    case .healthy: "Working"
    case .failing: "Failing"
    }
  }
}

/// One row of Bazarr's history.
public struct SubtitleHistoryRecord: Sendable, Hashable, Identifiable {
  public let id: String
  public let title: String
  public let subtitle: String?
  public let language: SubtitleLanguage?
  public let provider: String?
  public let score: Int?
  public let timestamp: String?
  /// Bazarr's `action` code, mapped to something readable.
  public let action: SubtitleHistoryAction

  public init(
    id: String, title: String, subtitle: String?, language: SubtitleLanguage?,
    provider: String?, score: Int?, timestamp: String?, action: SubtitleHistoryAction
  ) {
    self.id = id
    self.title = title
    self.subtitle = subtitle
    self.language = language
    self.provider = provider
    self.score = score
    self.timestamp = timestamp
    self.action = action
  }
}

/// Bazarr encodes its history actions as integers.
public enum SubtitleHistoryAction: Int, Sendable, Hashable {
  case deleted = 0
  case downloaded = 1
  case manuallyDownloaded = 2
  case upgraded = 3
  case manuallyUploaded = 4
  case synced = 5
  case unknown = -1

  public init(apiValue: Int?) {
    self = SubtitleHistoryAction(rawValue: apiValue ?? -1) ?? .unknown
  }

  public var displayName: String {
    switch self {
    case .deleted: "Deleted"
    case .downloaded: "Downloaded"
    case .manuallyDownloaded: "Downloaded manually"
    case .upgraded: "Upgraded"
    case .manuallyUploaded: "Uploaded"
    case .synced: "Synced"
    case .unknown: "Unknown"
    }
  }
}

/// A library row — a series or a film Bazarr is managing subtitles for.
public struct BazarrMediaItem: Sendable, Hashable, Identifiable {
  /// Sonarr's series id or Radarr's movie id, depending on `isSeries`.
  public let serviceID: Int
  public let title: String
  public let isSeries: Bool
  public let posterURL: URL?
  public let monitored: Bool
  /// How many episodes (or how many languages, for a film) still lack a
  /// subtitle. The number this whole screen exists to drive to zero.
  public let missingCount: Int
  public let languageProfileName: String?

  public var id: String { "\(isSeries ? "series" : "movie")-\(serviceID)" }

  public init(
    serviceID: Int, title: String, isSeries: Bool, posterURL: URL?, monitored: Bool,
    missingCount: Int, languageProfileName: String?
  ) {
    self.serviceID = serviceID
    self.title = title
    self.isSeries = isSeries
    self.posterURL = posterURL
    self.monitored = monitored
    self.missingCount = missingCount
    self.languageProfileName = languageProfileName
  }
}
