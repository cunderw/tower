import Foundation
import Testing
import TowerCore
import TowerData

@testable import Tower

/// Search, the two request shapes, and the states that replace a Request
/// button.
@MainActor
@Suite
struct OverseerrSearchStoreTests {
  private func result(
    id: Int, type: OverseerrMediaType = .movie, title: String = "Example",
    status: MediaAvailability? = nil
  ) -> OverseerrSearchResult {
    OverseerrSearchResult(
      id: id, mediaType: type, title: title, overview: nil, posterURL: nil,
      releaseDate: Date(timeIntervalSince1970: 1_700_000_000), mediaStatus: status)
  }

  private func makeStore(
    _ results: [OverseerrSearchResult], seasons: [OverseerrSeason] = []
  ) -> (OverseerrSearchStore, SearchStubRepository) {
    let repository = SearchStubRepository(results: results, seasons: seasons)
    return (OverseerrSearchStore(repository: repository), repository)
  }

  private func seasons(_ numbers: [Int]) -> [OverseerrSeason] {
    numbers.map {
      OverseerrSeason(seasonNumber: $0, name: "Season \($0)", episodeCount: 10, airDate: nil)
    }
  }

  // MARK: - Search

  @Test func searchingRunsOnSubmitNotPerKeystroke() async {
    let (store, repository) = makeStore([result(id: 1)])

    store.searchText = "har"
    #expect(repository.searches.isEmpty, "typing alone reached the service")

    await store.search()
    #expect(repository.searches == ["har"])
  }

  @Test func anEmptyTermIsNotASearch() async {
    let (store, repository) = makeStore([result(id: 1)])
    store.searchText = "   "

    await store.search()

    #expect(repository.searches.isEmpty)
    #expect(!store.canSearch)
  }

  @Test func theEmptyStateRemembersWhatWasActuallySearchedFor() async {
    // Otherwise it says "nothing matched" against a box the user has retyped.
    let (store, _) = makeStore([])
    store.searchText = "  zzz  "

    await store.search()

    #expect(store.lastSearchedTerm == "zzz")
  }

  // MARK: - Availability replaces the button

  @Test func mediaAlreadyInTheLibraryShowsItsStateInsteadOfARequestButton() {
    // Offering Request on something already available files a duplicate that
    // Overseerr rejects, which reads as the app being broken.
    let (store, _) = makeStore([])

    let available = result(id: 1, status: .available)
    #expect(!store.isRequestable(available))
    #expect(store.stateDescription(for: available) == "Available")

    let processing = result(id: 2, status: .processing)
    #expect(!store.isRequestable(processing))
    #expect(store.stateDescription(for: processing) == "Processing")

    let partial = result(id: 3, status: .partiallyAvailable)
    #expect(!store.isRequestable(partial))

    // Not requested at all: the button stands.
    let fresh = result(id: 4, status: .unknown)
    #expect(store.isRequestable(fresh))
    #expect(store.stateDescription(for: fresh) == nil)

    let unknownToOverseerr = result(id: 5, status: nil)
    #expect(store.isRequestable(unknownToOverseerr))
  }

  @Test func aRowRequestedInThisSessionStopsOfferingTheButton() async {
    // Overseerr's `mediaInfo` only refreshes on a re-query, so without this the
    // row would still offer Request right after one succeeded.
    let (store, _) = makeStore([result(id: 1)])
    store.searchText = "x"
    await store.search()

    await store.beginRequest(for: store.state.value![0])
    _ = await store.submit()

    #expect(!store.isRequestable(result(id: 1)))
    #expect(store.stateDescription(for: result(id: 1)) == "Requested")
  }

  // MARK: - Movie vs series

  @Test func requestingAMovieIsOneConfirmWithNoSeasonStep() async {
    let (store, repository) = makeStore([result(id: 1, type: .movie)])
    store.searchText = "x"
    await store.search()

    await store.beginRequest(for: store.state.value![0])

    let draft = try! #require(store.requesting)
    #expect(!draft.isTV)
    #expect(draft.canSubmit, "a movie draft wasn't immediately submittable")
    #expect(repository.seasonLookups.isEmpty, "a movie triggered a season lookup")
  }

  @Test func requestingASeriesLoadsItsSeasonsAndSelectsThemAll() async {
    // "I want the show" is the common ask, and an empty selection would make
    // the confirm button start disabled.
    let (store, repository) = makeStore(
      [result(id: 2, type: .tv)], seasons: seasons([1, 2, 3]))
    store.searchText = "x"
    await store.search()

    await store.beginRequest(for: store.state.value![0])

    let draft = try! #require(store.requesting)
    #expect(draft.isTV)
    #expect(repository.seasonLookups == [2])
    #expect(draft.seasons.value?.count == 3)
    #expect(draft.selectedSeasons == [1, 2, 3])
    #expect(draft.isEverySeasonSelected)
    #expect(draft.canSubmit)
  }

  @Test func aSeriesWithNoSeasonsSelectedCannotBeSubmitted() async {
    let (store, _) = makeStore([result(id: 2, type: .tv)], seasons: seasons([1, 2]))
    store.searchText = "x"
    await store.search()
    await store.beginRequest(for: store.state.value![0])

    store.clearSeasonSelection()

    #expect(store.requesting?.canSubmit == false)
  }

  @Test func togglingSeasonsAddsAndRemoves() async {
    let (store, _) = makeStore([result(id: 2, type: .tv)], seasons: seasons([1, 2, 3]))
    store.searchText = "x"
    await store.search()
    await store.beginRequest(for: store.state.value![0])

    store.toggleSeason(2)
    #expect(store.requesting?.selectedSeasons == [1, 3])
    #expect(store.requesting?.isEverySeasonSelected == false)

    store.toggleSeason(2)
    #expect(store.requesting?.selectedSeasons == [1, 2, 3])
  }

  @Test func aPartialSelectionSendsExactlyThoseSeasons() async {
    let (store, repository) = makeStore(
      [result(id: 2, type: .tv)], seasons: seasons([1, 2, 3]))
    store.searchText = "x"
    await store.search()
    await store.beginRequest(for: store.state.value![0])
    store.toggleSeason(2)

    _ = await store.submit()

    let submitted = try! #require(repository.submitted.last)
    #expect(submitted.seasons == [1, 3])
    #expect(submitted.mediaType == .tv)
  }

  @Test func everySeasonSelectedSendsTheWholeSeriesRatherThanAList() async {
    // Which is what Overseerr's own UI does, and what the DTO turns into an
    // omitted key.
    let (store, repository) = makeStore(
      [result(id: 2, type: .tv)], seasons: seasons([1, 2, 3]))
    store.searchText = "x"
    await store.search()
    await store.beginRequest(for: store.state.value![0])

    _ = await store.submit()

    #expect(repository.submitted.last?.seasons.isEmpty == true)
  }

  @Test func aSeasonLookupFailureIsShownRatherThanBlockingTheSheet() async {
    let (store, repository) = makeStore([result(id: 2, type: .tv)])
    repository.failSeasons = true
    store.searchText = "x"
    await store.search()

    await store.beginRequest(for: store.state.value![0])

    guard case .failed = store.requesting?.seasons else {
      Issue.record("expected .failed, got \(String(describing: store.requesting?.seasons))")
      return
    }
    #expect(store.requesting != nil, "the sheet closed on a season lookup failure")
  }

  // MARK: - Submitting

  @Test func aSuccessfulRequestClosesTheSheetAndRefreshesTheRequestsList() async {
    // A request has to *appear in the requests list*, so the list is re-read
    // rather than the sheet closing on a 200.
    let repository = SearchStubRepository(results: [result(id: 1)], seasons: [])
    let requests = OverseerrRequestsStore(repository: repository)
    await requests.load()
    let store = OverseerrSearchStore(repository: repository, requestsStore: requests)
    store.searchText = "x"
    await store.search()
    await store.beginRequest(for: store.state.value![0])
    let listCallsBefore = repository.listCalls

    let closed = await store.submit()

    #expect(closed)
    #expect(store.requesting == nil)
    #expect(store.lastActionSuccess == 1)
    #expect(repository.listCalls > listCallsBefore, "the requests list was never re-read")
  }

  @Test func aRejectedRequestKeepsTheSheetAndItsSeasonSelection() async {
    // A rejected request is usually a permissions problem, not a reason to
    // pick seasons again.
    let (store, repository) = makeStore(
      [result(id: 2, type: .tv)], seasons: seasons([1, 2, 3]))
    store.searchText = "x"
    await store.search()
    await store.beginRequest(for: store.state.value![0])
    store.toggleSeason(3)
    repository.failSubmit = true

    let closed = await store.submit()

    #expect(!closed)
    let draft = try! #require(store.requesting)
    #expect(draft.error != nil)
    #expect(draft.selectedSeasons == [1, 2], "the season selection was lost")
    #expect(!draft.isSubmitting)
    #expect(store.lastActionFailure == 1)
  }

  @Test func anAlreadyAvailableResultCannotBeginARequestAtAll() async {
    let (store, repository) = makeStore([result(id: 1, status: .available)])
    store.searchText = "x"
    await store.search()

    await store.beginRequest(for: store.state.value![0])

    #expect(store.requesting == nil)
    #expect(repository.submitted.isEmpty)
  }
}

// MARK: - Stub

final class SearchStubRepository: OverseerrRepositoryProtocol, @unchecked Sendable {
  let instance = ServiceInstance(
    kind: .overseerr, name: "Overseerr", baseURL: URL(string: "http://192.0.2.1:5055")!,
    credentials: .apiKey("k"))

  private let lock = NSLock()
  private let results: [OverseerrSearchResult]
  private let seasonList: [OverseerrSeason]

  var failSeasons = false
  var failSubmit = false

  private(set) var searches: [String] = []
  private(set) var seasonLookups: [Int] = []
  private(set) var submitted: [SubmitRequest] = []
  private(set) var listCalls = 0

  init(results: [OverseerrSearchResult], seasons: [OverseerrSeason]) {
    self.results = results
    self.seasonList = seasons
  }

  func requests(filter: RequestFilter, page: Int) async throws -> OverseerrRequestPage {
    lock.withLock {
      listCalls += 1
      return OverseerrRequestPage(requests: [], page: page, pages: 1, totalResults: 0)
    }
  }

  func request(id: Int) async throws -> OverseerrRequest { throw AppError.unknown("unused") }
  func approve(requestID: Int) async throws {}
  func decline(requestID: Int) async throws {}

  func search(term: String) async throws -> [OverseerrSearchResult] {
    lock.withLock {
      searches.append(term)
      return results
    }
  }

  func seasons(tmdbID: Int) async throws -> [OverseerrSeason] {
    if failSeasons { throw AppError.serverUnreachable }
    return lock.withLock {
      seasonLookups.append(tmdbID)
      return seasonList
    }
  }

  @discardableResult
  func submit(_ request: SubmitRequest) async throws -> OverseerrRequest {
    if failSubmit { throw AppError.actionRefused("You don't have permission to request that.") }
    lock.withLock { submitted.append(request) }
    return OverseerrRequest(
      id: 999, status: .pending, mediaType: request.mediaType, mediaID: request.mediaID,
      tmdbID: request.mediaID, tvdbID: nil, mediaStatus: .pending, requestedBy: "You",
      requestedByAvatarURL: nil, createdAt: Date(), updatedAt: nil, is4K: request.is4K,
      seasons: request.seasons)
  }

  func issues(includeResolved: Bool) async throws -> [OverseerrIssue] { [] }
  func comment(issueID: Int, message: String) async throws {}
  func setIssueResolved(_ isResolved: Bool, issueID: Int) async throws {}
}
