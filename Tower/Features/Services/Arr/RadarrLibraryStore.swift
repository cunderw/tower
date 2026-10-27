import Foundation
import Observation
import TowerCore
import TowerData

/// The Radarr library list.
///
/// One store per instance, retained by `ServiceStoreRegistry` — two Radarrs are
/// two stores with independent state, which is what multi-instance means in
/// practice.
@MainActor
@Observable
final class RadarrLibraryStore: RefreshableStore {
  var state: Loadable<[RadarrMovie]> = .idle
  let loads = LoadTracker()
  var searchText: String = ""
  var sort: RadarrSort = .title
  var filter: RadarrFilter = .all
  /// Bumped once per action that lands (a search, a monitor toggle, a
  /// delete), never by a load or a refresh, so a background fetch never buzzes.
  /// The detail screen drives `.sensoryFeedback(.success, trigger:)` off it.
  private(set) var lastActionSuccess = 0
  /// The failure twin of `lastActionSuccess`, driving
  /// `.sensoryFeedback(.error, trigger:)`.
  private(set) var lastActionFailure = 0
  /// Quality profiles, for the row's profile name. Loaded alongside the
  /// library; a failure here costs the rows a label, never the list.
  private(set) var qualityProfiles: [Int: String] = [:]

  let repository: any RadarrRepositoryProtocol

  init(repository: any RadarrRepositoryProtocol) {
    self.repository = repository
  }

  func qualityProfileName(for movie: RadarrMovie) -> String? {
    qualityProfiles[movie.qualityProfileID]
  }

  /// Deliberately non-throwing and separate from the library load: the profile
  /// names are a nicety on the row, and a service that answers `/movie` but not
  /// `/qualityprofile` should still show its library.
  func loadQualityProfiles() async {
    guard qualityProfiles.isEmpty else { return }
    guard let profiles = try? await repository.qualityProfiles() else { return }
    qualityProfiles = Dictionary(uniqueKeysWithValues: profiles.map { ($0.id, $0.name) })
  }

  func load() async {
    await load { [self] in try await repository.movies() }
  }

  /// Never passes through `.loading`, so a failed refresh doesn't blank a
  /// library that is already on screen — the rule every Unraid list follows.
  func refresh() async {
    guard state.value != nil else { return await load() }
    await mutate { [self] in try await repository.movies() }
  }

  /// Search, then filter, then sort — in that order, so the empty states can
  /// tell "this library has nothing" from "this filter matched nothing" from
  /// "this search matched nothing".
  var filteredMovies: [RadarrMovie] {
    guard let movies = state.value else { return [] }
    let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    let searched = query.isEmpty
      ? movies
      // Studio as well as title: it is on the row, and it is how someone finds
      // "that A24 one" whose name they can't remember.
      : movies.filter {
        $0.title.localizedCaseInsensitiveContains(query)
          || $0.studio?.localizedCaseInsensitiveContains(query) == true
      }
    return searched.filter(filter.matches).sorted(by: sort.areInOrder)
  }

  /// Whether the *filter* is what emptied the list — as opposed to the search,
  /// or the library itself.
  var isFilteredToNothing: Bool {
    guard let movies = state.value, !movies.isEmpty else { return false }
    return filteredMovies.isEmpty && filter != .all
  }

  /// Kicks off Radarr's own search. Nothing on screen changes — the result of
  /// the command shows up later in the queue — so the screen confirms it with a
  /// haptic off `lastActionSuccess`, and a failure surfaces through
  /// `.actionFailed` like any other.
  func runAutomaticSearch(for movie: RadarrMovie) async {
    await perform { [self] in
      try await repository.search(movieID: movie.id)
      return state.value ?? []
    }
  }

  // MARK: - List maintenance

  /// Replaces one movie in the loaded list — after an edit, so the row and the
  /// detail screen both reflect it without a refetch.
  func replace(_ movie: RadarrMovie) {
    guard let movies = state.value else { return }
    state = .loaded(movies.map { $0.id == movie.id ? movie : $0 })
  }

  /// Adds a newly created movie. Sorting is applied on read, so this only has
  /// to get it into the list.
  func insert(_ movie: RadarrMovie) {
    guard let movies = state.value else { return }
    guard !movies.contains(where: { $0.id == movie.id }) else { return replace(movie) }
    state = .loaded(movies + [movie])
  }

  // MARK: - Actions

  /// Deletes a movie and drops it from the list without a refetch.
  ///
  /// On failure the list is left exactly as it was and the error surfaces
  /// through `.actionFailed` — losing a library because one delete failed is
  /// the outcome that rule exists to prevent.
  func delete(_ movie: RadarrMovie, deleteFiles: Bool) async {
    await perform { [self] in
      try await repository.delete(
        id: movie.id, deleteFiles: deleteFiles, addImportExclusion: false)
      return (state.value ?? []).filter { $0.id != movie.id }
    }
  }

  /// Flips the monitor flag, sending Radarr the whole resource (its PUT
  /// merges a fixed set of fields onto the stored record) and replacing just
  /// this row on success.
  func setMonitored(_ isMonitored: Bool, for movie: RadarrMovie) async {
    await perform { [self] in
      var edit = RadarrMovieEdit(movie: movie)
      edit.isMonitored = isMonitored
      let updated = try await repository.update(movie, with: edit)
      return (state.value ?? []).map { $0.id == updated.id ? updated : $0 }
    }
  }

  /// `mutate`, counting the outcome for the haptics.
  private func perform(_ action: () async throws -> [RadarrMovie]) async {
    var succeeded = false
    await mutate {
      let value = try await action()
      succeeded = true
      return value
    }
    if succeeded { lastActionSuccess += 1 } else { lastActionFailure += 1 }
  }
}

/// The Sonarr library list. Same shape, different media — the two are separate
/// types rather than one generic store because their filters and their rows
/// diverge.
@MainActor
@Observable
final class SonarrLibraryStore: RefreshableStore {
  var state: Loadable<[SonarrSeries]> = .idle
  let loads = LoadTracker()
  var searchText: String = ""
  var sort: SonarrSort = .title
  var filter: SonarrFilter = .all
  /// Bumped once per action that lands (a search or a monitor toggle at any
  /// level), never by a load or a refresh, so a background fetch never buzzes.
  /// `SonarrServiceView` drives `.sensoryFeedback(.success, trigger:)` off it,
  /// once for the whole stack, so the series, season and episode screens do not.
  private(set) var lastActionSuccess = 0
  /// The failure twin of `lastActionSuccess`, driving
  /// `.sensoryFeedback(.error, trigger:)`.
  private(set) var lastActionFailure = 0

  /// Episodes, per series, loaded when a series screen opens. Kept here rather
  /// than in a per-series store so a season toggle and the episode list it
  /// affects can't disagree.
  private(set) var episodes: [Int: Loadable<[SonarrEpisode]>] = [:]

  let repository: any SonarrRepositoryProtocol

  init(repository: any SonarrRepositoryProtocol) {
    self.repository = repository
  }

  func load() async {
    await load { [self] in try await repository.series() }
  }

  func refresh() async {
    guard state.value != nil else { return await load() }
    await mutate { [self] in try await repository.series() }
  }

  var filteredSeries: [SonarrSeries] {
    guard let series = state.value else { return [] }
    let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    let searched = query.isEmpty
      ? series
      : series.filter {
        $0.title.localizedCaseInsensitiveContains(query)
          || $0.network?.localizedCaseInsensitiveContains(query) == true
      }
    return searched.filter(filter.matches).sorted(by: sort.areInOrder)
  }

  var isFilteredToNothing: Bool {
    guard let series = state.value, !series.isEmpty else { return false }
    return filteredSeries.isEmpty && filter != .all
  }

  func series(id: Int) -> SonarrSeries? {
    state.value?.first { $0.id == id }
  }

  /// Adds a newly created series to the loaded list.
  func insert(_ series: SonarrSeries) {
    guard let list = state.value else { return }
    guard !list.contains(where: { $0.id == series.id }) else { return }
    state = .loaded(list + [series])
  }

  // MARK: - Episodes

  func episodes(for seriesID: Int) -> Loadable<[SonarrEpisode]> {
    episodes[seriesID] ?? .idle
  }

  /// Episodes for one series. Sonarr returns them all in one call, and the
  /// season screens filter locally — one request per series rather than one per
  /// season, which is what a per-season fetch would cost while scrolling.
  func loadEpisodes(seriesID: Int, force: Bool = false) async {
    if !force, episodes[seriesID]?.value != nil { return }
    if episodes[seriesID]?.value == nil { episodes[seriesID] = .loading }
    do {
      episodes[seriesID] = .loaded(try await repository.episodes(seriesID: seriesID))
    } catch {
      episodes[seriesID] = .failed(AppError.wrapping(error))
    }
  }

  func episodes(seriesID: Int, season: Int) -> [SonarrEpisode] {
    (episodes[seriesID]?.value ?? []).filter { $0.seasonNumber == season }
  }

  // MARK: - Monitoring

  func setSeriesMonitored(_ isMonitored: Bool, for series: SonarrSeries) async {
    await perform { [self] in
      var edit = SonarrSeriesEdit(series: series)
      edit.isMonitored = isMonitored
      let updated = try await repository.update(series, with: edit)
      return (state.value ?? []).map { $0.id == updated.id ? updated : $0 }
    }
  }

  /// Season monitoring, and then the episodes it governs.
  ///
  /// Sonarr applies a season's flag to its episodes server-side, so the episode
  /// list is re-fetched rather than patched locally — otherwise the episode
  /// rows keep the old state until something else happens to reload them, which
  /// is exactly the disagreement this store exists to prevent.
  func setSeasonMonitored(
    _ isMonitored: Bool, seriesID: Int, seasonNumber: Int
  ) async {
    await perform { [self] in
      try await repository.setSeasonMonitored(
        isMonitored, seriesID: seriesID, seasonNumber: seasonNumber)
      let refreshed = try await repository.series()
      return refreshed
    }
    await loadEpisodes(seriesID: seriesID, force: true)
  }

  func setEpisodeMonitored(_ isMonitored: Bool, episode: SonarrEpisode) async {
    do {
      try await repository.setEpisodesMonitored(isMonitored, episodeIDs: [episode.id])
      // Patch just this row: the round trip for one episode is not worth a full
      // re-fetch, and nothing else changes.
      if let list = episodes[episode.seriesID]?.value {
        episodes[episode.seriesID] = .loaded(
          list.map { $0.id == episode.id ? $0.settingMonitored(isMonitored) : $0 })
      }
      lastActionSuccess += 1
    } catch {
      state = .actionFailed(state.value ?? [], AppError.wrapping(error))
      lastActionFailure += 1
    }
  }

  // MARK: - Search

  func runAutomaticSearch(series: SonarrSeries) async {
    await perform { [self] in
      try await repository.searchSeries(id: series.id)
      return state.value ?? []
    }
  }

  func runAutomaticSearch(seriesID: Int, seasonNumber: Int) async {
    await perform { [self] in
      try await repository.searchSeason(seriesID: seriesID, seasonNumber: seasonNumber)
      return state.value ?? []
    }
  }

  func runAutomaticSearch(episode: SonarrEpisode) async {
    await perform { [self] in
      try await repository.searchEpisodes(ids: [episode.id])
      return state.value ?? []
    }
  }

  /// `mutate`, counting the outcome for the haptics.
  private func perform(_ action: () async throws -> [SonarrSeries]) async {
    var succeeded = false
    await mutate {
      let value = try await action()
      succeeded = true
      return value
    }
    if succeeded { lastActionSuccess += 1 } else { lastActionFailure += 1 }
  }
}

extension SonarrEpisode {
  /// A copy with the monitor flag flipped — the one field the episode list
  /// changes locally.
  func settingMonitored(_ isMonitored: Bool) -> SonarrEpisode {
    SonarrEpisode(
      id: id, seriesID: seriesID, seasonNumber: seasonNumber, episodeNumber: episodeNumber,
      title: title, overview: overview, airDate: airDate, runtimeMinutes: runtimeMinutes,
      hasFile: hasFile, isMonitored: isMonitored, file: file)
  }
}
