import Foundation
import TowerCore

/// Everything the Lidarr screens can ask for.
///
/// **Most of this is reuse.** Queue, calendar, history, health,
/// system status, commands, quality profiles, root folders, and tags all come
/// from `ArrClientCore` through `arr` — none of them is reimplemented here.
/// What is Lidarr's own is the artist → album → track hierarchy, the metadata
/// profile, and search at two levels instead of one.
public protocol LidarrRepositoryProtocol: ServiceRepository, ArrPickerSource {
  /// The shared *arr endpoints for this instance.
  var arr: ArrClientCore { get }

  func artists() async throws -> [LidarrArtist]
  func artist(id: Int) async throws -> LidarrArtist
  func albums(artistID: Int) async throws -> [LidarrAlbum]
  func tracks(albumID: Int) async throws -> [LidarrTrack]

  /// MusicBrainz search for the add flow.
  func lookup(term: String) async throws -> [LidarrArtistLookup]
  @discardableResult
  func add(_ request: LidarrAddArtistRequest) async throws -> LidarrArtist
  @discardableResult
  func update(_ artist: LidarrArtist, with edit: LidarrArtistEdit) async throws -> LidarrArtist
  func delete(id: Int, deleteFiles: Bool, addImportExclusion: Bool) async throws

  func setAlbumMonitored(_ isMonitored: Bool, albumIDs: [Int]) async throws

  /// Lidarr's second profile axis, which decides which album types are wanted
  /// at all. No Radarr or Sonarr equivalent, so it isn't on `ArrPickerSource`.
  func metadataProfiles() async throws -> [LidarrMetadataProfile]

  /// Interactive search, at either level.
  func releases(artistID: Int) async throws -> [ArrRelease]
  func releases(albumID: Int) async throws -> [ArrRelease]
  func grab(_ release: ArrRelease) async throws
  func searchArtist(id: Int) async throws
  func searchAlbum(id: Int) async throws
}

/// The live conformance, over `ServiceHTTPClient`.
public struct LiveLidarrRepository: LidarrRepositoryProtocol {
  public let instance: ServiceInstance
  public let arr: ArrClientCore
  private let client: ServiceHTTPClient

  public init(instance: ServiceInstance, sessionConfiguration: URLSessionConfiguration? = nil) {
    let client = ServiceHTTPClient(
      instance: instance, sessionConfiguration: sessionConfiguration)
    self.init(instance: instance, client: client)
  }

  init(instance: ServiceInstance, client: ServiceHTTPClient) {
    self.instance = instance
    self.client = client
    // v1, not v3 — Lidarr's version of the shared surface.
    self.arr = ArrClientCore(client: client, apiPath: "api/v1")
  }

  // MARK: - Library

  public func artists() async throws -> [LidarrArtist] {
    let dtos: [LidarrArtistDTO] = try await client.send(
      "api/v1/artist", as: [LidarrArtistDTO].self)
    // Lidarr's own sort name, so Tower and the service agree about where "The
    // Beatles" belongs.
    return dtos.map(\.domain).sorted {
      $0.sortName.localizedCaseInsensitiveCompare($1.sortName) == .orderedAscending
    }
  }

  public func artist(id: Int) async throws -> LidarrArtist {
    try await client.send("api/v1/artist/\(id)", as: LidarrArtistDTO.self).domain
  }

  public func albums(artistID: Int) async throws -> [LidarrAlbum] {
    let dtos: [LidarrAlbumDTO] = try await client.send(
      "api/v1/album",
      query: [URLQueryItem(name: "artistId", value: String(artistID))],
      as: [LidarrAlbumDTO].self)
    // Newest first: a discography is read from the current record backwards,
    // which is the opposite of how a TV series' seasons are read.
    return dtos.map(\.domain).sorted {
      ($0.releaseDate ?? .distantPast) > ($1.releaseDate ?? .distantPast)
    }
  }

  public func tracks(albumID: Int) async throws -> [LidarrTrack] {
    let dtos: [LidarrTrackDTO] = try await client.send(
      "api/v1/track",
      query: [URLQueryItem(name: "albumId", value: String(albumID))],
      as: [LidarrTrackDTO].self)
    // By disc, then by track within it. `absoluteTrackNumber` alone would
    // interleave a double album's two discs.
    return dtos.map(\.domain).sorted {
      ($0.mediumNumber ?? 1, $0.absoluteTrackNumber ?? 0)
        < ($1.mediumNumber ?? 1, $1.absoluteTrackNumber ?? 0)
    }
  }

  // MARK: - Add and edit

  public func lookup(term: String) async throws -> [LidarrArtistLookup] {
    let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return [] }
    let dtos: [LidarrArtistDTO] = try await client.send(
      "api/v1/artist/lookup",
      query: [URLQueryItem(name: "term", value: trimmed)],
      as: [LidarrArtistDTO].self)
    return dtos.map(\.lookupDomain)
  }

  @discardableResult
  public func add(_ request: LidarrAddArtistRequest) async throws -> LidarrArtist {
    try await client.send(
      "api/v1/artist", method: .post, body: LidarrAddArtistBody(request: request),
      as: LidarrArtistDTO.self
    ).domain
  }

  @discardableResult
  public func update(
    _ artist: LidarrArtist, with edit: LidarrArtistEdit
  ) async throws -> LidarrArtist {
    // Read back first, and sent back whole. PUT merges a fixed set of fields
    // onto the stored record, and `unknownFields` carries the ones Tower
    // doesn't model (`monitorNewItems` among them) so they aren't reset.
    let current: LidarrArtistDTO = try await client.send(
      "api/v1/artist/\(artist.id)", as: LidarrArtistDTO.self)
    return try await client.send(
      "api/v1/artist/\(artist.id)", method: .put, body: current.applying(edit),
      as: LidarrArtistDTO.self
    ).domain
  }

  public func delete(id: Int, deleteFiles: Bool, addImportExclusion: Bool) async throws {
    try await client.send(
      "api/v1/artist/\(id)", method: .delete,
      query: [
        URLQueryItem(name: "deleteFiles", value: deleteFiles ? "true" : "false"),
        URLQueryItem(
          name: "addImportListExclusion", value: addImportExclusion ? "true" : "false"),
      ])
  }

  public func setAlbumMonitored(_ isMonitored: Bool, albumIDs: [Int]) async throws {
    guard !albumIDs.isEmpty else { return }
    // The dedicated bulk endpoint, not a whole-album PUT: this one exists for
    // the single-flag case and can't drop a field by omission.
    try await client.send(
      "api/v1/album/monitor", method: .put,
      body: LidarrAlbumMonitorBody(albumIds: albumIDs, monitored: isMonitored))
  }

  // MARK: - Pickers

  public func metadataProfiles() async throws -> [LidarrMetadataProfile] {
    let dtos: [LidarrMetadataProfileDTO] = try await client.send(
      "api/v1/metadataprofile", as: [LidarrMetadataProfileDTO].self)
    return dtos.map(\.domain)
  }

  // MARK: - Search

  public func releases(artistID: Int) async throws -> [ArrRelease] {
    try await releases(query: URLQueryItem(name: "artistId", value: String(artistID)))
  }

  public func releases(albumID: Int) async throws -> [ArrRelease] {
    try await releases(query: URLQueryItem(name: "albumId", value: String(albumID)))
  }

  private func releases(query: URLQueryItem) async throws -> [ArrRelease] {
    let dtos: [ReleaseDTO] = try await client.send(
      "api/v1/release", query: [query], as: [ReleaseDTO].self)
    return dtos.map(\.domain)
  }

  public func grab(_ release: ArrRelease) async throws {
    // The guid plus the indexer that offered it — the same release from two
    // indexers is two different grabs. Identical to Radarr's and Sonarr's,
    // which is why `GrabReleaseBody` is shared rather than duplicated.
    let body = GrabReleaseBody(guid: release.id, indexerId: release.indexerID ?? 0)
    try await client.send("api/v1/release", method: .post, body: body)
  }

  public func searchArtist(id: Int) async throws {
    try await arr.runCommand("ArtistSearch", parameters: ["artistId": .int(id)])
  }

  public func searchAlbum(id: Int) async throws {
    try await arr.runCommand("AlbumSearch", parameters: ["albumIds": .ints([id])])
  }
}

/// The shared surface, answered from `ArrClientCore` by default — the same
/// extension Radarr and Sonarr carry, which is why a Lidarr client is mostly
/// wiring. A live repository never overrides these; a demo one does.
extension LidarrRepositoryProtocol {
  public func qualityProfiles() async throws -> [ArrQualityProfile] {
    try await arr.qualityProfiles()
  }

  public func rootFolders() async throws -> [ArrRootFolder] { try await arr.rootFolders() }
  public func tags() async throws -> [ArrTag] { try await arr.tags() }

  public func queue() async throws -> ArrQueuePage { try await arr.queue() }

  public func removeQueueItem(id: Int, removeFromClient: Bool, blocklist: Bool) async throws {
    try await arr.removeQueueItem(
      id: id, removeFromClient: removeFromClient, blocklist: blocklist)
  }

  public func calendar(start: Date, end: Date) async throws -> [ArrCalendarEntry] {
    try await arr.calendar(start: start, end: end)
  }

  public func history(page: Int) async throws -> ArrHistoryPage {
    try await arr.history(page: page)
  }

  public func health() async throws -> [ArrHealthCheck] { try await arr.health() }
  public func diskSpace() async throws -> [ArrDiskSpace] { try await arr.diskSpace() }
  public func systemStatus() async throws -> ArrSystemStatus { try await arr.systemStatus() }

  @discardableResult
  public func runCommand(_ name: String) async throws -> ArrCommand {
    try await arr.runCommand(name)
  }
}
