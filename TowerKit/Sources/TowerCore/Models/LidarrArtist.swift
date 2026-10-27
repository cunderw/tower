import Foundation

// Lidarr's domain types. Plain `TowerCore`, like every other service.
//
// **Three levels, not two.** Radarr has films and Sonarr has series → seasons →
// episodes; Lidarr has artists → albums → tracks, and the middle level is the
// one people actually act on. That shape is why this is its own model file
// rather than a reuse of `SonarrSeries` with the nouns changed.

public enum LidarrArtistStatus: String, Sendable, Hashable {
  case continuing, ended, unknown

  public init(apiValue: String?) {
    self = LidarrArtistStatus(rawValue: (apiValue ?? "").lowercased()) ?? .unknown
  }

  public var displayName: String {
    switch self {
    case .continuing: "Active"
    case .ended: "Ended"
    case .unknown: "Unknown"
    }
  }
}

/// What a library row is missing, if anything.
///
/// The same three-way split the Radarr library makes, in music's terms: an
/// artist with every track on disk is complete, one with some is partial, one
/// with none is missing. "Partial" is the interesting case here in a way it
/// isn't for films — a discography is rarely all-or-nothing.
public enum LidarrLibraryState: Sendable, Hashable {
  case complete
  case partial
  case missing

  public var displayName: String {
    switch self {
    case .complete: "Complete"
    case .partial: "Partial"
    case .missing: "Missing"
    }
  }
}

public struct LidarrArtist: Sendable, Hashable, Identifiable {
  public let id: Int
  public let name: String
  public let sortName: String
  public let foreignArtistID: String?
  public let overview: String?
  public let artistType: String?
  public let disambiguation: String?
  public let status: LidarrArtistStatus
  public let isMonitored: Bool
  public let qualityProfileID: Int
  public let metadataProfileID: Int
  public let path: String?
  public let rootFolderPath: String?
  public let genres: [String]
  public let tagIDs: [Int]
  public let added: Date?
  public let posterURL: URL?
  public let statistics: LidarrArtistStatistics?

  public var displayName: String {
    guard let disambiguation, !disambiguation.isEmpty else { return name }
    return "\(name) (\(disambiguation))"
  }

  public var libraryState: LidarrLibraryState {
    guard let statistics, statistics.totalTrackCount > 0 else { return .missing }
    if statistics.trackFileCount == 0 { return .missing }
    return statistics.trackFileCount >= statistics.trackCount ? .complete : .partial
  }

  public init(
    id: Int, name: String, sortName: String, foreignArtistID: String?, overview: String?,
    artistType: String?, disambiguation: String?, status: LidarrArtistStatus,
    isMonitored: Bool, qualityProfileID: Int, metadataProfileID: Int, path: String?,
    rootFolderPath: String?, genres: [String], tagIDs: [Int], added: Date?, posterURL: URL?,
    statistics: LidarrArtistStatistics?
  ) {
    self.id = id
    self.name = name
    self.sortName = sortName
    self.foreignArtistID = foreignArtistID
    self.overview = overview
    self.artistType = artistType
    self.disambiguation = disambiguation
    self.status = status
    self.isMonitored = isMonitored
    self.qualityProfileID = qualityProfileID
    self.metadataProfileID = metadataProfileID
    self.path = path
    self.rootFolderPath = rootFolderPath
    self.genres = genres
    self.tagIDs = tagIDs
    self.added = added
    self.posterURL = posterURL
    self.statistics = statistics
  }
}

public struct LidarrArtistStatistics: Sendable, Hashable {
  public let albumCount: Int
  public let trackFileCount: Int
  /// Tracks on released albums Lidarr is monitoring, plus any track that already
  /// has a file. A track with no file on an unmonitored or unreleased album is
  /// left out.
  public let trackCount: Int
  public let totalTrackCount: Int
  public let sizeOnDiskBytes: Int64

  /// 0…1 against `trackCount`, not the total. Counting unmonitored albums
  /// would make every artist look permanently incomplete — the same
  /// reasoning as Sonarr's aired-versus-total progress.
  public var progress: Double? {
    guard trackCount > 0 else { return nil }
    return min(1, Double(trackFileCount) / Double(trackCount))
  }

  public init(
    albumCount: Int, trackFileCount: Int, trackCount: Int, totalTrackCount: Int,
    sizeOnDiskBytes: Int64
  ) {
    self.albumCount = albumCount
    self.trackFileCount = trackFileCount
    self.trackCount = trackCount
    self.totalTrackCount = totalTrackCount
    self.sizeOnDiskBytes = sizeOnDiskBytes
  }
}

public struct LidarrAlbum: Sendable, Hashable, Identifiable {
  public let id: Int
  public let artistID: Int
  public let title: String
  public let disambiguation: String?
  public let overview: String?
  public let albumType: String?
  public let secondaryTypes: [String]
  public let releaseDate: Date?
  public let isMonitored: Bool
  public let durationMilliseconds: Int?
  public let genres: [String]
  public let coverURL: URL?
  public let statistics: LidarrAlbumStatistics?

  public var displayTitle: String {
    guard let disambiguation, !disambiguation.isEmpty else { return title }
    return "\(title) (\(disambiguation))"
  }

  public var year: Int? {
    releaseDate.map { Calendar(identifier: .gregorian).component(.year, from: $0) }
  }

  /// Whether this album has been released yet. The album screen disables
  /// search for an unreleased album and says "Not released", because a search
  /// sends the user after something that does not exist.
  public var isReleased: Bool {
    guard let releaseDate else { return true }
    return releaseDate <= .now
  }

  /// What the album has on disk. An unreleased album is `.missing` too, and
  /// `isReleased` is what tells the two apart on screen.
  public var libraryState: LidarrLibraryState {
    guard let statistics, statistics.trackCount > 0 else { return .missing }
    if statistics.trackFileCount == 0 { return .missing }
    return statistics.trackFileCount >= statistics.trackCount ? .complete : .partial
  }

  public init(
    id: Int, artistID: Int, title: String, disambiguation: String?, overview: String?,
    albumType: String?, secondaryTypes: [String], releaseDate: Date?, isMonitored: Bool,
    durationMilliseconds: Int?, genres: [String], coverURL: URL?,
    statistics: LidarrAlbumStatistics?
  ) {
    self.id = id
    self.artistID = artistID
    self.title = title
    self.disambiguation = disambiguation
    self.overview = overview
    self.albumType = albumType
    self.secondaryTypes = secondaryTypes
    self.releaseDate = releaseDate
    self.isMonitored = isMonitored
    self.durationMilliseconds = durationMilliseconds
    self.genres = genres
    self.coverURL = coverURL
    self.statistics = statistics
  }
}

public struct LidarrAlbumStatistics: Sendable, Hashable {
  public let trackFileCount: Int
  public let trackCount: Int
  public let totalTrackCount: Int
  public let sizeOnDiskBytes: Int64

  public init(
    trackFileCount: Int, trackCount: Int, totalTrackCount: Int, sizeOnDiskBytes: Int64
  ) {
    self.trackFileCount = trackFileCount
    self.trackCount = trackCount
    self.totalTrackCount = totalTrackCount
    self.sizeOnDiskBytes = sizeOnDiskBytes
  }

  /// The album's track line: files against the tracked count, or the album's
  /// size in tracks when Lidarr tracks none of them (an unreleased or
  /// unmonitored album with no files), where "0 of 0" would say nothing. Nil
  /// when the album has no tracks at all.
  public var trackSummary: String? {
    if trackCount > 0 { return "\(trackFileCount) of \(trackCount)" }
    guard totalTrackCount > 0 else { return nil }
    return Formatters.count(totalTrackCount, "track")
  }
}

public struct LidarrTrack: Sendable, Hashable, Identifiable {
  public let id: Int
  public let albumID: Int
  public let title: String
  public let trackNumber: String?
  public let absoluteTrackNumber: Int?
  public let mediumNumber: Int?
  public let durationMilliseconds: Int?
  public let hasFile: Bool
  public let isExplicit: Bool

  public init(
    id: Int, albumID: Int, title: String, trackNumber: String?, absoluteTrackNumber: Int?,
    mediumNumber: Int?, durationMilliseconds: Int?, hasFile: Bool, isExplicit: Bool
  ) {
    self.id = id
    self.albumID = albumID
    self.title = title
    self.trackNumber = trackNumber
    self.absoluteTrackNumber = absoluteTrackNumber
    self.mediumNumber = mediumNumber
    self.durationMilliseconds = durationMilliseconds
    self.hasFile = hasFile
    self.isExplicit = isExplicit
  }
}

// MARK: - Add and edit

/// A lookup hit from `/artist/lookup`.
public struct LidarrArtistLookup: Sendable, Hashable, Identifiable {
  /// MusicBrainz id — the identity an add is filed against, and a string rather
  /// than an integer, unlike Radarr's TMDb id.
  public let foreignArtistID: String
  public let name: String
  public let overview: String?
  public let artistType: String?
  public let disambiguation: String?
  public let posterURL: URL?
  /// Non-nil when this artist is already in the library.
  public let existingArtistID: Int?

  public var id: String { foreignArtistID }
  public var isAlreadyAdded: Bool { existingArtistID != nil }

  public init(
    foreignArtistID: String, name: String, overview: String?, artistType: String?,
    disambiguation: String?, posterURL: URL?, existingArtistID: Int?
  ) {
    self.foreignArtistID = foreignArtistID
    self.name = name
    self.overview = overview
    self.artistType = artistType
    self.disambiguation = disambiguation
    self.posterURL = posterURL
    self.existingArtistID = existingArtistID
  }
}

/// Which of an artist's albums Lidarr should monitor when adding them.
public enum LidarrMonitorOption: String, Sendable, Hashable, CaseIterable, Identifiable {
  case all
  case future
  case missing
  case existing
  case latest
  case first
  case none

  public var id: String { rawValue }

  public var displayName: String {
    switch self {
    case .all: "All albums"
    case .future: "Future albums"
    case .missing: "Missing albums"
    case .existing: "Existing albums"
    case .latest: "Latest album"
    case .first: "First album"
    case .none: "None"
    }
  }
}

public struct LidarrAddArtistRequest: Sendable, Hashable {
  public let lookup: LidarrArtistLookup
  public let qualityProfileID: Int
  /// Lidarr's second profile axis, and the one that has no analogue in
  /// Radarr or Sonarr: it decides which *album types* are wanted at all.
  public let metadataProfileID: Int
  public let rootFolderPath: String
  public let monitorOption: LidarrMonitorOption
  public let isMonitored: Bool
  public let searchForMissingAlbums: Bool
  public let tagIDs: [Int]

  public init(
    lookup: LidarrArtistLookup, qualityProfileID: Int, metadataProfileID: Int,
    rootFolderPath: String, monitorOption: LidarrMonitorOption = .all,
    isMonitored: Bool = true, searchForMissingAlbums: Bool = true, tagIDs: [Int] = []
  ) {
    self.lookup = lookup
    self.qualityProfileID = qualityProfileID
    self.metadataProfileID = metadataProfileID
    self.rootFolderPath = rootFolderPath
    self.monitorOption = monitorOption
    self.isMonitored = isMonitored
    self.searchForMissingAlbums = searchForMissingAlbums
    self.tagIDs = tagIDs
  }
}

public struct LidarrArtistEdit: Sendable, Hashable {
  public var isMonitored: Bool
  public var qualityProfileID: Int
  public var metadataProfileID: Int
  public var rootFolderPath: String?
  public var tagIDs: [Int]

  public init(artist: LidarrArtist) {
    self.isMonitored = artist.isMonitored
    self.qualityProfileID = artist.qualityProfileID
    self.metadataProfileID = artist.metadataProfileID
    self.rootFolderPath = artist.rootFolderPath
    self.tagIDs = artist.tagIDs
  }
}

/// Lidarr's metadata profiles, for the picker the add and edit forms need.
public struct LidarrMetadataProfile: Sendable, Hashable, Identifiable {
  public let id: Int
  public let name: String

  public init(id: Int, name: String) {
    self.id = id
    self.name = name
  }
}
