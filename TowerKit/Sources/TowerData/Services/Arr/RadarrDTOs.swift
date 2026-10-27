import Foundation
import TowerCore

// Radarr's wire shapes. Internal to `TowerData`, like every other DTO here.

/// `MovieResource`, decoded *and* re-encoded.
///
/// **Both directions on one type, deliberately.** Radarr's `PUT /movie/{id}`
/// merges a fixed set of fields onto the stored record, and a field of that
/// set missing from the body is reset. So an edit round-trips — fetch the
/// resource, change the handful of fields the user touched, send it back — and
/// that only works if the decode preserves what it doesn't understand well
/// enough to send it again.
///
/// `unknownFields` carries the ones Tower doesn't model (`addOptions`) and any
/// added later; modelled read-only keys that `encode` omits are not in that
/// set. Anything not modelled is captured verbatim and merged back on encode.
struct MovieDTO: Codable, Sendable {
  /// **0 means "not in the library"**, and so does an absent `id` — see the
  /// decoder. Everything downstream reads the zero, never the absence.
  let id: Int
  let title: String?
  let sortTitle: String?
  let originalTitle: String?
  let year: Int?
  let overview: String?
  let studio: String?
  let runtime: Int?
  let certification: String?
  let genres: [String]?
  let status: String?
  let minimumAvailability: String?
  let monitored: Bool?
  let hasFile: Bool?
  let isAvailable: Bool?
  let sizeOnDisk: Int64?
  let qualityProfileId: Int?
  let path: String?
  let rootFolderPath: String?
  let folderName: String?
  let tags: [Int]?
  let added: Date?
  let inCinemas: Date?
  let digitalRelease: Date?
  let physicalRelease: Date?
  let images: [MediaCoverDTO]?
  let tmdbId: Int?
  let imdbId: String?
  let movieFile: MovieFileDTO?
  let titleSlug: String?

  /// Everything Radarr sent that this type doesn't model, kept so an edit can
  /// hand it back untouched.
  let unknownFields: [String: AnyJSON]

  enum CodingKeys: String, CodingKey, CaseIterable {
    case id, title, sortTitle, originalTitle, year, overview, studio, runtime, certification
    case genres, status, minimumAvailability, monitored, hasFile, isAvailable, sizeOnDisk
    case qualityProfileId, path, rootFolderPath, folderName, tags, added, inCinemas
    case digitalRelease, physicalRelease, images, tmdbId, imdbId, movieFile, titleSlug
  }

  init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    // **Not `decode`.** `movie/lookup` answers with resources for films
    // that are not in the library, and Radarr 6 leaves `id` out of those
    // entirely where earlier versions sent 0. Requiring it fails the whole
    // array, so one unlibraried result breaks every search with
    // "Missing field 'id'". Absent and 0 mean the same thing here, and the
    // sentinel is what `lookupDomain` already reads.
    id = try container.decodeIfPresent(Int.self, forKey: .id) ?? 0
    title = try container.decodeIfPresent(String.self, forKey: .title)
    sortTitle = try container.decodeIfPresent(String.self, forKey: .sortTitle)
    originalTitle = try container.decodeIfPresent(String.self, forKey: .originalTitle)
    year = try container.decodeIfPresent(Int.self, forKey: .year)
    overview = try container.decodeIfPresent(String.self, forKey: .overview)
    studio = try container.decodeIfPresent(String.self, forKey: .studio)
    runtime = try container.decodeIfPresent(Int.self, forKey: .runtime)
    certification = try container.decodeIfPresent(String.self, forKey: .certification)
    genres = try container.decodeIfPresent([String].self, forKey: .genres)
    status = try container.decodeIfPresent(String.self, forKey: .status)
    minimumAvailability = try container.decodeIfPresent(String.self, forKey: .minimumAvailability)
    monitored = try container.decodeIfPresent(Bool.self, forKey: .monitored)
    hasFile = try container.decodeIfPresent(Bool.self, forKey: .hasFile)
    isAvailable = try container.decodeIfPresent(Bool.self, forKey: .isAvailable)
    sizeOnDisk = try container.decodeIfPresent(Int64.self, forKey: .sizeOnDisk)
    qualityProfileId = try container.decodeIfPresent(Int.self, forKey: .qualityProfileId)
    path = try container.decodeIfPresent(String.self, forKey: .path)
    rootFolderPath = try container.decodeIfPresent(String.self, forKey: .rootFolderPath)
    folderName = try container.decodeIfPresent(String.self, forKey: .folderName)
    tags = try container.decodeIfPresent([Int].self, forKey: .tags)
    added = try container.decodeIfPresent(Date.self, forKey: .added)
    inCinemas = try container.decodeIfPresent(Date.self, forKey: .inCinemas)
    digitalRelease = try container.decodeIfPresent(Date.self, forKey: .digitalRelease)
    physicalRelease = try container.decodeIfPresent(Date.self, forKey: .physicalRelease)
    images = try container.decodeIfPresent([MediaCoverDTO].self, forKey: .images)
    tmdbId = try container.decodeIfPresent(Int.self, forKey: .tmdbId)
    imdbId = try container.decodeIfPresent(String.self, forKey: .imdbId)
    movieFile = try container.decodeIfPresent(MovieFileDTO.self, forKey: .movieFile)
    titleSlug = try container.decodeIfPresent(String.self, forKey: .titleSlug)

    let everything = try decoder.singleValueContainer().decode([String: AnyJSON].self)
    let known = Set(CodingKeys.allCases.map(\.rawValue))
    unknownFields = everything.filter { !known.contains($0.key) }
  }

  func encode(to encoder: any Encoder) throws {
    // Start from what Radarr sent, then overwrite the modelled fields — so
    // anything this type doesn't know about survives the round trip.
    var payload = unknownFields
    // A synthesised 0 is not an id, and Radarr reads `"id": 0` as one. Omit it
    // so a resource that arrived without one goes back without one; the edit
    // round trip always has a real id, so this only affects lookup results.
    if id != 0 { payload["id"] = .int(id) }
    payload["title"] = title.map(AnyJSON.string) ?? .null
    payload["sortTitle"] = sortTitle.map(AnyJSON.string) ?? .null
    payload["originalTitle"] = originalTitle.map(AnyJSON.string) ?? .null
    payload["year"] = year.map(AnyJSON.int) ?? .null
    payload["overview"] = overview.map(AnyJSON.string) ?? .null
    payload["studio"] = studio.map(AnyJSON.string) ?? .null
    payload["runtime"] = runtime.map(AnyJSON.int) ?? .null
    payload["certification"] = certification.map(AnyJSON.string) ?? .null
    payload["genres"] = .array((genres ?? []).map(AnyJSON.string))
    payload["status"] = status.map(AnyJSON.string) ?? .null
    payload["minimumAvailability"] = minimumAvailability.map(AnyJSON.string) ?? .null
    payload["monitored"] = .bool(monitored ?? false)
    payload["hasFile"] = .bool(hasFile ?? false)
    payload["isAvailable"] = .bool(isAvailable ?? false)
    payload["sizeOnDisk"] = sizeOnDisk.map { AnyJSON.int(Int($0)) } ?? .null
    payload["qualityProfileId"] = qualityProfileId.map(AnyJSON.int) ?? .null
    payload["path"] = path.map(AnyJSON.string) ?? .null
    payload["rootFolderPath"] = rootFolderPath.map(AnyJSON.string) ?? .null
    payload["tags"] = .array((tags ?? []).map(AnyJSON.int))
    payload["tmdbId"] = tmdbId.map(AnyJSON.int) ?? .null
    payload["imdbId"] = imdbId.map(AnyJSON.string) ?? .null
    payload["titleSlug"] = titleSlug.map(AnyJSON.string) ?? .null

    var container = encoder.singleValueContainer()
    try container.encode(payload)
  }

  /// The library/detail domain value.
  var domain: RadarrMovie {
    RadarrMovie(
      id: id,
      tmdbID: tmdbId,
      imdbID: imdbId,
      title: title ?? originalTitle ?? "Untitled",
      // Radarr sends `sortTitle` for everything in the library, but a lookup
      // result may not have one — falling back to the title keeps the list from
      // collapsing every unsorted row to the top.
      sortTitle: sortTitle ?? title ?? "",
      year: year == 0 ? nil : year,
      overview: overview?.isEmpty == true ? nil : overview,
      studio: studio?.isEmpty == true ? nil : studio,
      runtimeMinutes: (runtime ?? 0) == 0 ? nil : runtime,
      certification: certification?.isEmpty == true ? nil : certification,
      genres: genres ?? [],
      status: MovieAvailability(apiValue: status),
      minimumAvailability: MovieAvailability(apiValue: minimumAvailability),
      isMonitored: monitored ?? false,
      hasFile: hasFile ?? (movieFile != nil),
      isAvailable: isAvailable ?? false,
      // Multi-terabyte libraries: this is `Int64` the whole way down, and the
      // fixture carries a 4K remux to prove a real figure survives.
      sizeOnDiskBytes: sizeOnDisk ?? movieFile?.size ?? 0,
      qualityProfileID: qualityProfileId ?? 0,
      path: path,
      // `rootFolderPath` is absent on the list endpoint but derivable: the path
      // minus the movie's own folder. Without this the edit sheet opens with no
      // root folder selected for every movie in the library.
      rootFolderPath: rootFolderPath ?? derivedRootFolderPath,
      tagIDs: tags ?? [],
      added: added,
      inCinemas: inCinemas,
      digitalRelease: digitalRelease,
      physicalRelease: physicalRelease,
      posterURL: imageURL(.poster),
      fanartURL: imageURL(.fanart),
      file: movieFile?.domain
    )
  }

  /// The add-search domain value. A lookup result's `id` is `0` until the film
  /// is in the library, which is exactly how "already added" is detected.
  var lookupDomain: RadarrMovieLookup {
    RadarrMovieLookup(
      tmdbID: tmdbId ?? 0,
      title: title ?? "Untitled",
      year: year == 0 ? nil : year,
      overview: overview?.isEmpty == true ? nil : overview,
      posterURL: imageURL(.poster),
      studio: studio?.isEmpty == true ? nil : studio,
      runtimeMinutes: (runtime ?? 0) == 0 ? nil : runtime,
      existingMovieID: id == 0 ? nil : id
    )
  }

  /// This resource with the edit applied, ready to PUT back.
  func applying(_ edit: RadarrMovieEdit) -> MovieDTO {
    MovieDTO(
      base: self,
      monitored: edit.isMonitored,
      qualityProfileId: edit.qualityProfileID,
      minimumAvailability: edit.minimumAvailability.rawValue,
      rootFolderPath: edit.rootFolderPath ?? rootFolderPath,
      tags: edit.tagIDs,
      unknownFields: unknownFields
    )
  }

  private enum Cover: String {
    case poster, fanart
  }

  private func imageURL(_ type: Cover) -> URL? {
    guard let image = images?.first(where: { $0.coverType == type.rawValue }) else { return nil }
    // `remoteUrl` is the absolute TMDb address. The *arrs also send a
    // server-relative `url`, which needs the API key to fetch and an
    // `AsyncImage` won't send it, so Tower does not use it. Requiring a scheme
    // here keeps the two from being confused, and a scheme-less value yields no
    // image rather than a permanently blank one.
    return OpenableURL.from(image.remoteUrl)
  }

  /// `/movies/Some Film (2024)` → `/movies`.
  private var derivedRootFolderPath: String? {
    guard let path, let folderName = folderName ?? path.split(separator: "/").last.map(String.init)
    else { return nil }
    let leaf = folderName.split(separator: "/").last.map(String.init) ?? folderName
    guard path.hasSuffix(leaf) else { return nil }
    let trimmed = String(path.dropLast(leaf.count))
    return trimmed.hasSuffix("/") && trimmed.count > 1 ? String(trimmed.dropLast()) : trimmed
  }
}

extension MovieDTO {
  /// Memberwise-with-overrides, used by `applying(_:)`.
  fileprivate init(
    base: MovieDTO,
    monitored: Bool,
    qualityProfileId: Int,
    minimumAvailability: String,
    rootFolderPath: String?,
    tags: [Int],
    unknownFields: [String: AnyJSON]
  ) {
    self.id = base.id
    self.title = base.title
    self.sortTitle = base.sortTitle
    self.originalTitle = base.originalTitle
    self.year = base.year
    self.overview = base.overview
    self.studio = base.studio
    self.runtime = base.runtime
    self.certification = base.certification
    self.genres = base.genres
    self.status = base.status
    self.minimumAvailability = minimumAvailability
    self.monitored = monitored
    self.hasFile = base.hasFile
    self.isAvailable = base.isAvailable
    self.sizeOnDisk = base.sizeOnDisk
    self.qualityProfileId = qualityProfileId
    self.path = base.path
    self.rootFolderPath = rootFolderPath
    self.folderName = base.folderName
    self.tags = tags
    self.added = base.added
    self.inCinemas = base.inCinemas
    self.digitalRelease = base.digitalRelease
    self.physicalRelease = base.physicalRelease
    self.images = base.images
    self.tmdbId = base.tmdbId
    self.imdbId = base.imdbId
    self.movieFile = base.movieFile
    self.titleSlug = base.titleSlug
    self.unknownFields = unknownFields
  }
}

struct MediaCoverDTO: Decodable, Sendable {
  let coverType: String?
  let url: String?
  let remoteUrl: String?
}

struct MovieFileDTO: Decodable, Sendable {
  struct MediaInfoDTO: Decodable, Sendable {
    let videoCodec: String?
    let audioCodec: String?
    let audioChannels: Double?
    let resolution: String?
    let runTime: String?
    let audioLanguages: String?
  }

  let id: Int
  let relativePath: String?
  let size: Int64?
  let dateAdded: Date?
  let releaseGroup: String?
  let quality: QualityModelDTO?
  let mediaInfo: MediaInfoDTO?

  var domain: RadarrMovieFile {
    RadarrMovieFile(
      id: id,
      relativePath: relativePath,
      sizeBytes: size ?? 0,
      quality: quality?.quality?.name,
      releaseGroup: releaseGroup,
      videoCodec: mediaInfo?.videoCodec,
      audioCodec: mediaInfo?.audioCodec,
      audioChannels: mediaInfo?.audioChannels,
      resolution: mediaInfo?.resolution,
      runtime: mediaInfo?.runTime,
      // The API sends these as one `/`-joined string, which is not something to
      // put in front of a user.
      languages: (mediaInfo?.audioLanguages ?? "")
        .split(separator: "/")
        .map { $0.trimmingCharacters(in: .whitespaces) }
        .filter { !$0.isEmpty },
      dateAdded: dateAdded
    )
  }
}

struct ReleaseDTO: Decodable, Sendable {
  let guid: String?
  let title: String?
  let indexer: String?
  let indexerId: Int?
  let quality: QualityModelDTO?
  let size: Int64?
  let `protocol`: String?
  let publishDate: Date?
  let ageHours: Double?
  let approved: Bool?
  let rejected: Bool?
  let rejections: [String]?

  var domain: ArrRelease {
    ArrRelease(
      id: guid ?? UUID().uuidString,
      title: title ?? "Untitled release",
      indexer: indexer,
      indexerID: indexerId,
      quality: quality?.quality?.name,
      sizeBytes: size ?? 0,
      downloadProtocol: ArrDownloadProtocol(apiValue: `protocol`),
      publishDate: publishDate,
      ageHours: ageHours,
      // `approved` and `rejected` are both sent and can disagree on older
      // versions; a release with rejections is not approved whatever the flag
      // says, which is the safer reading for a list the user picks from.
      isApproved: (approved ?? false) && !(rejected ?? false) && (rejections ?? []).isEmpty,
      rejections: rejections ?? []
    )
  }
}

/// The add-movie POST body. Only what Radarr needs — it fills in the rest from
/// TMDb itself.
struct AddMovieBody: Encodable, Sendable {
  struct AddOptions: Encodable, Sendable {
    let searchForMovie: Bool
    let monitor: String
  }

  let tmdbId: Int
  let title: String
  let year: Int?
  let qualityProfileId: Int
  let rootFolderPath: String
  let minimumAvailability: String
  let monitored: Bool
  let tags: [Int]
  let addOptions: AddOptions

  init(request: RadarrAddMovieRequest) {
    tmdbId = request.lookup.tmdbID
    title = request.lookup.title
    year = request.lookup.year
    qualityProfileId = request.qualityProfileID
    rootFolderPath = request.rootFolderPath
    minimumAvailability = request.minimumAvailability.rawValue
    monitored = request.isMonitored
    tags = request.tagIDs
    addOptions = AddOptions(
      searchForMovie: request.searchOnAdd,
      monitor: request.isMonitored ? "movieOnly" : "none")
  }
}

struct GrabReleaseBody: Encodable, Sendable {
  let guid: String
  let indexerId: Int
}

/// Just enough JSON to carry fields this app doesn't model through a decode and
/// back out again — see `MovieDTO`'s note on why the round trip needs it.
enum AnyJSON: Codable, Sendable, Equatable {
  case null
  case bool(Bool)
  case int(Int)
  case double(Double)
  case string(String)
  case array([AnyJSON])
  case object([String: AnyJSON])

  init(from decoder: any Decoder) throws {
    let container = try decoder.singleValueContainer()
    if container.decodeNil() {
      self = .null
    } else if let value = try? container.decode(Bool.self) {
      self = .bool(value)
    } else if let value = try? container.decode(Int.self) {
      self = .int(value)
    } else if let value = try? container.decode(Double.self) {
      self = .double(value)
    } else if let value = try? container.decode(String.self) {
      self = .string(value)
    } else if let value = try? container.decode([AnyJSON].self) {
      self = .array(value)
    } else {
      self = .object(try container.decode([String: AnyJSON].self))
    }
  }

  func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    switch self {
    case .null: try container.encodeNil()
    case .bool(let value): try container.encode(value)
    case .int(let value): try container.encode(value)
    case .double(let value): try container.encode(value)
    case .string(let value): try container.encode(value)
    case .array(let value): try container.encode(value)
    case .object(let value): try container.encode(value)
    }
  }
}
