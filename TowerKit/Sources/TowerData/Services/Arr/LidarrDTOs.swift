import Foundation
import TowerCore

// Lidarr's wire types. `internal`, like every other service's DTOs.
//
// Lidarr is an *arr, so the shared surface — queue, calendar, history, health,
// profiles, root folders, tags — is `ArrClientCore`'s and does not reappear
// here. What is Lidarr's own is the artist → album → track hierarchy and the
// **metadata profile**, a second profile axis with no Radarr or Sonarr
// equivalent.

/// `ArtistResource`, decoded *and* re-encoded.
///
/// An edit round-trips: fetch the resource, change the fields the user
/// touched, send it back. Lidarr's `PUT` merges a fixed set of fields onto the
/// stored record, and anything in that set that is missing from the body is
/// reset to the type's default — `monitorNewItems` falls back to `all`.
/// `unknownFields` carries the ones Tower doesn't model (`monitorNewItems`
/// among them) and any added later; modelled read-only keys that `encode`
/// omits are not in that set.
struct LidarrArtistDTO: Codable, Sendable {
  /// **Optional on the wire.** `artist/lookup` answers with artist
  /// resources for artists that are not in the library, and newer *arr builds
  /// leave `id` out of those entirely where older ones sent 0. Requiring it
  /// fails the whole array, so one unlibraried hit breaks every search with
  /// "Missing field 'id'".
  ///
  /// Read `libraryID` rather than this, so the two spellings of "not in the
  /// library" are collapsed in exactly one place.
  let id: Int?
  let artistName: String?
  let sortName: String?
  let foreignArtistId: String?
  let overview: String?
  let artistType: String?
  let disambiguation: String?
  let status: String?
  var monitored: Bool?
  var qualityProfileId: Int?
  var metadataProfileId: Int?
  let path: String?
  var rootFolderPath: String?
  let genres: [String]?
  var tags: [Int]?
  let added: Date?
  let images: [MediaCoverDTO]?
  let statistics: ArtistStatisticsDTO?

  /// Everything Lidarr sent that this type doesn't model, kept so an edit can
  /// hand it back untouched.
  let unknownFields: [String: AnyJSON]

  enum CodingKeys: String, CodingKey, CaseIterable {
    case id, artistName, sortName, foreignArtistId, overview, artistType, disambiguation
    case status, monitored, qualityProfileId, metadataProfileId, path, rootFolderPath
    case genres, tags, added, images, statistics
  }

  init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decodeIfPresent(Int.self, forKey: .id)
    artistName = try container.decodeIfPresent(String.self, forKey: .artistName)
    sortName = try container.decodeIfPresent(String.self, forKey: .sortName)
    foreignArtistId = try container.decodeIfPresent(String.self, forKey: .foreignArtistId)
    overview = try container.decodeIfPresent(String.self, forKey: .overview)
    artistType = try container.decodeIfPresent(String.self, forKey: .artistType)
    disambiguation = try container.decodeIfPresent(String.self, forKey: .disambiguation)
    status = try container.decodeIfPresent(String.self, forKey: .status)
    monitored = try container.decodeIfPresent(Bool.self, forKey: .monitored)
    qualityProfileId = try container.decodeIfPresent(Int.self, forKey: .qualityProfileId)
    metadataProfileId = try container.decodeIfPresent(Int.self, forKey: .metadataProfileId)
    path = try container.decodeIfPresent(String.self, forKey: .path)
    rootFolderPath = try container.decodeIfPresent(String.self, forKey: .rootFolderPath)
    genres = try container.decodeIfPresent([String].self, forKey: .genres)
    tags = try container.decodeIfPresent([Int].self, forKey: .tags)
    added = try container.decodeIfPresent(Date.self, forKey: .added)
    images = try container.decodeIfPresent([MediaCoverDTO].self, forKey: .images)
    statistics = try container.decodeIfPresent(ArtistStatisticsDTO.self, forKey: .statistics)

    let everything = try decoder.singleValueContainer().decode([String: AnyJSON].self)
    let known = Set(CodingKeys.allCases.map(\.rawValue))
    unknownFields = everything.filter { !known.contains($0.key) }
  }

  func encode(to encoder: any Encoder) throws {
    // Start from what Lidarr sent, then overwrite the fields an edit can
    // change or the server needs to identify the record. A nil is left out
    // rather than sent as null.
    var payload = unknownFields
    // An unlibraried lookup result has no id, or 0, and Lidarr reads `"id": 0`
    // as one; omit it.
    if libraryID != 0 { payload["id"] = .int(libraryID) }
    if let artistName { payload["artistName"] = .string(artistName) }
    if let foreignArtistId { payload["foreignArtistId"] = .string(foreignArtistId) }
    if let monitored { payload["monitored"] = .bool(monitored) }
    if let qualityProfileId { payload["qualityProfileId"] = .int(qualityProfileId) }
    if let metadataProfileId { payload["metadataProfileId"] = .int(metadataProfileId) }
    if let rootFolderPath { payload["rootFolderPath"] = .string(rootFolderPath) }
    if let path { payload["path"] = .string(path) }
    if let tags { payload["tags"] = .array(tags.map(AnyJSON.int)) }

    var container = encoder.singleValueContainer()
    try container.encode(payload)
  }

  struct ArtistStatisticsDTO: Decodable, Sendable {
    let albumCount: Int?
    let trackFileCount: Int?
    let trackCount: Int?
    let totalTrackCount: Int?
    let sizeOnDisk: Int64?
  }

  /// The library id on the 0 sentinel the rest of the code reads: 0 when the
  /// artist is not in the library, whether Lidarr said so by sending 0 or by
  /// omitting the field.
  var libraryID: Int { id ?? 0 }

  var domain: LidarrArtist {
    let name = artistName ?? "Unknown artist"
    return LidarrArtist(
      id: libraryID,
      name: name,
      // Lidarr's own sort name, so Tower and the service agree about where
      // "The Beatles" belongs.
      sortName: sortName ?? name.lowercased(),
      foreignArtistID: foreignArtistId,
      overview: overview.flatMap { $0.isEmpty ? nil : $0 },
      artistType: artistType.flatMap { $0.isEmpty ? nil : $0 },
      disambiguation: disambiguation.flatMap { $0.isEmpty ? nil : $0 },
      status: LidarrArtistStatus(apiValue: status),
      isMonitored: monitored ?? false,
      qualityProfileID: qualityProfileId ?? 0,
      metadataProfileID: metadataProfileId ?? 0,
      path: path,
      rootFolderPath: rootFolderPath,
      genres: genres ?? [],
      tagIDs: tags ?? [],
      added: added,
      posterURL: MediaCoverDTO.remoteURL(in: images, coverType: "poster"),
      statistics: statistics.map {
        LidarrArtistStatistics(
          albumCount: $0.albumCount ?? 0,
          trackFileCount: $0.trackFileCount ?? 0,
          trackCount: $0.trackCount ?? 0,
          totalTrackCount: $0.totalTrackCount ?? 0,
          sizeOnDiskBytes: $0.sizeOnDisk ?? 0)
      })
  }

  /// The same payload, read as a lookup hit. `/artist/lookup` answers with
  /// artist resources whose `id` is 0 for anything not in the library.
  var lookupDomain: LidarrArtistLookup {
    LidarrArtistLookup(
      foreignArtistID: foreignArtistId ?? String(libraryID),
      name: artistName ?? "Unknown artist",
      overview: overview.flatMap { $0.isEmpty ? nil : $0 },
      artistType: artistType.flatMap { $0.isEmpty ? nil : $0 },
      disambiguation: disambiguation.flatMap { $0.isEmpty ? nil : $0 },
      posterURL: MediaCoverDTO.remoteURL(in: images, coverType: "poster"),
      // **0 means "not in the library"**, not "the artist with id 0" — the same
      // sentinel Radarr's lookup uses, and reading it literally would mark
      // every search result as already added. An absent `id` lands on 0 too.
      existingArtistID: (libraryID != 0) ? libraryID : nil)
  }
}

struct LidarrAlbumDTO: Decodable, Sendable {
  let id: Int
  let artistId: Int?
  let title: String?
  let disambiguation: String?
  let overview: String?
  let albumType: String?
  let secondaryTypes: [String]?
  let releaseDate: Date?
  let monitored: Bool?
  let duration: Int?
  let genres: [String]?
  let images: [MediaCoverDTO]?
  let statistics: AlbumStatisticsDTO?
  /// Present when the album came back nested inside an artist payload.
  let artist: LidarrArtistDTO?

  struct AlbumStatisticsDTO: Decodable, Sendable {
    let trackFileCount: Int?
    let trackCount: Int?
    let totalTrackCount: Int?
    let sizeOnDisk: Int64?
  }

  var domain: LidarrAlbum {
    LidarrAlbum(
      id: id,
      // `artistId` is absent on an album fetched through `/album?artistId=`,
      // where the nested artist carries it instead.
      artistID: artistId ?? artist?.id ?? 0,
      title: title ?? "Untitled album",
      disambiguation: disambiguation.flatMap { $0.isEmpty ? nil : $0 },
      overview: overview.flatMap { $0.isEmpty ? nil : $0 },
      albumType: albumType.flatMap { $0.isEmpty ? nil : $0 },
      secondaryTypes: secondaryTypes ?? [],
      releaseDate: releaseDate,
      isMonitored: monitored ?? false,
      durationMilliseconds: duration,
      genres: genres ?? [],
      coverURL: MediaCoverDTO.remoteURL(in: images, coverType: "cover")
        ?? MediaCoverDTO.remoteURL(in: images, coverType: "poster"),
      statistics: statistics.map {
        LidarrAlbumStatistics(
          trackFileCount: $0.trackFileCount ?? 0,
          trackCount: $0.trackCount ?? 0,
          totalTrackCount: $0.totalTrackCount ?? 0,
          sizeOnDiskBytes: $0.sizeOnDisk ?? 0)
      })
  }
}

struct LidarrTrackDTO: Decodable, Sendable {
  let id: Int
  let albumId: Int?
  let title: String?
  let trackNumber: String?
  let absoluteTrackNumber: Int?
  let mediumNumber: Int?
  let duration: Int?
  let hasFile: Bool?
  let explicit: Bool?

  var domain: LidarrTrack {
    LidarrTrack(
      id: id,
      albumID: albumId ?? 0,
      title: title ?? "Untitled track",
      // A *string* on the wire: vinyl and multi-disc releases use "A1", "B2".
      trackNumber: trackNumber.flatMap { $0.isEmpty ? nil : $0 },
      absoluteTrackNumber: absoluteTrackNumber,
      mediumNumber: mediumNumber,
      durationMilliseconds: duration,
      hasFile: hasFile ?? false,
      isExplicit: explicit ?? false)
  }
}

struct LidarrMetadataProfileDTO: Decodable, Sendable {
  let id: Int
  let name: String?

  var domain: LidarrMetadataProfile {
    LidarrMetadataProfile(id: id, name: name ?? "Profile \(id)")
  }
}

// MARK: - Request bodies

/// `POST /artist`. Lidarr's add takes the *whole* looked-up resource plus
/// `addOptions`, the same shape as Radarr's.
struct LidarrAddArtistBody: Encodable, Sendable {
  let foreignArtistId: String
  let artistName: String
  let qualityProfileId: Int
  let metadataProfileId: Int
  let rootFolderPath: String
  let monitored: Bool
  let tags: [Int]
  let addOptions: AddOptions

  struct AddOptions: Encodable, Sendable {
    let monitor: String
    let searchForMissingAlbums: Bool
    /// Required by Lidarr even though Tower never sets it false — omitting it
    /// makes the add succeed and monitor nothing.
    let monitored: Bool
  }

  init(request: LidarrAddArtistRequest) {
    self.foreignArtistId = request.lookup.foreignArtistID
    self.artistName = request.lookup.name
    self.qualityProfileId = request.qualityProfileID
    self.metadataProfileId = request.metadataProfileID
    self.rootFolderPath = request.rootFolderPath
    self.monitored = request.isMonitored
    self.tags = request.tagIDs
    self.addOptions = AddOptions(
      monitor: request.monitorOption.rawValue,
      searchForMissingAlbums: request.searchForMissingAlbums,
      monitored: request.isMonitored)
  }
}

/// `PUT /album/monitor` — the bulk monitor toggle, which is how Lidarr changes
/// an album's monitored flag. A whole-album PUT works too but merges a fixed
/// set of fields and needs the album read back first; this one exists
/// precisely for the single-flag case.
struct LidarrAlbumMonitorBody: Encodable, Sendable {
  let albumIds: [Int]
  let monitored: Bool
}

extension MediaCoverDTO {
  /// The absolute artwork address for a cover type.
  ///
  /// **`remoteUrl`, not `url`.** The relative one points at the service and
  /// needs its API key to fetch, which an `AsyncImage` won't send — the same
  /// reasoning `RadarrDTOs` already applies to posters.
  static func remoteURL(in images: [MediaCoverDTO]?, coverType: String) -> URL? {
    // Absolute `remoteUrl` only — see `MediaCoverDTO` in RadarrDTOs.
    OpenableURL.from(images?.first { $0.coverType == coverType }?.remoteUrl)
  }
}

extension LidarrArtistDTO {
  /// The resource with the edit applied, ready to PUT back. Everything the
  /// edit doesn't touch, `unknownFields` included, goes back as it came.
  func applying(_ edit: LidarrArtistEdit) -> LidarrArtistDTO {
    var copy = self
    copy.monitored = edit.isMonitored
    copy.qualityProfileId = edit.qualityProfileID
    copy.metadataProfileId = edit.metadataProfileID
    copy.rootFolderPath = edit.rootFolderPath ?? rootFolderPath
    copy.tags = edit.tagIDs
    return copy
  }
}
