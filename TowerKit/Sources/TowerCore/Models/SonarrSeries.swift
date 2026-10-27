import Foundation

public enum SeriesStatus: String, Sendable, Hashable {
  case continuing, ended, upcoming, deleted, unknown

  public init(apiValue: String?) {
    self = SeriesStatus(rawValue: apiValue ?? "") ?? .unknown
  }

  public var displayName: String {
    switch self {
    case .continuing: "Continuing"
    case .ended: "Ended"
    case .upcoming: "Upcoming"
    case .deleted: "Deleted"
    case .unknown: "Unknown"
    }
  }
}

/// Sonarr's per-series numbering scheme, which changes how episodes are matched
/// and is therefore something the edit sheet has to offer.
public enum SeriesType: String, Sendable, Hashable, CaseIterable {
  case standard, daily, anime

  public init(apiValue: String?) {
    self = SeriesType(rawValue: apiValue ?? "") ?? .standard
  }

  public var displayName: String {
    switch self {
    case .standard: "Standard"
    case .daily: "Daily"
    case .anime: "Anime"
    }
  }
}

/// A series in a Sonarr library.
public struct SonarrSeries: Identifiable, Equatable, Sendable {
  public let id: Int
  public let tvdbID: Int?
  public let imdbID: String?
  public let title: String
  public let sortTitle: String
  public let year: Int?
  public let overview: String?
  public let network: String?
  public let runtimeMinutes: Int?
  public let certification: String?
  public let genres: [String]
  public let status: SeriesStatus
  public let seriesType: SeriesType
  public let isMonitored: Bool
  public let usesSeasonFolders: Bool
  public let qualityProfileID: Int
  public let path: String?
  public let rootFolderPath: String?
  public let tagIDs: [Int]
  public let added: Date?
  public let nextAiring: Date?
  public let previousAiring: Date?
  public let posterURL: URL?
  public let fanartURL: URL?
  public let seasons: [SonarrSeason]
  public let statistics: SonarrSeriesStatistics?

  public init(
    id: Int, tvdbID: Int?, imdbID: String?, title: String, sortTitle: String, year: Int?,
    overview: String?, network: String?, runtimeMinutes: Int?, certification: String?,
    genres: [String], status: SeriesStatus, seriesType: SeriesType, isMonitored: Bool,
    usesSeasonFolders: Bool, qualityProfileID: Int, path: String?, rootFolderPath: String?,
    tagIDs: [Int], added: Date?, nextAiring: Date?, previousAiring: Date?,
    posterURL: URL?, fanartURL: URL?, seasons: [SonarrSeason],
    statistics: SonarrSeriesStatistics?
  ) {
    self.id = id
    self.tvdbID = tvdbID
    self.imdbID = imdbID
    self.title = title
    self.sortTitle = sortTitle
    self.year = year
    self.overview = overview
    self.network = network
    self.runtimeMinutes = runtimeMinutes
    self.certification = certification
    self.genres = genres
    self.status = status
    self.seriesType = seriesType
    self.isMonitored = isMonitored
    self.usesSeasonFolders = usesSeasonFolders
    self.qualityProfileID = qualityProfileID
    self.path = path
    self.rootFolderPath = rootFolderPath
    self.tagIDs = tagIDs
    self.added = added
    self.nextAiring = nextAiring
    self.previousAiring = previousAiring
    self.posterURL = posterURL
    self.fanartURL = fanartURL
    self.seasons = seasons
    self.statistics = statistics
  }

  public var displayTitle: String {
    year.map { "\(title) (\($0))" } ?? title
  }

  public var sizeOnDiskBytes: Int64 { statistics?.sizeOnDiskBytes ?? 0 }

  /// Episodes on disk out of episodes that have aired — the figure the library
  /// row shows, and deliberately *not* out of the total including unaired ones,
  /// which would make a fully up-to-date continuing series look incomplete.
  public var completion: Double? {
    guard let statistics, statistics.episodeCount > 0 else { return nil }
    return min(1, Double(statistics.episodeFileCount) / Double(statistics.episodeCount))
  }

  public var isComplete: Bool {
    guard let statistics else { return false }
    return statistics.episodeCount > 0 && statistics.episodeFileCount >= statistics.episodeCount
  }
}

public struct SonarrSeriesStatistics: Equatable, Sendable {
  public let seasonCount: Int
  public let episodeFileCount: Int
  /// Aired episodes.
  public let episodeCount: Int
  /// Including unaired.
  public let totalEpisodeCount: Int
  public let sizeOnDiskBytes: Int64

  public init(
    seasonCount: Int, episodeFileCount: Int, episodeCount: Int,
    totalEpisodeCount: Int, sizeOnDiskBytes: Int64
  ) {
    self.seasonCount = seasonCount
    self.episodeFileCount = episodeFileCount
    self.episodeCount = episodeCount
    self.totalEpisodeCount = totalEpisodeCount
    self.sizeOnDiskBytes = sizeOnDiskBytes
  }
}

public struct SonarrSeason: Identifiable, Equatable, Sendable {
  public let seasonNumber: Int
  public let isMonitored: Bool
  public let episodeFileCount: Int
  public let episodeCount: Int
  public let totalEpisodeCount: Int
  public let sizeOnDiskBytes: Int64
  public let nextAiring: Date?

  /// The season number itself: unique within a series, and stable across
  /// refreshes in a way an array index is not.
  public var id: Int { seasonNumber }

  public init(
    seasonNumber: Int, isMonitored: Bool, episodeFileCount: Int, episodeCount: Int,
    totalEpisodeCount: Int, sizeOnDiskBytes: Int64, nextAiring: Date?
  ) {
    self.seasonNumber = seasonNumber
    self.isMonitored = isMonitored
    self.episodeFileCount = episodeFileCount
    self.episodeCount = episodeCount
    self.totalEpisodeCount = totalEpisodeCount
    self.sizeOnDiskBytes = sizeOnDiskBytes
    self.nextAiring = nextAiring
  }

  /// Season 0 is Sonarr's specials folder, and it is listed differently.
  public var isSpecials: Bool { seasonNumber == 0 }

  public var displayName: String {
    isSpecials ? "Specials" : "Season \(seasonNumber)"
  }

  public var isComplete: Bool {
    episodeCount > 0 && episodeFileCount >= episodeCount
  }
}

public struct SonarrEpisode: Identifiable, Equatable, Sendable {
  public let id: Int
  public let seriesID: Int
  public let seasonNumber: Int
  public let episodeNumber: Int
  public let title: String
  public let overview: String?
  public let airDate: Date?
  public let runtimeMinutes: Int?
  public let hasFile: Bool
  public let isMonitored: Bool
  public let file: SonarrEpisodeFile?

  public init(
    id: Int, seriesID: Int, seasonNumber: Int, episodeNumber: Int, title: String,
    overview: String?, airDate: Date?, runtimeMinutes: Int?, hasFile: Bool,
    isMonitored: Bool, file: SonarrEpisodeFile?
  ) {
    self.id = id
    self.seriesID = seriesID
    self.seasonNumber = seasonNumber
    self.episodeNumber = episodeNumber
    self.title = title
    self.overview = overview
    self.airDate = airDate
    self.runtimeMinutes = runtimeMinutes
    self.hasFile = hasFile
    self.isMonitored = isMonitored
    self.file = file
  }

  /// `S02E07`, zero-padded, which is how every other tool in this stack spells
  /// it and therefore what a user is searching the screen for.
  public var episodeCode: String {
    String(format: "S%02dE%02d", seasonNumber, episodeNumber)
  }

  /// Whether this has aired — an episode with no file that hasn't aired is not
  /// missing, and offering a search for it is offering to fail.
  public var hasAired: Bool {
    guard let airDate else { return false }
    return airDate <= Date()
  }

  public var isMissing: Bool { !hasFile && hasAired && isMonitored }

  /// What the detail screen's File section may say — see `ArrFileSection`.
  public var fileSection: ArrFileSection {
    .resolve(hasFile: hasFile, hasDetails: file != nil, isOut: hasAired)
  }
}

public struct SonarrEpisodeFile: Identifiable, Equatable, Sendable {
  public let id: Int
  public let relativePath: String?
  public let sizeBytes: Int64
  public let quality: String?
  public let releaseGroup: String?
  public let videoCodec: String?
  public let audioCodec: String?
  public let resolution: String?
  public let languages: [String]
  public let dateAdded: Date?

  public init(
    id: Int, relativePath: String?, sizeBytes: Int64, quality: String?, releaseGroup: String?,
    videoCodec: String?, audioCodec: String?, resolution: String?, languages: [String],
    dateAdded: Date?
  ) {
    self.id = id
    self.relativePath = relativePath
    self.sizeBytes = sizeBytes
    self.quality = quality
    self.releaseGroup = releaseGroup
    self.videoCodec = videoCodec
    self.audioCodec = audioCodec
    self.resolution = resolution
    self.languages = languages
    self.dateAdded = dateAdded
  }
}

/// A TVDB search result for the add flow.
public struct SonarrSeriesLookup: Identifiable, Equatable, Sendable {
  public var id: Int { tvdbID }
  public let tvdbID: Int
  public let title: String
  public let year: Int?
  public let overview: String?
  public let network: String?
  public let status: SeriesStatus
  public let posterURL: URL?
  public let existingSeriesID: Int?

  public init(
    tvdbID: Int, title: String, year: Int?, overview: String?, network: String?,
    status: SeriesStatus, posterURL: URL?, existingSeriesID: Int?
  ) {
    self.tvdbID = tvdbID
    self.title = title
    self.year = year
    self.overview = overview
    self.network = network
    self.status = status
    self.posterURL = posterURL
    self.existingSeriesID = existingSeriesID
  }

  public var isAlreadyAdded: Bool { existingSeriesID != nil }
}

/// Which episodes Sonarr should monitor when a series is added. Sonarr's own
/// vocabulary, because these are its rules and paraphrasing them would make the
/// picker mean something slightly different from what it does.
public enum SeriesMonitorOption: String, Sendable, Hashable, CaseIterable {
  case all
  case future
  case missing
  case existing
  case firstSeason
  case lastSeason
  case pilot
  case none

  public var displayName: String {
    switch self {
    case .all: "All episodes"
    case .future: "Future episodes"
    case .missing: "Missing episodes"
    case .existing: "Existing episodes"
    case .firstSeason: "First season"
    case .lastSeason: "Last season"
    case .pilot: "Pilot only"
    case .none: "None"
    }
  }
}

public struct SonarrAddSeriesRequest: Equatable, Sendable {
  public let lookup: SonarrSeriesLookup
  public let qualityProfileID: Int
  public let rootFolderPath: String
  public let seriesType: SeriesType
  public let monitorOption: SeriesMonitorOption
  public let usesSeasonFolders: Bool
  public let searchOnAdd: Bool
  public let tagIDs: [Int]

  public init(
    lookup: SonarrSeriesLookup, qualityProfileID: Int, rootFolderPath: String,
    seriesType: SeriesType = .standard, monitorOption: SeriesMonitorOption = .all,
    usesSeasonFolders: Bool = true, searchOnAdd: Bool = true, tagIDs: [Int] = []
  ) {
    self.lookup = lookup
    self.qualityProfileID = qualityProfileID
    self.rootFolderPath = rootFolderPath
    self.seriesType = seriesType
    self.monitorOption = monitorOption
    self.usesSeasonFolders = usesSeasonFolders
    self.searchOnAdd = searchOnAdd
    self.tagIDs = tagIDs
  }
}

public struct SonarrSeriesEdit: Equatable, Sendable {
  public var isMonitored: Bool
  public var qualityProfileID: Int
  public var seriesType: SeriesType
  public var usesSeasonFolders: Bool
  public var rootFolderPath: String?
  public var tagIDs: [Int]

  public init(
    isMonitored: Bool, qualityProfileID: Int, seriesType: SeriesType,
    usesSeasonFolders: Bool, rootFolderPath: String?, tagIDs: [Int]
  ) {
    self.isMonitored = isMonitored
    self.qualityProfileID = qualityProfileID
    self.seriesType = seriesType
    self.usesSeasonFolders = usesSeasonFolders
    self.rootFolderPath = rootFolderPath
    self.tagIDs = tagIDs
  }

  public init(series: SonarrSeries) {
    self.init(
      isMonitored: series.isMonitored,
      qualityProfileID: series.qualityProfileID,
      seriesType: series.seriesType,
      usesSeasonFolders: series.usesSeasonFolders,
      rootFolderPath: series.rootFolderPath,
      tagIDs: series.tagIDs
    )
  }
}
