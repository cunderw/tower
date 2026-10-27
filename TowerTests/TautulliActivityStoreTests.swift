import Foundation
import Testing
import TowerCore
import TowerData

@testable import Tower

/// Tautulli's activity screen and its one mutation.
@MainActor
@Suite
struct TautulliActivityStoreTests {
  private func session(
    key: String, user: String, decision: TautulliStreamDecision,
    video: TautulliStreamDecision? = nil, audio: TautulliStreamDecision? = nil,
    bandwidth: Int = 1_000, location: TautulliStreamLocation = .lan
  ) -> TautulliSession {
    TautulliSession(
      sessionKey: key, sessionID: key, userID: nil, user: user, title: "Something",
      subtitle: nil, mediaType: "movie", player: "Apple TV", platform: nil, product: nil,
      ipAddress: nil, state: .playing, decision: decision,
      videoDecision: video ?? decision, audioDecision: audio ?? decision,
      location: location, isSecure: true, qualityProfile: nil, bandwidthKbps: bandwidth,
      progressPercent: 20, viewOffsetMilliseconds: 0, durationMilliseconds: 1_000,
      transcodeProgressPercent: nil, container: nil, videoCodec: nil, audioCodec: nil,
      thumbnailPath: nil)
  }

  private func activity(_ sessions: [TautulliSession]) -> TautulliActivity {
    TautulliActivity(
      streamCount: sessions.count,
      directPlayCount: sessions.filter { $0.decision == .directPlay }.count,
      directStreamCount: sessions.filter { $0.decision == .directStream }.count,
      transcodeCount: sessions.filter { $0.decision == .transcode }.count,
      totalBandwidthKbps: sessions.reduce(0) { $0 + $1.bandwidthKbps },
      lanBandwidthKbps: sessions.filter { $0.location == .lan }
        .reduce(0) { $0 + $1.bandwidthKbps },
      wanBandwidthKbps: sessions.filter { $0.location != .lan }
        .reduce(0) { $0 + $1.bandwidthKbps },
      sessions: sessions)
  }

  private func makeStore(
    _ sessions: [TautulliSession]
  ) async -> (TautulliActivityStore, StubTautulliRepository) {
    let repository = StubTautulliRepository(activity: activity(sessions))
    let store = TautulliActivityStore(repository: repository)
    await store.load()
    return (store, repository)
  }

  // MARK: - Loading

  @Test func transcodesSortAboveDirectPlays() async throws {
    // The reason to open this screen when the server is struggling is to find
    // what is costing it work, so that goes first.
    let (store, _) = await makeStore([
      session(key: "1", user: "Amy", decision: .directPlay),
      session(key: "2", user: "Zoe", decision: .transcode),
    ])

    #expect(store.sessions.map(\.sessionKey) == ["2", "1"])
  }

  @Test func anIdleServerIsEmptyRatherThanFailed() async throws {
    let (store, _) = await makeStore([])

    #expect(store.isEmpty)
    #expect(store.state.value == .empty)
  }

  @Test func aRefreshDoesNotPassThroughLoading() async throws {
    let (store, repository) = await makeStore([
      session(key: "1", user: "Amy", decision: .directPlay)
    ])
    repository.current = activity([session(key: "2", user: "Zoe", decision: .transcode)])

    await store.refresh()

    // A spinner every 30 seconds over a correct list would be the most visible
    // thing on the screen.
    #expect(store.state.value?.sessions.map(\.sessionKey) == ["2"])
    #expect(store.isLoadInFlight == false)
  }

  // MARK: - Terminating

  @Test func terminatingRemovesTheStreamAndItsShareOfTheBandwidth() async throws {
    let (store, repository) = await makeStore([
      session(key: "1", user: "Amy", decision: .directPlay, bandwidth: 2_000),
      session(key: "2", user: "Zoe", decision: .transcode, bandwidth: 4_000, location: .wan),
    ])
    let target = try #require(store.sessions.first(where: { $0.sessionKey == "2" }))

    await store.terminate(target, message: "Stopped from Tower")

    #expect(repository.terminated == [Terminated(key: "2", message: "Stopped from Tower")])
    // Removed locally rather than refetched: Tautulli's session list lags a
    // terminate, so a refetch would put the row back for one poll.
    #expect(repository.activityCalls == 1)
    let state = store.state.value
    #expect(state?.sessions.map(\.sessionKey) == ["1"])
    #expect(state?.streamCount == 1)
    #expect(state?.transcodeCount == 0)
    #expect(state?.totalBandwidthKbps == 2_000)
    #expect(state?.wanBandwidthKbps == 0)
    #expect(state?.lanBandwidthKbps == 2_000)
  }

  @Test func aFailedTerminateKeepsTheStreamOnScreen() async throws {
    let (store, repository) = await makeStore([
      session(key: "1", user: "Amy", decision: .directPlay)
    ])
    repository.failTerminate = true
    let target = try #require(store.sessions.first)

    await store.terminate(target, message: nil)

    // Dropping the row on a failure would tell the user it worked.
    #expect(store.state.value?.sessions.count == 1)
    #expect(store.actionError != nil)
    #expect(store.lastActionFailure == 1)
    #expect(store.lastActionSuccess == 0)
  }

  @Test func aStreamWithNoSessionKeyCannotBeTerminated() async throws {
    let (store, repository) = await makeStore([
      session(key: "", user: "Amy", decision: .directPlay)
    ])
    let target = try #require(store.sessions.first)

    #expect(store.canTerminate(target) == false)
    await store.terminate(target, message: nil)

    // Tautulli's terminate takes a session key; sending an empty one would
    // fail server-side after telling the user it was stopping.
    #expect(repository.terminated.isEmpty)
    #expect(store.state.value?.sessions.count == 1)
  }

  @Test func aTerminateWithoutAMessageSendsNone() async throws {
    let (store, repository) = await makeStore([
      session(key: "7", user: "Amy", decision: .directPlay)
    ])

    await store.terminate(try #require(store.sessions.first), message: nil)

    #expect(repository.terminated == [Terminated(key: "7", message: nil)])
    #expect(store.lastActionSuccess == 1)
  }
}

// MARK: - History, users, and libraries

@MainActor
@Suite
struct TautulliInsightsStoreTests {
  private func record(id: Int, user: String, userID: Int, media: String) -> TautulliHistoryRecord
  {
    TautulliHistoryRecord(
      id: id, date: Date(timeIntervalSince1970: 1_755_000_000), user: user, userID: userID,
      title: "Something", subtitle: nil, mediaType: media, player: "Apple TV", platform: nil,
      decision: .directPlay, watchStatus: .watched, percentComplete: 100,
      playDurationSeconds: 3_600)
  }

  private func makeStore() -> (TautulliActivityStore, StubTautulliRepository) {
    let repository = StubTautulliRepository(activity: .empty)
    repository.history = [
      record(id: 1, user: "Amy", userID: 5, media: "episode"),
      record(id: 2, user: "Zoe", userID: 7, media: "movie"),
    ]
    repository.users = [
      TautulliUser(
        id: 5, name: "Amy", plays: 412, totalTimeSeconds: 90_000,
        lastSeen: Date(timeIntervalSince1970: 1_755_000_000), lastPlayed: "Something",
        platform: "tvOS", player: "Apple TV", thumbnailPath: nil, isActive: true),
      TautulliUser(
        id: 7, name: "Zoe", plays: 0, totalTimeSeconds: 0, lastSeen: nil, lastPlayed: nil,
        platform: nil, player: nil, thumbnailPath: nil, isActive: false),
    ]
    repository.libraries = [
      TautulliLibrary(
        id: 1, name: "Movies", type: "movie", count: 500, parentCount: nil, childCount: nil,
        plays: 1_200, totalTimeSeconds: 100, lastAccessed: nil, thumbnailPath: nil)
    ]
    return (TautulliActivityStore(repository: repository), repository)
  }

  @Test func aSectionLoadsOnceAndKeepsWhatItGot() async throws {
    let (store, repository) = makeStore()

    await store.loadUsers()
    await store.loadUsers()

    #expect(store.users.value?.count == 2)
    #expect(repository.userCalls == 1)
    // A pull-to-refresh is the deliberate second fetch.
    await store.loadUsers(force: true)
    #expect(repository.userCalls == 2)
  }

  @Test func historyFiltersCompose() async throws {
    let (store, repository) = makeStore()
    store.historyFilter.userID = 5
    store.historyFilter.mediaType = "episode"
    store.historyFilter.search = "lights"

    await store.loadHistory()

    // All three go to Tautulli in one request — it narrows in SQL, and a
    // local filter over one page would search only that page.
    let filter = try #require(repository.historyFilters.last)
    #expect(filter.userID == 5)
    #expect(filter.mediaType == "episode")
    #expect(filter.search == "lights")
    #expect(repository.historyLengths.last == TautulliActivityStore.historyPageSize)
  }

  @Test func changingAFilterBumpsTheReloadToken() async throws {
    let (store, _) = makeStore()
    let before = store.historyReloadToken

    store.historyFilter.mediaType = "movie"

    #expect(store.historyReloadToken == before + 1)
    // Setting the same value again is not a change, and must not refetch.
    store.historyFilter.mediaType = "movie"
    #expect(store.historyReloadToken == before + 1)
  }

  @Test func reloadingHistoryRefetchesEvenThoughAPageIsAlreadyLoaded() async throws {
    let (store, repository) = makeStore()
    await store.loadHistory()
    store.historyFilter.mediaType = "movie"

    await store.reloadHistory()

    #expect(repository.historyFilters.count == 2)
    #expect(repository.historyFilters.last?.mediaType == "movie")
  }

  @Test func aFilterSetAwayFromHistoryRefetchesOnTheWayBack() async throws {
    // "Filter History" on a user's screen sets the filter while History is not
    // showing, so nothing refetches then. Arriving on History is an unforced
    // load, and it must not keep a page fetched under the old filter.
    let (store, repository) = makeStore()
    await store.loadHistory()
    store.historyFilter.userID = 5

    await store.loadHistory()

    #expect(repository.historyFilters.count == 2)
    #expect(repository.historyFilters.last?.userID == 5)
    // With nothing changed since, the page is kept.
    await store.loadHistory()
    #expect(repository.historyFilters.count == 2)
  }

  @Test func aUserDrillInDoesNotCountAsTheListsFetch() async throws {
    // The drill-in fetches with that user's filter, but for its own screen.
    // The list behind it still holds the unfiltered page, so filtering to the
    // same user afterwards must refetch the list.
    let (store, repository) = makeStore()
    await store.loadHistory()
    await store.loadUsers()
    let user = try #require(store.users.value?.first { $0.id == 5 })
    _ = await store.history(for: user)
    store.historyFilter.userID = 5

    await store.loadHistory()

    #expect(repository.historyFilters.count == 3)
    #expect(repository.historyFilters.last?.userID == 5)
  }

  @Test func aCancelledReloadKeepsThePageOnScreen() async throws {
    // Each keystroke in the search field cancels the previous one's fetch.
    // That cancellation is not an error to show; the page stays until the
    // fetch that replaced it lands.
    let (store, repository) = makeStore()
    await store.loadHistory()
    store.historyFilter.search = "l"
    repository.nextHistoryError = CancellationError()

    await store.reloadHistory()

    #expect(store.history.value?.records.count == 2)
  }

  @Test func anOlderFiltersPageLandingLateIsDropped() async throws {
    // The section's first load and the filter's reload are separate tasks, so
    // the page for an older filter can arrive after the newer one's.
    let (store, repository) = makeStore()
    store.historyFilter.userID = 7
    repository.holdNextHistory()
    let older = Task { await store.reloadHistory() }
    var parked = false
    for _ in 0..<1_000 where !parked {
      await Task.yield()
      parked = repository.isHoldingHistory
    }
    try #require(parked, "the first fetch never reached the stub")

    store.historyFilter.userID = 5
    await store.reloadHistory()
    repository.releaseHeldHistory()
    await older.value

    let records = try #require(store.history.value?.records)
    #expect(!records.isEmpty)
    #expect(records.allSatisfy { $0.userID == 5 }, "the older filter's page replaced the newer one")
  }

  @Test func theFilteredFlagTellsNoMatchesApartFromNoHistory() async throws {
    let (store, _) = makeStore()

    #expect(store.isHistoryFiltered == false)
    store.historyFilter.search = "   "
    // Whitespace is not a filter; treating it as one would show "no matches"
    // over an empty database.
    #expect(store.isHistoryFiltered == false)
    store.historyFilter.search = "lights"
    #expect(store.isHistoryFiltered)
  }

  @Test func aUserDrillInFetchesThatUsersHistoryRatherThanSlicingThePage() async throws {
    let (store, repository) = makeStore()
    await store.loadUsers()
    let user = try #require(store.users.value?.first)

    let history = await store.history(for: user)

    #expect(history.value != nil)
    // The user's hundredth play may be nowhere near the newest hundred, so
    // this has to be its own filtered request.
    #expect(repository.historyFilters.last?.userID == 5)
    // And it must not disturb the list behind it.
    #expect(store.historyFilter.userID == nil)
  }

  @Test func theUserFilterChipCanNameTheUser() async throws {
    let (store, _) = makeStore()
    await store.loadUsers()

    #expect(store.userName(id: 5) == "Amy")
    #expect(store.userName(id: 99) == nil)
  }

  @Test func aFailedSectionKeepsItsErrorToItself() async throws {
    let (store, repository) = makeStore()
    await store.load()
    await store.loadUsers()
    repository.failingSections = [.libraries]

    await store.loadLibraries()

    #expect(store.libraries.error != nil)
    // The sections already on screen survive it: a libraries failure must not
    // blank the users list, or the activity the user is actually looking at.
    // `.empty` is a loaded idle server; a blanked activity reads `nil`.
    #expect(store.users.value?.count == 2)
    #expect(store.state.value == .empty)
  }
}

// MARK: - Stub

struct Terminated: Equatable, Sendable {
  let key: String
  let message: String?
}

final class StubTautulliRepository: TautulliRepositoryProtocol, @unchecked Sendable {
  let instance = ServiceInstance(
    kind: .tautulli, name: "Tautulli", baseURL: URL(string: "http://192.0.2.1:8181")!,
    credentials: .apiKey("k"))

  private let lock = NSLock()
  private var storedActivity: TautulliActivity
  private var storedCalls = 0
  private var storedTerminated: [Terminated] = []

  var failTerminate = false

  init(activity: TautulliActivity) {
    self.storedActivity = activity
  }

  /// Not named `activity`: the protocol requirement below already owns that
  /// name, and a property plus a method cannot share one.
  var current: TautulliActivity {
    get { lock.withLock { storedActivity } }
    set { lock.withLock { storedActivity = newValue } }
  }

  var activityCalls: Int { lock.withLock { storedCalls } }
  var terminated: [Terminated] { lock.withLock { storedTerminated } }

  func activity() async throws -> TautulliActivity {
    lock.withLock {
      storedCalls += 1
      return storedActivity
    }
  }

  func terminate(sessionKey: String, message: String?) async throws {
    if failTerminate { throw AppError.serverUnreachable }
    lock.withLock { storedTerminated.append(Terminated(key: sessionKey, message: message)) }
  }

  var history: [TautulliHistoryRecord] = []
  var users: [TautulliUser] = []
  var libraries: [TautulliLibrary] = []

  enum Section { case history, users, libraries }
  /// The sections whose fetch throws, each on its own so a test can fail one
  /// and watch the others.
  var failingSections: Set<Section> = []

  private var storedHistoryFilters: [TautulliHistoryFilter] = []
  private var storedHistoryLengths: [Int] = []
  private var storedUserCalls = 0

  var historyFilters: [TautulliHistoryFilter] { lock.withLock { storedHistoryFilters } }
  var historyLengths: [Int] { lock.withLock { storedHistoryLengths } }
  var userCalls: Int { lock.withLock { storedUserCalls } }

  /// What the next history fetch throws, once, in place of a page.
  var nextHistoryError: (any Error)? {
    get { lock.withLock { storedNextHistoryError } }
    set { lock.withLock { storedNextHistoryError = newValue } }
  }
  private var storedNextHistoryError: (any Error)?

  /// Parks the next history fetch until `releaseHeldHistory()`, so a test can
  /// land a later fetch before an earlier one.
  func holdNextHistory() { lock.withLock { shouldHoldHistory = true } }
  private var shouldHoldHistory = false
  private var heldHistory: CheckedContinuation<Void, Never>?

  var isHoldingHistory: Bool { lock.withLock { heldHistory != nil } }

  func releaseHeldHistory() {
    let held = lock.withLock {
      defer { heldHistory = nil }
      return heldHistory
    }
    held?.resume()
  }

  func history(
    filter: TautulliHistoryFilter, start: Int, length: Int
  ) async throws -> TautulliHistoryPage {
    if failingSections.contains(.history) { throw AppError.serverUnreachable }
    let hold = lock.withLock {
      defer { shouldHoldHistory = false }
      return shouldHoldHistory
    }
    if hold {
      await withCheckedContinuation { continuation in
        lock.withLock { heldHistory = continuation }
      }
    }
    let error = lock.withLock {
      defer { storedNextHistoryError = nil }
      return storedNextHistoryError
    }
    if let error { throw error }
    return lock.withLock {
      storedHistoryFilters.append(filter)
      storedHistoryLengths.append(length)
      let records = filter.userID.map { id in history.filter { $0.userID == id } } ?? history
      return TautulliHistoryPage(
        records: records, filteredCount: records.count, totalCount: history.count)
    }
  }

  func users() async throws -> [TautulliUser] {
    if failingSections.contains(.users) { throw AppError.serverUnreachable }
    return lock.withLock {
      storedUserCalls += 1
      return users
    }
  }

  func libraries() async throws -> [TautulliLibrary] {
    if failingSections.contains(.libraries) { throw AppError.serverUnreachable }
    return libraries
  }
}
