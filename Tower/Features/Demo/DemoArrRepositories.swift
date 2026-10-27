import Foundation
import TowerCore
import TowerData

/// Demo mode's Radarr and Sonarr.
///
/// **Mutations are real, in memory.** App Review walks this path, and a demo
/// where Add does nothing is a demo that shows the app not working. Everything
/// a user can do here — add, edit, delete, grab, remove from the queue —
/// changes the dataset the screens are reading, and stays changed until the
/// demo is re-entered.
///
/// Latency matches `DemoRepositories`' 450ms/700ms: without it every screen
/// snaps to loaded and a reviewer never sees the states a real LAN produces.
private enum DemoArrLatency {
  static let read = Duration.milliseconds(450)
  static let write = Duration.milliseconds(700)

  static func read() async { try? await Task.sleep(for: read) }
  static func write() async { try? await Task.sleep(for: write) }
}

/// One shared dataset per demo entry, so the *arr screens agree with each other:
/// grabbing a release puts an item in the queue, and removing it takes it out.
@MainActor
final class DemoArrServer {
  private(set) var movies: [RadarrMovie] = DemoArrFixtures.movies()
  private(set) var series: [SonarrSeries] = DemoArrFixtures.series()
  private(set) var episodes: [SonarrEpisode] = DemoArrFixtures.episodes()
  private(set) var queue: [ArrQueueItem] = DemoArrFixtures.queue()
  private(set) var history: [ArrHistoryRecord] = DemoArrFixtures.history()

  /// The ids the next add or grab takes. Counted rather than random, because
  /// every list here draws its rows by id and two of them must never share
  /// one. All start well clear of the fixtures' own ids.
  private var nextMovieID = 5_000
  private var nextSeriesID = 5_000
  private var nextQueueID = 900
  private var nextHistoryID = 8000

  func add(_ request: RadarrAddMovieRequest) -> RadarrMovie {
    let added = DemoArrFixtures.movie(from: request, id: nextMovieID)
    nextMovieID += 1
    movies.append(added)
    return added
  }

  func replace(_ movie: RadarrMovie) {
    movies = movies.map { $0.id == movie.id ? movie : $0 }
  }

  func removeMovie(id: Int) { movies.removeAll { $0.id == id } }

  func add(_ request: SonarrAddSeriesRequest) -> SonarrSeries {
    let added = DemoArrFixtures.series(from: request, id: nextSeriesID)
    nextSeriesID += 1
    series.append(added)
    return added
  }

  func replace(_ show: SonarrSeries) {
    series = series.map { $0.id == show.id ? show : $0 }
  }

  func removeSeries(id: Int) {
    series.removeAll { $0.id == id }
    episodes.removeAll { $0.seriesID == id }
  }

  func setEpisodesMonitored(_ isMonitored: Bool, ids: [Int]) {
    episodes = episodes.map { ids.contains($0.id) ? $0.settingMonitored(isMonitored) : $0 }
  }

  func setSeasonMonitored(_ isMonitored: Bool, seriesID: Int, season: Int) {
    series = series.map { show in
      guard show.id == seriesID else { return show }
      return show.replacingSeasons(
        show.seasons.map {
          $0.seasonNumber == season ? $0.settingMonitored(isMonitored) : $0
        })
    }
    episodes = episodes.map {
      $0.seriesID == seriesID && $0.seasonNumber == season
        ? $0.settingMonitored(isMonitored) : $0
    }
  }

  /// A grab lands in the queue — which is the whole point of the demo's
  /// search → grab path being end to end rather than a button that shrugs.
  func grab(_ release: ArrRelease) {
    guard !queue.contains(where: { $0.title == release.title }) else { return }
    defer {
      nextQueueID += 1
      nextHistoryID += 1
    }
    queue.insert(
      ArrQueueItem(
        id: nextQueueID,
        title: release.title,
        mediaID: nil,
        sizeBytes: release.sizeBytes,
        sizeLeftBytes: release.sizeBytes,
        timeLeft: "00:04:12",
        estimatedCompletionTime: nil,
        status: .downloading,
        trackedStatus: .ok,
        trackedState: .downloading,
        errorMessage: nil,
        statusMessages: [],
        downloadProtocol: release.downloadProtocol,
        downloadClient: "NZBGet",
        indexer: release.indexer,
        quality: release.quality),
      at: 0)
    history.insert(
      ArrHistoryRecord(
        id: nextHistoryID, event: .grabbed, sourceTitle: release.title,
        mediaID: nil, date: Date(), quality: release.quality),
      at: 0)
  }

  func removeQueueItem(id: Int) { queue.removeAll { $0.id == id } }
}

struct DemoRadarrRepository: RadarrRepositoryProtocol {
  let instance: ServiceInstance
  let server: DemoArrServer

  var arr: ArrClientCore {
    // Never used: every shared endpoint is answered below rather than delegated.
    ArrClientCore(client: ServiceHTTPClient(instance: instance))
  }

  func movies() async throws -> [RadarrMovie] {
    await DemoArrLatency.read()
    return await server.movies
  }

  func movie(id: Int) async throws -> RadarrMovie {
    await DemoArrLatency.read()
    guard let movie = await server.movies.first(where: { $0.id == id }) else {
      throw AppError.unknown("That movie is no longer in the library.")
    }
    return movie
  }

  func lookup(term: String) async throws -> [RadarrMovieLookup] {
    await DemoArrLatency.read()
    return DemoArrFixtures.movieLookups(matching: term, existing: await server.movies)
  }

  @discardableResult
  func add(_ request: RadarrAddMovieRequest) async throws -> RadarrMovie {
    await DemoArrLatency.write()
    return await server.add(request)
  }

  @discardableResult
  func update(_ movie: RadarrMovie, with edit: RadarrMovieEdit) async throws -> RadarrMovie {
    await DemoArrLatency.write()
    let updated = movie.applying(edit)
    await server.replace(updated)
    return updated
  }

  func delete(id: Int, deleteFiles: Bool, addImportExclusion: Bool) async throws {
    await DemoArrLatency.write()
    await server.removeMovie(id: id)
  }

  func releases(movieID: Int) async throws -> [ArrRelease] {
    await DemoArrLatency.read()
    let title = await server.movies.first { $0.id == movieID }?.title ?? "Unknown Film"
    return DemoArrFixtures.releases(for: title)
  }

  func grab(_ release: ArrRelease) async throws {
    await DemoArrLatency.write()
    await server.grab(release)
  }

  func search(movieID: Int) async throws {
    await DemoArrLatency.write()
  }

  // MARK: - Shared surface

  func qualityProfiles() async throws -> [ArrQualityProfile] { DemoArrFixtures.qualityProfiles }
  func rootFolders() async throws -> [ArrRootFolder] { DemoArrFixtures.movieRootFolders }
  func tags() async throws -> [ArrTag] { DemoArrFixtures.tags }

  func queue() async throws -> ArrQueuePage {
    await DemoArrLatency.read()
    let items = await server.queue
    return ArrQueuePage(items: items, page: 1, pageSize: 50, totalRecords: items.count)
  }

  func removeQueueItem(id: Int, removeFromClient: Bool, blocklist: Bool) async throws {
    await DemoArrLatency.write()
    await server.removeQueueItem(id: id)
  }

  func calendar(start: Date, end: Date) async throws -> [ArrCalendarEntry] {
    await DemoArrLatency.read()
    return DemoArrFixtures.movieCalendar()
  }

  func history(page: Int) async throws -> ArrHistoryPage {
    await DemoArrLatency.read()
    let records = await server.history
    return ArrHistoryPage(records: records, page: 1, pageSize: 50, totalRecords: records.count)
  }

  func health() async throws -> [ArrHealthCheck] {
    await DemoArrLatency.read()
    return DemoArrFixtures.health
  }

  func diskSpace() async throws -> [ArrDiskSpace] {
    await DemoArrLatency.read()
    return DemoArrFixtures.disks
  }

  func systemStatus() async throws -> ArrSystemStatus {
    await DemoArrLatency.read()
    return DemoArrFixtures.status(app: "Radarr", version: "5.14.0.9383")
  }

  @discardableResult
  func runCommand(_ name: String) async throws -> ArrCommand {
    await DemoArrLatency.write()
    return ArrCommand(id: 1, name: name, status: .queued, message: nil, started: Date(), ended: nil)
  }
}

struct DemoSonarrRepository: SonarrRepositoryProtocol {
  let instance: ServiceInstance
  let server: DemoArrServer

  var arr: ArrClientCore {
    ArrClientCore(client: ServiceHTTPClient(instance: instance))
  }

  func series() async throws -> [SonarrSeries] {
    await DemoArrLatency.read()
    return await server.series
  }

  func series(id: Int) async throws -> SonarrSeries {
    await DemoArrLatency.read()
    guard let show = await server.series.first(where: { $0.id == id }) else {
      throw AppError.unknown("That series is no longer in the library.")
    }
    return show
  }

  func episodes(seriesID: Int) async throws -> [SonarrEpisode] {
    await DemoArrLatency.read()
    return await server.episodes.filter { $0.seriesID == seriesID }
  }

  func lookup(term: String) async throws -> [SonarrSeriesLookup] {
    await DemoArrLatency.read()
    return DemoArrFixtures.seriesLookups(matching: term, existing: await server.series)
  }

  @discardableResult
  func add(_ request: SonarrAddSeriesRequest) async throws -> SonarrSeries {
    await DemoArrLatency.write()
    return await server.add(request)
  }

  @discardableResult
  func update(_ show: SonarrSeries, with edit: SonarrSeriesEdit) async throws -> SonarrSeries {
    await DemoArrLatency.write()
    let updated = show.applying(edit)
    await server.replace(updated)
    return updated
  }

  func delete(id: Int, deleteFiles: Bool, addImportExclusion: Bool) async throws {
    await DemoArrLatency.write()
    await server.removeSeries(id: id)
  }

  func setSeasonMonitored(_ isMonitored: Bool, seriesID: Int, seasonNumber: Int) async throws {
    await DemoArrLatency.write()
    await server.setSeasonMonitored(isMonitored, seriesID: seriesID, season: seasonNumber)
  }

  func setEpisodesMonitored(_ isMonitored: Bool, episodeIDs: [Int]) async throws {
    await DemoArrLatency.write()
    await server.setEpisodesMonitored(isMonitored, ids: episodeIDs)
  }

  func releases(episodeID: Int) async throws -> [ArrRelease] {
    await DemoArrLatency.read()
    guard let episode = await server.episodes.first(where: { $0.id == episodeID }),
      let show = await server.series.first(where: { $0.id == episode.seriesID })
    else { return DemoArrFixtures.releases(for: "Unknown Series", season: 1, episode: 1) }
    return DemoArrFixtures.releases(
      for: show.title, season: episode.seasonNumber, episode: episode.episodeNumber)
  }

  func grab(_ release: ArrRelease) async throws {
    await DemoArrLatency.write()
    await server.grab(release)
  }

  func searchSeries(id: Int) async throws { await DemoArrLatency.write() }
  func searchSeason(seriesID: Int, seasonNumber: Int) async throws { await DemoArrLatency.write() }
  func searchEpisodes(ids: [Int]) async throws { await DemoArrLatency.write() }

  // MARK: - Shared surface

  func qualityProfiles() async throws -> [ArrQualityProfile] { DemoArrFixtures.qualityProfiles }
  func rootFolders() async throws -> [ArrRootFolder] { DemoArrFixtures.seriesRootFolders }
  func tags() async throws -> [ArrTag] { DemoArrFixtures.tags }

  func queue() async throws -> ArrQueuePage {
    await DemoArrLatency.read()
    let items = await server.queue
    return ArrQueuePage(items: items, page: 1, pageSize: 50, totalRecords: items.count)
  }

  func removeQueueItem(id: Int, removeFromClient: Bool, blocklist: Bool) async throws {
    await DemoArrLatency.write()
    await server.removeQueueItem(id: id)
  }

  func calendar(start: Date, end: Date) async throws -> [ArrCalendarEntry] {
    await DemoArrLatency.read()
    return DemoArrFixtures.seriesCalendar()
  }

  func history(page: Int) async throws -> ArrHistoryPage {
    await DemoArrLatency.read()
    let records = await server.history
    return ArrHistoryPage(records: records, page: 1, pageSize: 50, totalRecords: records.count)
  }

  func health() async throws -> [ArrHealthCheck] {
    await DemoArrLatency.read()
    return []
  }

  func diskSpace() async throws -> [ArrDiskSpace] {
    await DemoArrLatency.read()
    return DemoArrFixtures.disks
  }

  func systemStatus() async throws -> ArrSystemStatus {
    await DemoArrLatency.read()
    return DemoArrFixtures.status(app: "Sonarr", version: "4.0.10.2544")
  }

  @discardableResult
  func runCommand(_ name: String) async throws -> ArrCommand {
    await DemoArrLatency.write()
    return ArrCommand(id: 1, name: name, status: .queued, message: nil, started: Date(), ended: nil)
  }
}

extension RadarrMovie {
  /// The edit sheet's fields applied — the demo's stand-in for Radarr's PUT,
  /// which merges a fixed set of fields onto the stored record.
  func applying(_ edit: RadarrMovieEdit) -> RadarrMovie {
    RadarrMovie(
      id: id, tmdbID: tmdbID, imdbID: imdbID, title: title, sortTitle: sortTitle, year: year,
      overview: overview, studio: studio, runtimeMinutes: runtimeMinutes,
      certification: certification, genres: genres, status: status,
      minimumAvailability: edit.minimumAvailability, isMonitored: edit.isMonitored,
      hasFile: hasFile, isAvailable: isAvailable, sizeOnDiskBytes: sizeOnDiskBytes,
      qualityProfileID: edit.qualityProfileID, path: path,
      rootFolderPath: edit.rootFolderPath ?? rootFolderPath, tagIDs: edit.tagIDs, added: added,
      inCinemas: inCinemas, digitalRelease: digitalRelease, physicalRelease: physicalRelease,
      posterURL: posterURL, fanartURL: fanartURL, file: file)
  }
}

extension SonarrSeries {
  func applying(_ edit: SonarrSeriesEdit) -> SonarrSeries {
    SonarrSeries(
      id: id, tvdbID: tvdbID, imdbID: imdbID, title: title, sortTitle: sortTitle, year: year,
      overview: overview, network: network, runtimeMinutes: runtimeMinutes,
      certification: certification, genres: genres, status: status,
      seriesType: edit.seriesType, isMonitored: edit.isMonitored,
      usesSeasonFolders: edit.usesSeasonFolders, qualityProfileID: edit.qualityProfileID,
      path: path, rootFolderPath: edit.rootFolderPath ?? rootFolderPath, tagIDs: edit.tagIDs,
      added: added, nextAiring: nextAiring, previousAiring: previousAiring, posterURL: posterURL,
      fanartURL: fanartURL, seasons: seasons, statistics: statistics)
  }

  func replacingSeasons(_ seasons: [SonarrSeason]) -> SonarrSeries {
    SonarrSeries(
      id: id, tvdbID: tvdbID, imdbID: imdbID, title: title, sortTitle: sortTitle, year: year,
      overview: overview, network: network, runtimeMinutes: runtimeMinutes,
      certification: certification, genres: genres, status: status, seriesType: seriesType,
      isMonitored: isMonitored, usesSeasonFolders: usesSeasonFolders,
      qualityProfileID: qualityProfileID, path: path, rootFolderPath: rootFolderPath,
      tagIDs: tagIDs, added: added, nextAiring: nextAiring, previousAiring: previousAiring,
      posterURL: posterURL, fanartURL: fanartURL, seasons: seasons, statistics: statistics)
  }
}

extension SonarrSeason {
  func settingMonitored(_ isMonitored: Bool) -> SonarrSeason {
    SonarrSeason(
      seasonNumber: seasonNumber, isMonitored: isMonitored, episodeFileCount: episodeFileCount,
      episodeCount: episodeCount, totalEpisodeCount: totalEpisodeCount,
      sizeOnDiskBytes: sizeOnDiskBytes, nextAiring: nextAiring)
  }
}
