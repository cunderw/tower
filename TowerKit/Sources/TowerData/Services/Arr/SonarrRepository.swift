import Foundation
import TowerCore

/// Everything the Sonarr screens can ask for.
///
/// The same shape as `RadarrRepositoryProtocol` — shared surface through `arr`,
/// service-specific media on top — with the one structural difference that
/// makes Sonarr Sonarr: a series contains seasons, and a season contains
/// episodes, each with their own monitoring and their own search.
public protocol SonarrRepositoryProtocol: ServiceRepository, ArrPickerSource {
  var arr: ArrClientCore { get }

  func series() async throws -> [SonarrSeries]
  func series(id: Int) async throws -> SonarrSeries
  func episodes(seriesID: Int) async throws -> [SonarrEpisode]
  func lookup(term: String) async throws -> [SonarrSeriesLookup]
  @discardableResult
  func add(_ request: SonarrAddSeriesRequest) async throws -> SonarrSeries
  @discardableResult
  func update(_ series: SonarrSeries, with edit: SonarrSeriesEdit) async throws -> SonarrSeries
  func delete(id: Int, deleteFiles: Bool, addImportExclusion: Bool) async throws
  /// Monitoring at each of the three levels Sonarr offers.
  func setSeasonMonitored(_ isMonitored: Bool, seriesID: Int, seasonNumber: Int) async throws
  func setEpisodesMonitored(_ isMonitored: Bool, episodeIDs: [Int]) async throws
  /// Interactive search for one episode.
  func releases(episodeID: Int) async throws -> [ArrRelease]
  func grab(_ release: ArrRelease) async throws
  /// Automatic search, at series, season, or episode level.
  func searchSeries(id: Int) async throws
  func searchSeason(seriesID: Int, seasonNumber: Int) async throws
  func searchEpisodes(ids: [Int]) async throws
}

public struct LiveSonarrRepository: SonarrRepositoryProtocol {
  public let instance: ServiceInstance
  public let arr: ArrClientCore
  private let client: ServiceHTTPClient

  public init(instance: ServiceInstance, sessionConfiguration: URLSessionConfiguration? = nil) {
    let client = ServiceHTTPClient(instance: instance, sessionConfiguration: sessionConfiguration)
    self.instance = instance
    self.client = client
    self.arr = ArrClientCore(client: client, apiPath: "api/v3")
  }

  public func series() async throws -> [SonarrSeries] {
    let dtos: [SeriesDTO] = try await client.send("api/v3/series", as: [SeriesDTO].self)
    return dtos.map(\.domain).sorted {
      $0.sortTitle.localizedCaseInsensitiveCompare($1.sortTitle) == .orderedAscending
    }
  }

  public func series(id: Int) async throws -> SonarrSeries {
    try await client.send("api/v3/series/\(id)", as: SeriesDTO.self).domain
  }

  public func episodes(seriesID: Int) async throws -> [SonarrEpisode] {
    let dtos: [EpisodeDTO] = try await client.send(
      "api/v3/episode",
      query: [
        URLQueryItem(name: "seriesId", value: String(seriesID)),
        // `includeEpisodeFile` defaults to *false*, so without it Sonarr sends
        // `hasFile: true` with no `episodeFile` — and the detail screen reads
        // that as no file at all. It adds a file object only to the episodes
        // that have one.
        URLQueryItem(name: "includeEpisodeFile", value: "true"),
      ],
      as: [EpisodeDTO].self)
    // Season then episode order, because that is how a series reads and the API
    // makes no promise about the order it returns.
    return dtos.map(\.domain).sorted {
      ($0.seasonNumber, $0.episodeNumber) < ($1.seasonNumber, $1.episodeNumber)
    }
  }

  public func lookup(term: String) async throws -> [SonarrSeriesLookup] {
    let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return [] }
    let dtos: [SeriesDTO] = try await client.send(
      "api/v3/series/lookup",
      query: [URLQueryItem(name: "term", value: trimmed)],
      as: [SeriesDTO].self)
    return dtos.map(\.lookupDomain)
  }

  @discardableResult
  public func add(_ request: SonarrAddSeriesRequest) async throws -> SonarrSeries {
    try await client.send(
      "api/v3/series", method: .post, body: AddSeriesBody(request: request), as: SeriesDTO.self
    ).domain
  }

  @discardableResult
  public func update(_ series: SonarrSeries, with edit: SonarrSeriesEdit) async throws -> SonarrSeries {
    // As with Radarr: read back, apply, send it all.
    let current: SeriesDTO = try await client.send("api/v3/series/\(series.id)", as: SeriesDTO.self)
    return try await client.send(
      "api/v3/series/\(series.id)", method: .put, body: current.applying(edit), as: SeriesDTO.self
    ).domain
  }

  public func delete(id: Int, deleteFiles: Bool, addImportExclusion: Bool) async throws {
    try await client.send(
      "api/v3/series/\(id)",
      method: .delete,
      query: [
        URLQueryItem(name: "deleteFiles", value: String(deleteFiles)),
        URLQueryItem(name: "addImportListExclusion", value: String(addImportExclusion)),
      ])
  }

  public func setSeasonMonitored(
    _ isMonitored: Bool, seriesID: Int, seasonNumber: Int
  ) async throws {
    // Season monitoring lives *inside* the series resource — there is no
    // per-season endpoint — so this is a whole-series PUT with one flag flipped.
    let current: SeriesDTO = try await client.send("api/v3/series/\(seriesID)", as: SeriesDTO.self)
    let body = current.settingSeason(seasonNumber, monitored: isMonitored)
    try await client.send("api/v3/series/\(seriesID)", method: .put, body: body)
  }

  public func setEpisodesMonitored(_ isMonitored: Bool, episodeIDs: [Int]) async throws {
    guard !episodeIDs.isEmpty else { return }
    let body = EpisodeMonitorBody(episodeIds: episodeIDs, monitored: isMonitored)
    try await client.send("api/v3/episode/monitor", method: .put, body: body)
  }

  public func releases(episodeID: Int) async throws -> [ArrRelease] {
    let dtos: [ReleaseDTO] = try await client.send(
      "api/v3/release",
      query: [URLQueryItem(name: "episodeId", value: String(episodeID))],
      as: [ReleaseDTO].self)
    return dtos.map(\.domain)
  }

  public func grab(_ release: ArrRelease) async throws {
    try await client.send(
      "api/v3/release", method: .post,
      body: GrabReleaseBody(guid: release.id, indexerId: release.indexerID ?? 0))
  }

  public func searchSeries(id: Int) async throws {
    try await arr.runCommand("SeriesSearch", parameters: ["seriesId": .int(id)])
  }

  public func searchSeason(seriesID: Int, seasonNumber: Int) async throws {
    try await arr.runCommand(
      "SeasonSearch",
      parameters: ["seriesId": .int(seriesID), "seasonNumber": .int(seasonNumber)])
  }

  public func searchEpisodes(ids: [Int]) async throws {
    guard !ids.isEmpty else { return }
    try await arr.runCommand("EpisodeSearch", parameters: ["episodeIds": .ints(ids)])
  }
}

/// The picker endpoints, answered from the shared core by default. A live
/// repository never overrides these; a demo or fake one does.
extension SonarrRepositoryProtocol {
  public func qualityProfiles() async throws -> [ArrQualityProfile] {
    try await arr.qualityProfiles()
  }

  public func queue() async throws -> ArrQueuePage {
    try await arr.queue()
  }

  public func removeQueueItem(
    id: Int, removeFromClient: Bool, blocklist: Bool
  ) async throws {
    try await arr.removeQueueItem(
      id: id, removeFromClient: removeFromClient, blocklist: blocklist)
  }

  public func calendar(start: Date, end: Date) async throws -> [ArrCalendarEntry] {
    try await arr.calendar(start: start, end: end)
  }

  public func history(page: Int) async throws -> ArrHistoryPage {
    try await arr.history(page: page)
  }

  public func health() async throws -> [ArrHealthCheck] {
    try await arr.health()
  }

  public func diskSpace() async throws -> [ArrDiskSpace] {
    try await arr.diskSpace()
  }

  public func systemStatus() async throws -> ArrSystemStatus {
    try await arr.systemStatus()
  }

  @discardableResult
  public func runCommand(_ name: String) async throws -> ArrCommand {
    try await arr.runCommand(name)
  }

  public func rootFolders() async throws -> [ArrRootFolder] {
    try await arr.rootFolders()
  }

  public func tags() async throws -> [ArrTag] {
    try await arr.tags()
  }
}
