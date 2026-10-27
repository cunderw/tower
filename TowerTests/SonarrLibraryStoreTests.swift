import Foundation
import Testing
import TowerCore
import TowerData

@testable import Tower

/// The Sonarr library's action outcomes: what the haptics and the error row on
/// the series, season and episode screens are driven by.
@MainActor
@Suite
struct SonarrLibraryStoreTests {
  private func series(id: Int) -> SonarrSeries {
    SonarrSeries(
      id: id, tvdbID: id, imdbID: nil, title: "Show \(id)", sortTitle: "show \(id)", year: 2023,
      overview: nil, network: nil, runtimeMinutes: 45, certification: nil, genres: [],
      status: .continuing, seriesType: .standard, isMonitored: true, usesSeasonFolders: true,
      qualityProfileID: 1, path: nil, rootFolderPath: nil, tagIDs: [], added: nil,
      nextAiring: nil, previousAiring: nil, posterURL: nil, fanartURL: nil,
      seasons: [
        SonarrSeason(
          seasonNumber: 1, isMonitored: true, episodeFileCount: 1, episodeCount: 1,
          totalEpisodeCount: 1, sizeOnDiskBytes: 0, nextAiring: nil),
      ],
      statistics: nil)
  }

  private func episode(id: Int, seriesID: Int) -> SonarrEpisode {
    SonarrEpisode(
      id: id, seriesID: seriesID, seasonNumber: 1, episodeNumber: 1, title: "Pilot",
      overview: nil, airDate: Date(timeIntervalSince1970: 1_700_000_000), runtimeMinutes: 45,
      hasFile: false, isMonitored: true, file: nil)
  }

  private func makeStore() async -> (SonarrLibraryStore, StubSonarrRepository) {
    let repository = StubSonarrRepository(
      series: [series(id: 1)], episodes: [episode(id: 101, seriesID: 1)])
    let store = SonarrLibraryStore(repository: repository)
    await store.load()
    await store.loadEpisodes(seriesID: 1)
    return (store, repository)
  }

  @Test func aLoadIsNotAnAction() async {
    // A background fetch must never buzz.
    let (store, _) = await makeStore()
    await store.refresh()

    #expect(store.lastActionSuccess == 0)
    #expect(store.lastActionFailure == 0)
  }

  @Test func aSearchThatLandsCountsAsASuccess() async {
    let (store, _) = await makeStore()

    await store.runAutomaticSearch(series: store.state.value![0])

    #expect(store.lastActionSuccess == 1)
    #expect(store.lastActionFailure == 0)
  }

  @Test func aFailedSearchAtEachLevelCountsAsAFailureNotASuccess() async {
    // A failed search must not fire the success haptic.
    let (store, repository) = await makeStore()
    repository.failWrites = true

    await store.runAutomaticSearch(series: store.state.value![0])
    await store.runAutomaticSearch(seriesID: 1, seasonNumber: 1)
    await store.runAutomaticSearch(episode: store.episodes(seriesID: 1, season: 1)[0])

    #expect(store.lastActionSuccess == 0, "a failed search counted as a success")
    #expect(store.lastActionFailure == 3)
    guard case .actionFailed(let list, _) = store.state else {
      Issue.record("expected .actionFailed, got \(store.state)")
      return
    }
    #expect(list.count == 1, "the library was lost to a failed search")
  }

  @Test func aFailedToggleAtEachLevelCountsAsAFailure() async {
    let (store, repository) = await makeStore()
    repository.failWrites = true

    await store.setSeriesMonitored(false, for: store.state.value![0])
    await store.setSeasonMonitored(false, seriesID: 1, seasonNumber: 1)
    await store.setEpisodeMonitored(false, episode: store.episodes(seriesID: 1, season: 1)[0])

    #expect(store.lastActionSuccess == 0)
    #expect(store.lastActionFailure == 3)
    #expect(store.episodes(seriesID: 1, season: 1)[0].isMonitored, "the episode flipped anyway")
  }

  @Test func anEpisodeToggleThatLandsCountsAsASuccess() async {
    let (store, _) = await makeStore()

    await store.setEpisodeMonitored(false, episode: store.episodes(seriesID: 1, season: 1)[0])

    #expect(store.lastActionSuccess == 1)
    #expect(store.lastActionFailure == 0)
    #expect(store.episodes(seriesID: 1, season: 1)[0].isMonitored == false)
  }
}

/// The smallest Sonarr that can answer the library store. Writes and searches
/// fail together under `failWrites`; reads never fail.
private final class StubSonarrRepository: SonarrRepositoryProtocol, @unchecked Sendable {
  let instance = ServiceInstance(
    kind: .sonarr, name: "Sonarr", baseURL: URL(string: "http://192.0.2.1:8989")!,
    credentials: .apiKey("k"))
  var arr: ArrClientCore { ArrClientCore(client: ServiceHTTPClient(instance: instance)) }

  private let lock = NSLock()
  private var storedSeries: [SonarrSeries]
  private var storedEpisodes: [SonarrEpisode]
  var failWrites = false

  init(series: [SonarrSeries], episodes: [SonarrEpisode]) {
    storedSeries = series
    storedEpisodes = episodes
  }

  private func failIfAsked() throws {
    if failWrites { throw AppError.serverUnreachable }
  }

  func series() async throws -> [SonarrSeries] { lock.withLock { storedSeries } }

  func series(id: Int) async throws -> SonarrSeries {
    guard let match = lock.withLock({ storedSeries.first { $0.id == id } }) else {
      throw AppError.unknown("missing")
    }
    return match
  }

  func episodes(seriesID: Int) async throws -> [SonarrEpisode] {
    lock.withLock { storedEpisodes.filter { $0.seriesID == seriesID } }
  }

  func lookup(term: String) async throws -> [SonarrSeriesLookup] { [] }

  func add(_ request: SonarrAddSeriesRequest) async throws -> SonarrSeries {
    throw AppError.unknown("not used")
  }

  func update(_ series: SonarrSeries, with edit: SonarrSeriesEdit) async throws -> SonarrSeries {
    try failIfAsked()
    return series
  }

  func delete(id: Int, deleteFiles: Bool, addImportExclusion: Bool) async throws {
    try failIfAsked()
  }

  func setSeasonMonitored(_ isMonitored: Bool, seriesID: Int, seasonNumber: Int) async throws {
    try failIfAsked()
  }

  func setEpisodesMonitored(_ isMonitored: Bool, episodeIDs: [Int]) async throws {
    try failIfAsked()
    lock.withLock {
      storedEpisodes = storedEpisodes.map {
        episodeIDs.contains($0.id) ? $0.settingMonitored(isMonitored) : $0
      }
    }
  }

  func releases(episodeID: Int) async throws -> [ArrRelease] { [] }
  func grab(_ release: ArrRelease) async throws {}
  func searchSeries(id: Int) async throws { try failIfAsked() }
  func searchSeason(seriesID: Int, seasonNumber: Int) async throws { try failIfAsked() }
  func searchEpisodes(ids: [Int]) async throws { try failIfAsked() }

  func rootFolders() async throws -> [ArrRootFolder] { [] }
  func tags() async throws -> [ArrTag] { [] }
}
