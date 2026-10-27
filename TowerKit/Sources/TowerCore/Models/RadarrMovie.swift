import Foundation

/// Where a film is in its release cycle, as Radarr tracks it. Also the vocabulary
/// of "minimum availability" — the point at which Radarr starts looking.
public enum MovieAvailability: String, Sendable, Hashable, CaseIterable {
  case tba
  case announced
  case inCinemas
  case released
  case deleted
  case unknown

  public init(apiValue: String?) {
    self = MovieAvailability(rawValue: apiValue ?? "") ?? .unknown
  }

  public var displayName: String {
    switch self {
    case .tba: "TBA"
    case .announced: "Announced"
    case .inCinemas: "In cinemas"
    case .released: "Released"
    case .deleted: "Deleted"
    case .unknown: "Unknown"
    }
  }

  /// The three Radarr offers in its minimum-availability picker. `deleted` and
  /// `unknown` are states a movie can be *in*, never things to wait for.
  public static var selectableForMinimumAvailability: [MovieAvailability] {
    [.announced, .inCinemas, .released]
  }
}

/// A film in a Radarr library.
///
/// Sizes are `Int64`: a 4K remux library passes `Int32`'s 2.1 GB ceiling with
/// one film in it, and `sizeOnDisk` is a per-*movie* figure that regularly runs
/// to tens of gigabytes — the library total to many terabytes.
public struct RadarrMovie: Identifiable, Equatable, Sendable {
  public let id: Int
  public let tmdbID: Int?
  public let imdbID: String?
  public let title: String
  /// Radarr's own sort title (articles stripped). Used for ordering so the app
  /// agrees with the service's own list rather than resorting differently.
  public let sortTitle: String
  public let year: Int?
  public let overview: String?
  public let studio: String?
  public let runtimeMinutes: Int?
  public let certification: String?
  public let genres: [String]
  public let status: MovieAvailability
  public let minimumAvailability: MovieAvailability
  public let isMonitored: Bool
  public let hasFile: Bool
  /// Radarr's own answer to "should this have been downloadable by now",
  /// which folds in `minimumAvailability` — cheaper and more correct than
  /// recomputing it from dates here.
  public let isAvailable: Bool
  public let sizeOnDiskBytes: Int64
  public let qualityProfileID: Int
  public let path: String?
  public let rootFolderPath: String?
  public let tagIDs: [Int]
  public let added: Date?
  public let inCinemas: Date?
  public let digitalRelease: Date?
  public let physicalRelease: Date?
  public let posterURL: URL?
  public let fanartURL: URL?
  /// Present when `hasFile`; the file's own details.
  public let file: RadarrMovieFile?

  public init(
    id: Int, tmdbID: Int?, imdbID: String?, title: String, sortTitle: String, year: Int?,
    overview: String?, studio: String?, runtimeMinutes: Int?, certification: String?,
    genres: [String], status: MovieAvailability, minimumAvailability: MovieAvailability,
    isMonitored: Bool, hasFile: Bool, isAvailable: Bool, sizeOnDiskBytes: Int64,
    qualityProfileID: Int, path: String?, rootFolderPath: String?, tagIDs: [Int],
    added: Date?, inCinemas: Date?, digitalRelease: Date?, physicalRelease: Date?,
    posterURL: URL?, fanartURL: URL?, file: RadarrMovieFile?
  ) {
    self.id = id
    self.tmdbID = tmdbID
    self.imdbID = imdbID
    self.title = title
    self.sortTitle = sortTitle
    self.year = year
    self.overview = overview
    self.studio = studio
    self.runtimeMinutes = runtimeMinutes
    self.certification = certification
    self.genres = genres
    self.status = status
    self.minimumAvailability = minimumAvailability
    self.isMonitored = isMonitored
    self.hasFile = hasFile
    self.isAvailable = isAvailable
    self.sizeOnDiskBytes = sizeOnDiskBytes
    self.qualityProfileID = qualityProfileID
    self.path = path
    self.rootFolderPath = rootFolderPath
    self.tagIDs = tagIDs
    self.added = added
    self.inCinemas = inCinemas
    self.digitalRelease = digitalRelease
    self.physicalRelease = physicalRelease
    self.posterURL = posterURL
    self.fanartURL = fanartURL
    self.file = file
  }

  public var displayTitle: String {
    year.map { "\(title) (\($0))" } ?? title
  }

  /// What the library row's availability badge says. Three states the user acts
  /// on differently: downloaded, missing something that exists, or waiting for
  /// something that doesn't exist yet.
  public var libraryState: LibraryState {
    if hasFile { return .downloaded }
    return isAvailable ? .missing : .unreleased
  }

  /// What the detail screen's File section may say — see `ArrFileSection`.
  public var fileSection: ArrFileSection {
    .resolve(hasFile: hasFile, hasDetails: file != nil, isOut: isAvailable)
  }

  public enum LibraryState: String, Sendable, Hashable {
    case downloaded, missing, unreleased

    public var displayName: String {
      switch self {
      case .downloaded: "Downloaded"
      case .missing: "Missing"
      case .unreleased: "Unreleased"
      }
    }
  }
}

/// The file Radarr has on disk for a movie.
public struct RadarrMovieFile: Identifiable, Equatable, Sendable {
  public let id: Int
  public let relativePath: String?
  public let sizeBytes: Int64
  public let quality: String?
  public let releaseGroup: String?
  public let videoCodec: String?
  public let audioCodec: String?
  public let audioChannels: Double?
  public let resolution: String?
  public let runtime: String?
  public let languages: [String]
  public let dateAdded: Date?

  public init(
    id: Int, relativePath: String?, sizeBytes: Int64, quality: String?, releaseGroup: String?,
    videoCodec: String?, audioCodec: String?, audioChannels: Double?, resolution: String?,
    runtime: String?, languages: [String], dateAdded: Date?
  ) {
    self.id = id
    self.relativePath = relativePath
    self.sizeBytes = sizeBytes
    self.quality = quality
    self.releaseGroup = releaseGroup
    self.videoCodec = videoCodec
    self.audioCodec = audioCodec
    self.audioChannels = audioChannels
    self.resolution = resolution
    self.runtime = runtime
    self.languages = languages
    self.dateAdded = dateAdded
  }
}

/// A search result from Radarr's TMDb lookup — a film that may or may not
/// already be in the library.
public struct RadarrMovieLookup: Identifiable, Equatable, Sendable {
  /// TMDb id, because a film that isn't in the library has no Radarr id (the
  /// API sends `0`).
  public var id: Int { tmdbID }
  public let tmdbID: Int
  public let title: String
  public let year: Int?
  public let overview: String?
  public let posterURL: URL?
  public let studio: String?
  public let runtimeMinutes: Int?
  /// Radarr's own id when this film is already in the library, `nil` when it
  /// isn't — which is what the add screen shows as "Already added".
  public let existingMovieID: Int?

  public init(
    tmdbID: Int, title: String, year: Int?, overview: String?, posterURL: URL?,
    studio: String?, runtimeMinutes: Int?, existingMovieID: Int?
  ) {
    self.tmdbID = tmdbID
    self.title = title
    self.year = year
    self.overview = overview
    self.posterURL = posterURL
    self.studio = studio
    self.runtimeMinutes = runtimeMinutes
    self.existingMovieID = existingMovieID
  }

  public var isAlreadyAdded: Bool { existingMovieID != nil }
}

/// What the add-movie sheet collects.
public struct RadarrAddMovieRequest: Equatable, Sendable {
  public let lookup: RadarrMovieLookup
  public let qualityProfileID: Int
  public let rootFolderPath: String
  public let minimumAvailability: MovieAvailability
  public let isMonitored: Bool
  public let searchOnAdd: Bool
  public let tagIDs: [Int]

  public init(
    lookup: RadarrMovieLookup, qualityProfileID: Int, rootFolderPath: String,
    minimumAvailability: MovieAvailability = .released, isMonitored: Bool = true,
    searchOnAdd: Bool = true, tagIDs: [Int] = []
  ) {
    self.lookup = lookup
    self.qualityProfileID = qualityProfileID
    self.rootFolderPath = rootFolderPath
    self.minimumAvailability = minimumAvailability
    self.isMonitored = isMonitored
    self.searchOnAdd = searchOnAdd
    self.tagIDs = tagIDs
  }
}

/// The editable fields of a movie already in the library. Only what the edit
/// sheet offers — everything else on `RadarrMovie` is Radarr's to own.
public struct RadarrMovieEdit: Equatable, Sendable {
  public var isMonitored: Bool
  public var qualityProfileID: Int
  public var minimumAvailability: MovieAvailability
  public var rootFolderPath: String?
  public var tagIDs: [Int]

  public init(
    isMonitored: Bool, qualityProfileID: Int, minimumAvailability: MovieAvailability,
    rootFolderPath: String?, tagIDs: [Int]
  ) {
    self.isMonitored = isMonitored
    self.qualityProfileID = qualityProfileID
    self.minimumAvailability = minimumAvailability
    self.rootFolderPath = rootFolderPath
    self.tagIDs = tagIDs
  }

  public init(movie: RadarrMovie) {
    self.init(
      isMonitored: movie.isMonitored,
      qualityProfileID: movie.qualityProfileID,
      minimumAvailability: movie.minimumAvailability,
      rootFolderPath: movie.rootFolderPath,
      tagIDs: movie.tagIDs
    )
  }
}
