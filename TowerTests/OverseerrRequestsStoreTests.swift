import Foundation
import Testing
import TowerCore
import TowerData

@testable import Tower

/// The requests list's filtering, pagination, and the two decisions.
@MainActor
@Suite
struct OverseerrRequestsStoreTests {
  private func request(
    id: Int, status: RequestStatus = .pending, media: MediaAvailability = .pending,
    type: OverseerrMediaType = .movie, title: String? = "Example"
  ) -> OverseerrRequest {
    OverseerrRequest(
      id: id, status: status, mediaType: type, mediaID: id, tmdbID: 700_000 + id, tvdbID: nil,
      mediaStatus: media, requestedBy: "Alex", requestedByAvatarURL: nil,
      createdAt: Date(timeIntervalSince1970: 1_700_000_000), updatedAt: nil, is4K: false,
      seasons: [], title: title)
  }

  private func makeStore(
    _ requests: [OverseerrRequest], failing: Bool = false, pageSize: Int = 20
  ) async -> (OverseerrRequestsStore, StubOverseerrRepository) {
    let repository = StubOverseerrRepository(
      requests: requests, failing: failing, pageSize: pageSize)
    let store = OverseerrRequestsStore(repository: repository)
    await store.load()
    return (store, repository)
  }

  // MARK: - Loading and filters

  @Test func theDefaultFilterIsPendingBecauseThatIsTheQueueToWorkThrough() async {
    let (store, repository) = await makeStore([
      request(id: 1), request(id: 2, status: .approved),
    ])

    #expect(store.filter == .pending)
    #expect(repository.filtersRequested == [.pending])
    #expect(store.state.value?.map(\.id) == [1])
  }

  // MARK: - Status filters

  @Test func eachStatusFilterIsAskedOfTheServiceRatherThanAppliedLocally() async throws {
    // Filtering client-side would page through approved requests looking for
    // pending ones.
    let (store, repository) = await makeStore([
      request(id: 1, status: .pending),
      request(id: 2, status: .approved),
      request(id: 3, status: .declined),
      request(id: 4, status: .approved, media: .available),
    ])

    store.filter = .approved
    try await waitUntil { repository.filtersRequested.contains(.approved) }
    #expect(store.state.value?.map(\.id) == [2, 4])

    store.filter = .available
    try await waitUntil { repository.filtersRequested.contains(.available) }
    #expect(store.state.value?.map(\.id) == [4])

    store.filter = .all
    try await waitUntil { repository.filtersRequested.contains(.all) }
    #expect(store.state.value?.count == 4)
  }

  @Test func changingTheFilterStartsFromPageOne() async throws {
    // A filter is a different query, not a view onto what is already loaded.
    let (store, repository) = await makeStore(
      (1...30).map { request(id: $0) }, pageSize: 10)
    await store.loadMore()
    #expect(store.state.value?.count == 20)

    store.filter = .all
    try await waitUntil { repository.filtersRequested.contains(.all) }

    #expect(store.page == 1)
    #expect(store.state.value?.count == 10, "the filter change kept the old pages")
  }

  // MARK: - Pagination

  @Test func loadMoreAppendsTheNextPage() async {
    let (store, _) = await makeStore((1...25).map { request(id: $0) }, pageSize: 10)

    #expect(store.state.value?.count == 10)
    #expect(store.hasMore)

    await store.loadMore()
    #expect(store.state.value?.count == 20)
    #expect(store.hasMore)

    await store.loadMore()
    #expect(store.state.value?.count == 25)
    #expect(!store.hasMore, "the last page still claimed more")
  }

  @Test func aRowArrivingTwiceAcrossPagesIsNotDuplicated() async {
    // A request approved between two page fetches shifts the window, so the
    // same row can arrive twice. `ForEach` over duplicate ids is a runtime
    // warning and a visibly repeated row.
    let (store, repository) = await makeStore((1...20).map { request(id: $0) }, pageSize: 10)
    repository.repeatsLastRowOnNextPage = true

    await store.loadMore()

    let ids = store.state.value?.map(\.id) ?? []
    #expect(ids.count == Set(ids).count, "a duplicate row survived: \(ids)")
  }

  @Test func aFailedPageKeepsWhatIsAlreadyOnScreen() async {
    let (store, repository) = await makeStore((1...25).map { request(id: $0) }, pageSize: 10)
    repository.failNextPage = true

    await store.loadMore()

    guard case .actionFailed(let requests, _) = store.state else {
      Issue.record("expected .actionFailed, got \(store.state)")
      return
    }
    #expect(requests.count == 10, "the loaded page was lost")
    // A failed page keeps paging open, so the next scroll can retry it.
    #expect(store.hasMore, "a failed page ended paging for good")

    repository.failNextPage = false
    await store.loadMore()

    #expect(store.state.value?.count == 20, "the retry did not append the next page")
  }

  @Test func refreshRereadsOnlyTheFirstPage() async {
    // Re-fetching five pages on every pull would make the gesture cost five
    // round trips.
    let (store, repository) = await makeStore((1...30).map { request(id: $0) }, pageSize: 10)
    await store.loadMore()
    await store.loadMore()
    let before = repository.pageCalls

    await store.refresh()

    #expect(repository.pageCalls == before + 1)
    #expect(store.page == 1)
  }

  // MARK: - Approve

  @Test func approvingMovesTheRequestOutOfPending() async {
    let (store, repository) = await makeStore([request(id: 1), request(id: 2)])

    await store.approve(store.state.value![0])

    #expect(repository.approved == [1])
    #expect(store.state.value?.map(\.id) == [2], "the approved request stayed in pending")
  }

  @Test func approvingBumpsTheSuccessCounterThatDrivesTheHaptic() async {
    // The view drives `.sensoryFeedback(.success, trigger:)` off this, and a
    // load must never bump it — otherwise a background refresh buzzes.
    let (store, _) = await makeStore([request(id: 1)])
    #expect(store.lastActionSuccess == 0)

    await store.approve(store.state.value![0])
    #expect(store.lastActionSuccess == 1)

    await store.refresh()
    #expect(store.lastActionSuccess == 1, "a refresh bumped the haptic trigger")
  }

  @Test func aFailedApproveBumpsTheErrorCounterAndKeepsTheList() async {
    let (store, repository) = await makeStore([request(id: 1)])
    repository.failActions = true

    await store.approve(store.state.value![0])

    #expect(store.lastActionFailure == 1)
    #expect(store.lastActionSuccess == 0)
    guard case .actionFailed(let requests, _) = store.state else {
      Issue.record("expected .actionFailed, got \(store.state)")
      return
    }
    #expect(requests.count == 1, "the list was lost to a failed approve")
  }

  @Test func anApprovedRequestStaysVisibleUnderANonPendingFilter() async throws {
    // On the "all" filter it should update in place, not vanish.
    let (store, repository) = await makeStore(
      [request(id: 1), request(id: 2, status: .approved)])
    store.filter = .all
    try await waitUntil { repository.filtersRequested.contains(.all) }

    await store.approve(store.state.value!.first { $0.id == 1 }!)

    #expect(store.state.value?.count == 2, "the row vanished from the all-requests list")
    #expect(store.state.value?.first { $0.id == 1 }?.status == .approved)
  }

  @Test func aDoubleTapCannotApproveTwice() async {
    let (store, repository) = await makeStore([request(id: 1)])
    let target = store.state.value![0]

    async let first: Void = store.approve(target)
    async let second: Void = store.approve(target)
    _ = await (first, second)

    #expect(repository.approved == [1], "approved \(repository.approved.count) times")
  }

  @Test func aServiceThatWontReportTheNewStateStillDropsThePendingRow() async {
    // It is no longer pending, whatever else is true — leaving it would invite
    // a second decision on a decided request.
    let (store, repository) = await makeStore([request(id: 1)])
    repository.failSingleRequestRead = true

    await store.approve(store.state.value![0])

    #expect(store.state.value?.isEmpty == true)
  }

  // MARK: - Decline

  @Test func decliningReachesTheServiceAndClearsThePendingRow() async {
    let (store, repository) = await makeStore([request(id: 1)])

    await store.decline(store.state.value![0])

    #expect(repository.declined == [1])
    #expect(store.state.value?.isEmpty == true)
  }

  /// Polls a condition — the filter's `didSet` kicks off a detached reload, so
  /// the assertion has to wait for it rather than assume it has landed.
  private func waitUntil(
    _ condition: @escaping () -> Bool, timeout: Duration = .seconds(2)
  ) async throws {
    let deadline = ContinuousClock.now + timeout
    while ContinuousClock.now < deadline {
      if condition() { return }
      try await Task.sleep(for: .milliseconds(5))
    }
    Issue.record("condition never became true")
  }
}

// MARK: - Stub

final class StubOverseerrRepository: OverseerrRepositoryProtocol, @unchecked Sendable {
  let instance = ServiceInstance(
    kind: .overseerr, name: "Overseerr", baseURL: URL(string: "http://192.0.2.1:5055")!,
    credentials: .apiKey("k"))

  private let lock = NSLock()
  private var stored: [OverseerrRequest]
  private let failing: Bool
  private let pageSize: Int

  var failActions = false
  var failNextPage = false
  var failSingleRequestRead = false
  var repeatsLastRowOnNextPage = false

  private(set) var filtersRequested: [RequestFilter] = []
  private(set) var pageCalls = 0
  private(set) var approved: [Int] = []
  private(set) var declined: [Int] = []

  init(requests: [OverseerrRequest], failing: Bool = false, pageSize: Int = 20) {
    self.stored = requests
    self.failing = failing
    self.pageSize = pageSize
  }

  private func matching(_ filter: RequestFilter) -> [OverseerrRequest] {
    stored.filter { request in
      switch filter {
      case .all: true
      case .pending: request.status == .pending
      case .approved: request.status == .approved
      case .declined: request.status == .declined
      case .processing: request.mediaStatus == .processing
      case .available: request.mediaStatus == .available
      case .failed: request.status == .failed
      }
    }
  }

  func requests(filter: RequestFilter, page: Int) async throws -> OverseerrRequestPage {
    if failing { throw AppError.serverUnreachable }
    return try lock.withLock {
      if failNextPage, page > 1 { throw AppError.serverUnreachable }
      pageCalls += 1
      filtersRequested.append(filter)
      let all = matching(filter)
      let start = (page - 1) * pageSize
      guard start < all.count else {
        return OverseerrRequestPage(
          requests: [], page: page, pages: max(1, (all.count + pageSize - 1) / pageSize),
          totalResults: all.count)
      }
      var slice = Array(all[start..<min(start + pageSize, all.count)])
      // The window-shift case: page 2 repeats page 1's last row.
      if repeatsLastRowOnNextPage, page > 1, let previous = all[safe: start - 1] {
        slice.insert(previous, at: 0)
      }
      return OverseerrRequestPage(
        requests: slice, page: page,
        pages: max(1, (all.count + pageSize - 1) / pageSize), totalResults: all.count)
    }
  }

  func request(id: Int) async throws -> OverseerrRequest {
    if failing || failSingleRequestRead { throw AppError.serverUnreachable }
    guard let match = lock.withLock({ stored.first { $0.id == id } }) else {
      throw AppError.unknown("missing")
    }
    return match
  }

  func approve(requestID: Int) async throws {
    if failing || failActions { throw AppError.serverUnreachable }
    lock.withLock {
      approved.append(requestID)
      stored = stored.map { $0.id == requestID ? $0.settingStatus(.approved) : $0 }
    }
  }

  func decline(requestID: Int) async throws {
    if failing || failActions { throw AppError.serverUnreachable }
    lock.withLock {
      declined.append(requestID)
      stored = stored.map { $0.id == requestID ? $0.settingStatus(.declined) : $0 }
    }
  }

  func search(term: String) async throws -> [OverseerrSearchResult] { [] }
  func seasons(tmdbID: Int) async throws -> [OverseerrSeason] { [] }

  @discardableResult
  func submit(_ request: SubmitRequest) async throws -> OverseerrRequest {
    throw AppError.unknown("unused")
  }

  func issues(includeResolved: Bool) async throws -> [OverseerrIssue] { [] }
  func comment(issueID: Int, message: String) async throws {}
  func setIssueResolved(_ isResolved: Bool, issueID: Int) async throws {}
}

extension OverseerrRequest {
  fileprivate func settingStatus(_ status: RequestStatus) -> OverseerrRequest {
    OverseerrRequest(
      id: id, status: status, mediaType: mediaType, mediaID: mediaID, tmdbID: tmdbID,
      tvdbID: tvdbID, mediaStatus: mediaStatus, requestedBy: requestedBy,
      requestedByAvatarURL: requestedByAvatarURL, createdAt: createdAt, updatedAt: updatedAt,
      is4K: is4K, seasons: seasons, title: title, posterURL: posterURL)
  }
}

extension Array {
  fileprivate subscript(safe index: Int) -> Element? {
    indices.contains(index) ? self[index] : nil
  }
}
