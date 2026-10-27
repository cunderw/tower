import Foundation
import Testing
import TowerCore
import TowerData

@testable import Tower

/// Bazarr's wanted → search → download path, and the sections around it.
@MainActor
@Suite
struct BazarrStoreTests {
  private func language(
    _ code: String, _ name: String, hi: Bool = false, forced: Bool = false
  ) -> SubtitleLanguage {
    SubtitleLanguage(code: code, name: name, isHearingImpaired: hi, isForced: forced)
  }

  private func wanted(
    episode: Int? = nil, series: Int? = nil, movie: Int? = nil, title: String,
    missing: [SubtitleLanguage]
  ) -> WantedSubtitle {
    WantedSubtitle(
      title: title, subtitle: episode.map { "1x0\($0 % 10)" }, seriesID: series,
      episodeID: episode, radarrID: movie, missing: missing)
  }

  private func candidate(
    provider: String, score: Int, language: SubtitleLanguage, handle: String = "h"
  ) -> SubtitleCandidate {
    SubtitleCandidate(
      provider: provider, language: language, score: score, subtitleID: handle,
      releaseInfo: ["Example.Release"], uploader: nil, url: nil, matchedBy: [])
  }

  private func makeStore(
    _ items: [WantedSubtitle], candidates: [SubtitleCandidate] = [],
    providers: [SubtitleProvider] = [], series: [BazarrMediaItem] = []
  ) async -> (BazarrStore, StubBazarrRepository) {
    let repository = StubBazarrRepository(
      wanted: items, candidates: candidates, providers: providers, series: series)
    let store = BazarrStore(repository: repository)
    await store.load()
    return (store, repository)
  }

  // MARK: - Wanted

  @Test func theHeaderCountsSubtitlesNotRows() async {
    // One episode can be missing three languages, and the number people care
    // about is how many files are outstanding.
    let (store, _) = await makeStore([
      wanted(
        episode: 1, series: 14, title: "Northern Lights",
        missing: [language("en", "English"), language("en", "English", hi: true)]),
      wanted(movie: 3, title: "Winter Ledger", missing: [language("fr", "French")]),
    ])

    #expect(store.state.value?.count == 2)
    #expect(store.missingCount == 3)
  }

  @Test func searchMatchesTitleAndEpisodeLabel() async {
    let (store, _) = await makeStore([
      wanted(episode: 1, series: 14, title: "Northern Lights", missing: [language("en", "English")]),
      wanted(movie: 3, title: "Winter Ledger", missing: [language("fr", "French")]),
    ])

    store.searchText = "winter"
    #expect(store.filteredWanted.count == 1)

    store.searchText = "1x01"
    #expect(store.filteredWanted.first?.episodeID == 1)
  }

  // MARK: - Missing counts reconcile

  @Test func theLibraryRowsWantedEntriesAreFoundByTheRightID() async {
    // A series row matches on `seriesID` and a film row on `radarrID`; getting
    // that backwards silently shows every row as complete.
    let (store, _) = await makeStore(
      [
        wanted(episode: 1, series: 14, title: "Northern Lights", missing: [language("en", "English")]),
        wanted(episode: 2, series: 14, title: "Northern Lights", missing: [language("en", "English")]),
        wanted(movie: 3, title: "Winter Ledger", missing: [language("fr", "French")]),
      ],
      series: [
        BazarrMediaItem(
          serviceID: 14, title: "Northern Lights", isSeries: true, posterURL: nil,
          monitored: true, missingCount: 2, languageProfileName: "English")
      ])
    await store.loadSeries()

    let item = try! #require(store.series.value?.first)
    #expect(store.wantedRows(for: item).count == 2)

    // A film with the same numeric id must not match the series' rows.
    let film = BazarrMediaItem(
      serviceID: 14, title: "Something", isSeries: false, posterURL: nil, monitored: true,
      missingCount: 0, languageProfileName: nil)
    #expect(store.wantedRows(for: film).isEmpty)
  }

  @Test func aSeriesRowCountsItsWantedEpisodesOverAStaleLibraryCount() async {
    // The library loaded before the wanted list, so its count is out of date;
    // the wanted rows are what the screen downloads against.
    let item = BazarrMediaItem(
      serviceID: 14, title: "Northern Lights", isSeries: true, posterURL: nil,
      monitored: true, missingCount: 0, languageProfileName: "English")
    let (store, _) = await makeStore([
      wanted(episode: 1, series: 14, title: "Northern Lights", missing: [language("en", "English")]),
      wanted(
        episode: 2, series: 14, title: "Northern Lights",
        missing: [language("en", "English"), language("fr", "French")]),
    ])

    #expect(store.displayedMissingCount(for: item) == 2)
  }

  @Test func aFilmRowCountsItsWantedLanguagesOverAStaleLibraryCount() async {
    let item = BazarrMediaItem(
      serviceID: 3, title: "Winter Ledger", isSeries: false, posterURL: nil,
      monitored: true, missingCount: 0, languageProfileName: nil)
    let (store, _) = await makeStore([
      wanted(movie: 3, title: "Winter Ledger", missing: [language("en", "English"), language("fr", "French")])
    ])

    #expect(store.displayedMissingCount(for: item) == 2)
  }

  @Test func aRowFallsBackToBazarrsCountBeforeTheWantedListLoads() async {
    let item = BazarrMediaItem(
      serviceID: 14, title: "Northern Lights", isSeries: true, posterURL: nil,
      monitored: true, missingCount: 3, languageProfileName: "English")
    let store = BazarrStore(
      repository: StubBazarrRepository(wanted: [], candidates: [], providers: [], series: []))

    #expect(store.displayedMissingCount(for: item) == 3)
  }

  @Test func aRowWithNoWantedRowsKeepsBazarrsOwnCount() async {
    // The library and the wanted list load at different times, and a failed
    // wanted load leaves it empty, so an empty wanted list cannot overrule a
    // count above zero.
    let item = BazarrMediaItem(
      serviceID: 14, title: "Northern Lights", isSeries: true, posterURL: nil,
      monitored: true, missingCount: 3, languageProfileName: "English")
    let (store, _) = await makeStore([])

    #expect(store.state.value != nil)
    #expect(store.displayedMissingCount(for: item) == 3)
  }

  @Test func refreshingALibraryReReadsTheWantedListToo() async {
    let (store, repository) = await makeStore(
      [wanted(episode: 1, series: 14, title: "Northern Lights", missing: [language("en", "English")])],
      series: [
        BazarrMediaItem(
          serviceID: 14, title: "Northern Lights", isSeries: true, posterURL: nil,
          monitored: true, missingCount: 1, languageProfileName: "English")
      ])
    await store.loadSeries()
    let wantedCallsBefore = repository.wantedCalls
    let seriesCallsBefore = repository.seriesCalls
    let movieCallsBefore = repository.movieCalls

    await store.refreshLibrary(series: true)

    #expect(repository.wantedCalls == wantedCallsBefore + 1, "the row counts' source went stale")
    #expect(repository.seriesCalls == seriesCallsBefore + 1)
    #expect(repository.movieCalls == movieCallsBefore, "the other library was fetched")
  }

  // MARK: - Sections

  @Test func sectionsLoadOnFirstVisitAndKeepWhatTheyGot() async {
    let (store, repository) = await makeStore(
      [], providers: [SubtitleProvider(name: "opensubtitles.com", message: "Good", retryAt: nil)])

    #expect(repository.providerCalls == 0)
    await store.loadProviders()
    #expect(repository.providerCalls == 1)

    await store.loadProviders()
    #expect(repository.providerCalls == 1, "a section refetched on a second visit")

    await store.loadProviders(force: true)
    #expect(repository.providerCalls == 2)
  }

  @Test func aSectionFailureIsScopedToThatSection() async {
    let (store, repository) = await makeStore([
      wanted(movie: 3, title: "Winter Ledger", missing: [language("fr", "French")])
    ])
    repository.failSections = true

    await store.loadProviders()

    guard case .failed = store.providers else {
      Issue.record("expected .failed, got \(store.providers)")
      return
    }
    #expect(store.state.value?.count == 1, "the wanted list was lost to a provider failure")
  }

  // MARK: - Provider failures visible

  @Test func failingProvidersAreCountedSeparately() async {
    let (store, _) = await makeStore(
      [],
      providers: [
        SubtitleProvider(name: "opensubtitles.com", message: "Good", retryAt: nil),
        SubtitleProvider(name: "addic7ed", message: "Throttled", retryAt: "in 2 hours"),
        SubtitleProvider(name: "gestdown", message: nil, retryAt: nil),
      ])
    await store.loadProviders()

    #expect(store.providers.value?.count == 3)
    #expect(store.failingProviders.map(\.name) == ["addic7ed"])
  }

  // MARK: - Manual search

  @Test func candidatesLoadPerItemAndAreKept() async {
    let item = wanted(
      episode: 1, series: 14, title: "Northern Lights", missing: [language("en", "English")])
    let (store, repository) = await makeStore(
      [item], candidates: [candidate(provider: "opensubtitles.com", score: 96, language: language("en", "English"))])

    await store.searchCandidates(for: item)
    #expect(store.candidates(for: item).value?.count == 1)
    #expect(repository.candidateCalls == 1)

    await store.searchCandidates(for: item)
    #expect(repository.candidateCalls == 1)

    await store.searchCandidates(for: item, force: true)
    #expect(repository.candidateCalls == 2)
  }

  // MARK: - Download clears the wanted entry

  @Test func aManualDownloadClearsTheWantedEntry() async {
    let item = wanted(
      episode: 1, series: 14, title: "Northern Lights", missing: [language("en", "English")])
    let pick = candidate(
      provider: "opensubtitles.com", score: 96, language: language("en", "English"))
    let (store, repository) = await makeStore([item], candidates: [pick])
    await store.searchCandidates(for: item)

    await store.download(pick, for: item)

    #expect(repository.downloads.count == 1)
    #expect(repository.downloads[0].provider == "opensubtitles.com")
    #expect(store.state.value?.isEmpty == true, "the wanted entry survived the download")
    #expect(store.lastActionSuccess == 1)
    // The candidate list is stale the moment something is downloaded.
    #expect(store.candidates(for: item).value == nil)
  }

  @Test func anAutomaticDownloadClearsItToo() async {
    let item = wanted(
      episode: 1, series: 14, title: "Northern Lights", missing: [language("en", "English")])
    let (store, repository) = await makeStore([item])

    await store.downloadBest(language("en", "English"), for: item)

    #expect(repository.autoDownloads.count == 1)
    #expect(repository.autoDownloads[0].code == "en")
    #expect(store.state.value?.isEmpty == true)
  }

  @Test func downloadingOneOfTwoLanguagesLeavesTheRowWithOneLeft() async {
    // The reason the wanted list is re-read rather than patched: a row is
    // wanted per language, and only Bazarr knows which one is now satisfied.
    let item = wanted(
      episode: 1, series: 14, title: "Northern Lights",
      missing: [language("en", "English"), language("fr", "French")])
    let (store, _) = await makeStore([item])

    await store.downloadBest(language("en", "English"), for: item)

    #expect(store.state.value?.count == 1, "the row was dropped while it still had work")
    #expect(store.state.value?[0].missing.map(\.code) == ["fr"])
  }

  @Test func aFailedDownloadKeepsTheWantedListAndSaysWhy() async {
    let item = wanted(
      episode: 1, series: 14, title: "Northern Lights", missing: [language("en", "English")])
    let (store, repository) = await makeStore([item])
    repository.failDownloads = true

    await store.downloadBest(language("en", "English"), for: item)

    #expect(store.actionError != nil)
    #expect(store.lastActionFailure == 1)
    #expect(store.state.value?.count == 1, "the wanted list was lost to a failed download")
  }

  @Test func aDoubleTapCannotDownloadTwice() async {
    let item = wanted(
      episode: 1, series: 14, title: "Northern Lights", missing: [language("en", "English")])
    let (store, repository) = await makeStore([item])

    async let first: Void = store.downloadBest(language("en", "English"), for: item)
    async let second: Void = store.downloadBest(language("en", "English"), for: item)
    _ = await (first, second)

    #expect(repository.autoDownloads.count == 1)
  }

  @Test func aDownloadRefreshesTheSectionsThatHaveBeenLookedAt() async {
    // The library counts moved; the ones nobody has opened are left alone.
    let item = wanted(
      episode: 1, series: 14, title: "Northern Lights", missing: [language("en", "English")])
    let (store, repository) = await makeStore(
      [item],
      series: [
        BazarrMediaItem(
          serviceID: 14, title: "Northern Lights", isSeries: true, posterURL: nil,
          monitored: true, missingCount: 1, languageProfileName: nil)
      ])
    await store.loadSeries()
    let seriesCallsBefore = repository.seriesCalls
    let movieCallsBefore = repository.movieCalls

    await store.downloadBest(language("en", "English"), for: item)

    #expect(repository.seriesCalls > seriesCallsBefore, "the opened section went stale")
    #expect(repository.movieCalls == movieCallsBefore, "an unopened section was fetched")
  }
}

// MARK: - Stub

final class StubBazarrRepository: BazarrRepositoryProtocol, @unchecked Sendable {
  let instance = ServiceInstance(
    kind: .bazarr, name: "Bazarr", baseURL: URL(string: "http://192.0.2.1:6767")!,
    credentials: .apiKey("k"))

  private let lock = NSLock()
  private var storedWanted: [WantedSubtitle]
  private let storedCandidates: [SubtitleCandidate]
  private let storedProviders: [SubtitleProvider]
  private let storedSeries: [BazarrMediaItem]

  var failSections = false
  var failDownloads = false

  private(set) var wantedCalls = 0
  private(set) var providerCalls = 0
  private(set) var candidateCalls = 0
  private(set) var seriesCalls = 0
  private(set) var movieCalls = 0
  private(set) var downloads: [SubtitleCandidate] = []
  private(set) var autoDownloads: [SubtitleLanguage] = []

  init(
    wanted: [WantedSubtitle], candidates: [SubtitleCandidate], providers: [SubtitleProvider],
    series: [BazarrMediaItem]
  ) {
    self.storedWanted = wanted
    self.storedCandidates = candidates
    self.storedProviders = providers
    self.storedSeries = series
  }

  func series() async throws -> [BazarrMediaItem] {
    if failSections { throw AppError.serverUnreachable }
    return lock.withLock {
      seriesCalls += 1
      return storedSeries
    }
  }

  func movies() async throws -> [BazarrMediaItem] {
    if failSections { throw AppError.serverUnreachable }
    return lock.withLock {
      movieCalls += 1
      return []
    }
  }

  func wanted() async throws -> [WantedSubtitle] {
    lock.withLock {
      wantedCalls += 1
      return storedWanted
    }
  }

  func candidates(for item: WantedSubtitle) async throws -> [SubtitleCandidate] {
    lock.withLock {
      candidateCalls += 1
      return storedCandidates
    }
  }

  func download(_ candidate: SubtitleCandidate, for item: WantedSubtitle) async throws {
    if failDownloads { throw AppError.actionRefused("The provider refused it.") }
    lock.withLock {
      downloads.append(candidate)
      satisfy(candidate.language, for: item)
    }
  }

  func downloadBest(_ language: SubtitleLanguage, for item: WantedSubtitle) async throws {
    if failDownloads { throw AppError.actionRefused("No provider had one.") }
    lock.withLock {
      autoDownloads.append(language)
      satisfy(language, for: item)
    }
  }

  /// Removes one language from the row, and the row once nothing is left —
  /// which is what a real Bazarr's next `wanted` read would show.
  private func satisfy(_ language: SubtitleLanguage, for item: WantedSubtitle) {
    storedWanted = storedWanted.compactMap { row in
      guard row.id == item.id else { return row }
      let remaining = row.missing.filter { $0.code != language.code }
      guard !remaining.isEmpty else { return nil }
      return WantedSubtitle(
        title: row.title, subtitle: row.subtitle, seriesID: row.seriesID,
        episodeID: row.episodeID, radarrID: row.radarrID, missing: remaining)
    }
  }

  func providers() async throws -> [SubtitleProvider] {
    if failSections { throw AppError.serverUnreachable }
    return lock.withLock {
      providerCalls += 1
      return storedProviders
    }
  }

  func history() async throws -> [SubtitleHistoryRecord] {
    if failSections { throw AppError.serverUnreachable }
    return []
  }
}
