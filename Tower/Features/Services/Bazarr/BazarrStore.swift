import Foundation
import Observation
import TowerCore
import TowerData

/// Bazarr's screens: wanted, the two libraries, providers, and history.
///
/// **Wanted is the primary content**, so it drives `LoadingStore`'s spinner
/// and error states. The others are sections a user visits deliberately; each
/// loads on first visit and keeps what it got.
@MainActor
@Observable
final class BazarrStore: RefreshableStore {
  var state: Loadable<[WantedSubtitle]> = .idle
  let loads = LoadTracker()

  var searchText: String = ""

  var series: Loadable<[BazarrMediaItem]> = .idle
  var movies: Loadable<[BazarrMediaItem]> = .idle
  var providers: Loadable<[SubtitleProvider]> = .idle
  var history: Loadable<[SubtitleHistoryRecord]> = .idle

  /// Manual-search candidates, keyed by the wanted row they belong to.
  private(set) var candidates: [String: Loadable<[SubtitleCandidate]>] = [:]
  /// Rows with a download in flight.
  private(set) var downloading: Set<String> = []
  private(set) var actionError: AppError?

  private(set) var lastActionSuccess = 0
  private(set) var lastActionFailure = 0

  let repository: any BazarrRepositoryProtocol

  init(repository: any BazarrRepositoryProtocol) {
    self.repository = repository
  }

  // MARK: - Loading

  func load() async {
    await load { [self] in try await repository.wanted() }
  }

  func refresh() async {
    guard state.value != nil else { return await load() }
    await mutate { [self] in try await repository.wanted() }
  }

  /// Pull-to-refresh on a library section. Re-reads the wanted list as well,
  /// because a library row's count comes from it.
  func refreshLibrary(series isSeries: Bool) async {
    await refresh()
    if isSeries {
      await loadSeries(force: true)
    } else {
      await loadMovies(force: true)
    }
  }

  func loadSeries(force: Bool = false) async {
    await fill(\.series, force: force) { [self] in try await repository.series() }
  }

  func loadMovies(force: Bool = false) async {
    await fill(\.movies, force: force) { [self] in try await repository.movies() }
  }

  func loadProviders(force: Bool = false) async {
    await fill(\.providers, force: force) { [self] in try await repository.providers() }
  }

  func loadHistory(force: Bool = false) async {
    await fill(\.history, force: force) { [self] in try await repository.history() }
  }

  /// Loads one section on first visit and keeps what it got.
  ///
  /// Addressed by key path rather than `inout`: an actor-isolated property
  /// can't be passed `inout` across an `await`, and four near-identical copies
  /// of this six-line body is the alternative.
  private func fill<Value: Sendable>(
    _ keyPath: ReferenceWritableKeyPath<BazarrStore, Loadable<Value>>,
    force: Bool,
    _ work: @escaping () async throws -> Value
  ) async {
    if !force, self[keyPath: keyPath].value != nil { return }
    if self[keyPath: keyPath].value == nil { self[keyPath: keyPath] = .loading }
    do {
      self[keyPath: keyPath] = .loaded(try await work())
    } catch {
      self[keyPath: keyPath] = .failed(AppError.wrapping(error))
    }
  }

  var filteredWanted: [WantedSubtitle] {
    guard let wanted = state.value else { return [] }
    let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !query.isEmpty else { return wanted }
    return wanted.filter {
      $0.title.localizedCaseInsensitiveContains(query)
        || $0.subtitle?.localizedCaseInsensitiveContains(query) == true
    }
  }

  /// How many subtitles are wanted in total — the number a header leads with,
  /// since one episode can be missing three languages.
  var missingCount: Int {
    (state.value ?? []).reduce(0) { $0 + $1.missing.count }
  }

  /// The wanted rows for one library item.
  func wantedRows(for item: BazarrMediaItem) -> [WantedSubtitle] {
    (state.value ?? []).filter {
      item.isSeries ? $0.seriesID == item.serviceID : $0.radarrID == item.serviceID
    }
  }

  /// The missing count a library row shows: episodes for a series, languages
  /// for a film.
  ///
  /// The library and the wanted list are loaded at different times, so they
  /// can disagree: a download since the library loaded leaves the library's
  /// count stale, and a failed wanted load leaves the wanted list empty. The
  /// item's wanted rows win when there are any, because they are what the
  /// screen downloads against and what a download re-reads. With no wanted
  /// rows, Bazarr's own count stands, so a row reads "Complete" only when both
  /// say zero.
  func displayedMissingCount(for item: BazarrMediaItem) -> Int {
    let rows = wantedRows(for: item)
    guard !rows.isEmpty else { return item.missingCount }
    return item.isSeries ? rows.count : rows.reduce(0) { $0 + $1.missing.count }
  }

  func isDownloading(_ item: WantedSubtitle) -> Bool { downloading.contains(item.id) }
  func candidates(for item: WantedSubtitle) -> Loadable<[SubtitleCandidate]> {
    candidates[item.id] ?? .idle
  }

  // MARK: - Manual search

  func searchCandidates(for item: WantedSubtitle, force: Bool = false) async {
    if !force, candidates[item.id]?.value != nil { return }
    if candidates[item.id]?.value == nil { candidates[item.id] = .loading }
    do {
      candidates[item.id] = .loaded(try await repository.candidates(for: item))
    } catch {
      candidates[item.id] = .failed(AppError.wrapping(error))
    }
  }

  // MARK: - Downloading

  /// Downloads a specific candidate the user picked.
  func download(_ candidate: SubtitleCandidate, for item: WantedSubtitle) async {
    await performDownload(item) { [self] in
      try await repository.download(candidate, for: item)
    }
  }

  /// Lets Bazarr pick the best match for one wanted language.
  func downloadBest(_ language: SubtitleLanguage, for item: WantedSubtitle) async {
    await performDownload(item) { [self] in
      try await repository.downloadBest(language, for: item)
    }
  }

  /// Runs a download, then re-reads the wanted list.
  ///
  /// **Re-read, not patched.** A row is wanted per *language*, so downloading
  /// one of two missing subtitles should leave the row with one language left
  /// rather than remove it — and Bazarr is the only thing that knows which.
  /// Guessing would either drop a row that still has work or keep one that
  /// doesn't.
  private func performDownload(
    _ item: WantedSubtitle, _ work: @escaping () async throws -> Void
  ) async {
    guard !downloading.contains(item.id) else { return }
    downloading.insert(item.id)
    actionError = nil
    defer { downloading.remove(item.id) }

    do {
      try await work()
      lastActionSuccess += 1
      await mutate { [self] in try await repository.wanted() }
      // The candidate list is stale the moment something is downloaded.
      candidates[item.id] = nil
      // The library counts moved too, if they have been looked at.
      if series.value != nil { await loadSeries(force: true) }
      if movies.value != nil { await loadMovies(force: true) }
      if history.value != nil { await loadHistory(force: true) }
    } catch {
      lastActionFailure += 1
      actionError = AppError.wrapping(error)
    }
  }

  func clearActionError() { actionError = nil }

  /// Providers Bazarr has reported a problem with — what the provider screen
  /// leads with.
  var failingProviders: [SubtitleProvider] {
    (providers.value ?? []).filter { $0.status == .failing }
  }
}
