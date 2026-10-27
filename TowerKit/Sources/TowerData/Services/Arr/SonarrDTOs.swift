import Foundation
import TowerCore

// Sonarr's wire shapes. Same rules as `RadarrDTOs`: internal to `TowerData`,
// defensive decoding, and a `Codable` round trip because Sonarr's PUT merges a
// fixed set of fields onto the stored record too.

struct SeriesDTO: Codable, Sendable {
  let id: Int
  let title: String?
  let sortTitle: String?
  let year: Int?
  let overview: String?
  let network: String?
  let runtime: Int?
  let certification: String?
  let genres: [String]?
  let status: String?
  let seriesType: String?
  let monitored: Bool?
  let seasonFolder: Bool?
  let qualityProfileId: Int?
  let path: String?
  let rootFolderPath: String?
  let folder: String?
  let tags: [Int]?
  let added: Date?
  let nextAiring: Date?
  let previousAiring: Date?
  let images: [MediaCoverDTO]?
  let tvdbId: Int?
  let imdbId: String?
  let titleSlug: String?
  let seasons: [SeasonDTO]?
  let statistics: SeriesStatisticsDTO?

  /// Everything Sonarr sent that this type doesn't model — see `MovieDTO` for
  /// why the round trip makes this load-bearing rather than tidy.
  let unknownFields: [String: AnyJSON]

  enum CodingKeys: String, CodingKey, CaseIterable {
    case id, title, sortTitle, year, overview, network, runtime, certification, genres
    case status, seriesType, monitored, seasonFolder, qualityProfileId, path, rootFolderPath
    case folder, tags, added, nextAiring, previousAiring, images, tvdbId, imdbId, titleSlug
    case seasons, statistics
  }

  init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    // Absent means the same as 0 — not in the library. See `MovieDTO`'s
    // decoder for the version history behind this.
    id = try container.decodeIfPresent(Int.self, forKey: .id) ?? 0
    title = try container.decodeIfPresent(String.self, forKey: .title)
    sortTitle = try container.decodeIfPresent(String.self, forKey: .sortTitle)
    year = try container.decodeIfPresent(Int.self, forKey: .year)
    overview = try container.decodeIfPresent(String.self, forKey: .overview)
    network = try container.decodeIfPresent(String.self, forKey: .network)
    runtime = try container.decodeIfPresent(Int.self, forKey: .runtime)
    certification = try container.decodeIfPresent(String.self, forKey: .certification)
    genres = try container.decodeIfPresent([String].self, forKey: .genres)
    status = try container.decodeIfPresent(String.self, forKey: .status)
    seriesType = try container.decodeIfPresent(String.self, forKey: .seriesType)
    monitored = try container.decodeIfPresent(Bool.self, forKey: .monitored)
    seasonFolder = try container.decodeIfPresent(Bool.self, forKey: .seasonFolder)
    qualityProfileId = try container.decodeIfPresent(Int.self, forKey: .qualityProfileId)
    path = try container.decodeIfPresent(String.self, forKey: .path)
    rootFolderPath = try container.decodeIfPresent(String.self, forKey: .rootFolderPath)
    folder = try container.decodeIfPresent(String.self, forKey: .folder)
    tags = try container.decodeIfPresent([Int].self, forKey: .tags)
    added = try container.decodeIfPresent(Date.self, forKey: .added)
    nextAiring = try container.decodeIfPresent(Date.self, forKey: .nextAiring)
    previousAiring = try container.decodeIfPresent(Date.self, forKey: .previousAiring)
    images = try container.decodeIfPresent([MediaCoverDTO].self, forKey: .images)
    tvdbId = try container.decodeIfPresent(Int.self, forKey: .tvdbId)
    imdbId = try container.decodeIfPresent(String.self, forKey: .imdbId)
    titleSlug = try container.decodeIfPresent(String.self, forKey: .titleSlug)
    seasons = try container.decodeIfPresent([SeasonDTO].self, forKey: .seasons)
    statistics = try container.decodeIfPresent(SeriesStatisticsDTO.self, forKey: .statistics)

    let everything = try decoder.singleValueContainer().decode([String: AnyJSON].self)
    let known = Set(CodingKeys.allCases.map(\.rawValue))
    unknownFields = everything.filter { !known.contains($0.key) }
  }

  func encode(to encoder: any Encoder) throws {
    var payload = unknownFields
    // Omitted rather than sent as 0, as in `MovieDTO.encode`.
    if id != 0 { payload["id"] = .int(id) }
    payload["title"] = title.map(AnyJSON.string) ?? .null
    payload["sortTitle"] = sortTitle.map(AnyJSON.string) ?? .null
    payload["year"] = year.map(AnyJSON.int) ?? .null
    payload["overview"] = overview.map(AnyJSON.string) ?? .null
    payload["network"] = network.map(AnyJSON.string) ?? .null
    payload["runtime"] = runtime.map(AnyJSON.int) ?? .null
    payload["certification"] = certification.map(AnyJSON.string) ?? .null
    payload["genres"] = .array((genres ?? []).map(AnyJSON.string))
    payload["status"] = status.map(AnyJSON.string) ?? .null
    payload["seriesType"] = seriesType.map(AnyJSON.string) ?? .null
    payload["monitored"] = .bool(monitored ?? false)
    payload["seasonFolder"] = .bool(seasonFolder ?? true)
    payload["qualityProfileId"] = qualityProfileId.map(AnyJSON.int) ?? .null
    payload["path"] = path.map(AnyJSON.string) ?? .null
    payload["rootFolderPath"] = rootFolderPath.map(AnyJSON.string) ?? .null
    payload["tags"] = .array((tags ?? []).map(AnyJSON.int))
    payload["tvdbId"] = tvdbId.map(AnyJSON.int) ?? .null
    payload["imdbId"] = imdbId.map(AnyJSON.string) ?? .null
    payload["titleSlug"] = titleSlug.map(AnyJSON.string) ?? .null
    payload["seasons"] = .array((seasons ?? []).map(\.json))
    var container = encoder.singleValueContainer()
    try container.encode(payload)
  }

  var domain: SonarrSeries {
    SonarrSeries(
      id: id,
      tvdbID: tvdbId,
      imdbID: imdbId,
      title: title ?? "Untitled",
      sortTitle: sortTitle ?? title ?? "",
      year: year == 0 ? nil : year,
      overview: overview?.isEmpty == true ? nil : overview,
      network: network?.isEmpty == true ? nil : network,
      runtimeMinutes: (runtime ?? 0) == 0 ? nil : runtime,
      certification: certification?.isEmpty == true ? nil : certification,
      genres: genres ?? [],
      status: SeriesStatus(apiValue: status),
      seriesType: SeriesType(apiValue: seriesType),
      isMonitored: monitored ?? false,
      usesSeasonFolders: seasonFolder ?? true,
      qualityProfileID: qualityProfileId ?? 0,
      path: path,
      rootFolderPath: rootFolderPath ?? derivedRootFolderPath,
      tagIDs: tags ?? [],
      added: added,
      nextAiring: nextAiring,
      previousAiring: previousAiring,
      posterURL: imageURL("poster"),
      fanartURL: imageURL("fanart"),
      // Season order is not guaranteed by the API, and specials (season 0) come
      // back interleaved often enough to matter.
      seasons: (seasons ?? []).map(\.domain).sorted { $0.seasonNumber < $1.seasonNumber },
      statistics: statistics?.domain
    )
  }

  var lookupDomain: SonarrSeriesLookup {
    SonarrSeriesLookup(
      tvdbID: tvdbId ?? 0,
      title: title ?? "Untitled",
      year: year == 0 ? nil : year,
      overview: overview?.isEmpty == true ? nil : overview,
      network: network?.isEmpty == true ? nil : network,
      status: SeriesStatus(apiValue: status),
      posterURL: imageURL("poster"),
      existingSeriesID: id == 0 ? nil : id
    )
  }

  func applying(_ edit: SonarrSeriesEdit) -> SeriesDTO {
    SeriesDTO(
      base: self,
      monitored: edit.isMonitored,
      qualityProfileId: edit.qualityProfileID,
      seriesType: edit.seriesType.rawValue,
      seasonFolder: edit.usesSeasonFolders,
      rootFolderPath: edit.rootFolderPath ?? rootFolderPath,
      tags: edit.tagIDs,
      seasons: seasons
    )
  }

  /// One season's monitored flag flipped, everything else untouched — there is
  /// no per-season endpoint, so this is how season monitoring is set.
  func settingSeason(_ seasonNumber: Int, monitored: Bool) -> SeriesDTO {
    let updated = (seasons ?? []).map { season in
      season.seasonNumber == seasonNumber ? season.setting(monitored: monitored) : season
    }
    return SeriesDTO(
      base: self,
      monitored: self.monitored ?? false,
      qualityProfileId: qualityProfileId ?? 0,
      seriesType: seriesType ?? SeriesType.standard.rawValue,
      seasonFolder: seasonFolder ?? true,
      rootFolderPath: rootFolderPath,
      tags: tags ?? [],
      seasons: updated
    )
  }

  private func imageURL(_ type: String) -> URL? {
    // Absolute `remoteUrl` only — see `MediaCoverDTO` in RadarrDTOs.
    OpenableURL.from(images?.first { $0.coverType == type }?.remoteUrl)
  }

  private var derivedRootFolderPath: String? {
    guard let path else { return nil }
    let leaf = folder ?? path.split(separator: "/").last.map(String.init) ?? ""
    guard !leaf.isEmpty, path.hasSuffix(leaf) else { return nil }
    let trimmed = String(path.dropLast(leaf.count))
    return trimmed.hasSuffix("/") && trimmed.count > 1 ? String(trimmed.dropLast()) : trimmed
  }
}

extension SeriesDTO {
  fileprivate init(
    base: SeriesDTO,
    monitored: Bool,
    qualityProfileId: Int,
    seriesType: String,
    seasonFolder: Bool,
    rootFolderPath: String?,
    tags: [Int],
    seasons: [SeasonDTO]?
  ) {
    self.id = base.id
    self.title = base.title
    self.sortTitle = base.sortTitle
    self.year = base.year
    self.overview = base.overview
    self.network = base.network
    self.runtime = base.runtime
    self.certification = base.certification
    self.genres = base.genres
    self.status = base.status
    self.seriesType = seriesType
    self.monitored = monitored
    self.seasonFolder = seasonFolder
    self.qualityProfileId = qualityProfileId
    self.path = base.path
    self.rootFolderPath = rootFolderPath
    self.folder = base.folder
    self.tags = tags
    self.added = base.added
    self.nextAiring = base.nextAiring
    self.previousAiring = base.previousAiring
    self.images = base.images
    self.tvdbId = base.tvdbId
    self.imdbId = base.imdbId
    self.titleSlug = base.titleSlug
    self.seasons = seasons
    self.statistics = base.statistics
    self.unknownFields = base.unknownFields
  }
}

struct SeasonDTO: Codable, Sendable {
  let seasonNumber: Int
  let monitored: Bool?
  let statistics: SeasonStatisticsDTO?

  var domain: SonarrSeason {
    SonarrSeason(
      seasonNumber: seasonNumber,
      isMonitored: monitored ?? false,
      episodeFileCount: statistics?.episodeFileCount ?? 0,
      episodeCount: statistics?.episodeCount ?? 0,
      totalEpisodeCount: statistics?.totalEpisodeCount ?? 0,
      sizeOnDiskBytes: statistics?.sizeOnDisk ?? 0,
      nextAiring: statistics?.nextAiring
    )
  }

  func setting(monitored: Bool) -> SeasonDTO {
    SeasonDTO(seasonNumber: seasonNumber, monitored: monitored, statistics: statistics)
  }

  /// Sonarr rejects a series PUT whose seasons lack `monitored`, so the encoded
  /// form always carries it.
  var json: AnyJSON {
    .object([
      "seasonNumber": .int(seasonNumber),
      "monitored": .bool(monitored ?? false),
    ])
  }
}

struct SeasonStatisticsDTO: Codable, Sendable {
  let episodeFileCount: Int?
  let episodeCount: Int?
  let totalEpisodeCount: Int?
  let sizeOnDisk: Int64?
  let nextAiring: Date?
}

struct SeriesStatisticsDTO: Codable, Sendable {
  let seasonCount: Int?
  let episodeFileCount: Int?
  let episodeCount: Int?
  let totalEpisodeCount: Int?
  let sizeOnDisk: Int64?

  var domain: SonarrSeriesStatistics {
    SonarrSeriesStatistics(
      seasonCount: seasonCount ?? 0,
      episodeFileCount: episodeFileCount ?? 0,
      episodeCount: episodeCount ?? 0,
      totalEpisodeCount: totalEpisodeCount ?? 0,
      sizeOnDiskBytes: sizeOnDisk ?? 0
    )
  }
}

struct EpisodeDTO: Decodable, Sendable {
  let id: Int
  let seriesId: Int
  let seasonNumber: Int
  let episodeNumber: Int
  let title: String?
  let overview: String?
  let airDateUtc: Date?
  let runtime: Int?
  let hasFile: Bool?
  let monitored: Bool?
  let episodeFile: EpisodeFileDTO?

  var domain: SonarrEpisode {
    SonarrEpisode(
      id: id,
      seriesID: seriesId,
      seasonNumber: seasonNumber,
      episodeNumber: episodeNumber,
      // Unaired episodes routinely have no title yet; "TBA" is what Sonarr's
      // own UI shows, and a blank row reads as a broken screen.
      title: title?.isEmpty == false ? title! : "TBA",
      overview: overview?.isEmpty == true ? nil : overview,
      airDate: airDateUtc,
      runtimeMinutes: (runtime ?? 0) == 0 ? nil : runtime,
      hasFile: hasFile ?? (episodeFile != nil),
      isMonitored: monitored ?? false,
      file: episodeFile?.domain
    )
  }
}

struct EpisodeFileDTO: Decodable, Sendable {
  let id: Int
  let relativePath: String?
  let size: Int64?
  let dateAdded: Date?
  let releaseGroup: String?
  let quality: QualityModelDTO?
  let mediaInfo: MovieFileDTO.MediaInfoDTO?

  var domain: SonarrEpisodeFile {
    SonarrEpisodeFile(
      id: id,
      relativePath: relativePath,
      sizeBytes: size ?? 0,
      quality: quality?.quality?.name,
      releaseGroup: releaseGroup,
      videoCodec: mediaInfo?.videoCodec,
      audioCodec: mediaInfo?.audioCodec,
      resolution: mediaInfo?.resolution,
      languages: (mediaInfo?.audioLanguages ?? "")
        .split(separator: "/")
        .map { $0.trimmingCharacters(in: .whitespaces) }
        .filter { !$0.isEmpty },
      dateAdded: dateAdded
    )
  }
}

struct AddSeriesBody: Encodable, Sendable {
  struct AddOptions: Encodable, Sendable {
    let monitor: String
    let searchForMissingEpisodes: Bool
    let searchForCutoffUnmetEpisodes: Bool
  }

  let tvdbId: Int
  let title: String
  let qualityProfileId: Int
  let rootFolderPath: String
  let seriesType: String
  let seasonFolder: Bool
  let monitored: Bool
  let tags: [Int]
  let addOptions: AddOptions

  init(request: SonarrAddSeriesRequest) {
    tvdbId = request.lookup.tvdbID
    title = request.lookup.title
    qualityProfileId = request.qualityProfileID
    rootFolderPath = request.rootFolderPath
    seriesType = request.seriesType.rawValue
    seasonFolder = request.usesSeasonFolders
    // "Monitor nothing" and "monitor the series" are different questions from
    // *which* episodes to monitor; a series added with `.none` is still a
    // monitored series with no monitored episodes.
    monitored = request.monitorOption != .none
    tags = request.tagIDs
    addOptions = AddOptions(
      monitor: request.monitorOption.rawValue,
      searchForMissingEpisodes: request.searchOnAdd,
      searchForCutoffUnmetEpisodes: false)
  }
}

struct EpisodeMonitorBody: Encodable, Sendable {
  let episodeIds: [Int]
  let monitored: Bool
}
