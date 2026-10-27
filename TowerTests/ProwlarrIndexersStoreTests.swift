import Foundation
import Testing
import TowerCore
import TowerData

@testable import Tower

/// The indexer list's toggle, test, and stats.
@MainActor
@Suite
struct ProwlarrIndexersStoreTests {
  private func indexer(
    id: Int, name: String, enabled: Bool = true, failing: Bool = false
  ) -> ProwlarrIndexer {
    ProwlarrIndexer(
      id: id, name: name, definitionName: name, implementation: "Cardigann",
      isEnabled: enabled, downloadProtocol: .usenet, privacy: .publicIndexer, priority: 25,
      supportsRSS: true, supportsSearch: true, fields: [], tagIDs: [],
      failureMessage: failing ? "Recent failures" : nil,
      disabledUntil: failing ? Date().addingTimeInterval(3_600) : nil)
  }

  private func stats(id: Int, queries: Int, failed: Int) -> IndexerStats {
    IndexerStats(
      indexerID: id, indexerName: "Indexer \(id)", averageResponseTimeMilliseconds: 400,
      queries: queries, grabs: 5, failedQueries: failed, failedGrabs: 0)
  }

  private func makeStore(
    _ indexers: [ProwlarrIndexer], stats: [IndexerStats] = []
  ) async -> (ProwlarrIndexersStore, StubProwlarrRepository) {
    let repository = StubProwlarrRepository(indexers: indexers, stats: stats)
    let store = ProwlarrIndexersStore(repository: repository)
    await store.load()
    return (store, repository)
  }

  // MARK: - Loading

  @Test func theListLoadsWithItsStats() async {
    let (store, _) = await makeStore(
      [indexer(id: 1, name: "Alpha")], stats: [stats(id: 1, queries: 100, failed: 2)])

    #expect(store.state.value?.count == 1)
    #expect(store.stats(for: store.state.value![0])?.queries == 100)
  }

  @Test func aStatsFailureDoesNotCostTheIndexers() async {
    // A Prowlarr that answers /indexer but not /indexerstats should still show
    // its indexers.
    let (store, repository) = await makeStore([indexer(id: 1, name: "Alpha")])
    repository.failStats = true
    await store.refresh()

    #expect(store.state.value?.count == 1, "the list was lost to a stats failure")
    #expect(store.stats.isEmpty)
  }

  @Test func historyIsNotLoadedUntilItsSectionIsOpened() async {
    let (store, repository) = await makeStore([indexer(id: 1, name: "Alpha")])

    #expect(repository.historyCalls == 0)
    await store.loadHistory()
    #expect(repository.historyCalls == 1)

    await store.loadHistory()
    #expect(repository.historyCalls == 1, "history refetched on a second visit")
  }

  @Test func searchMatchesNameAndDefinition() async {
    let (store, _) = await makeStore([
      indexer(id: 1, name: "Alpha"), indexer(id: 2, name: "Beta"),
    ])

    store.searchText = "bet"
    #expect(store.filteredIndexers.map(\.id) == [2])
  }

  // MARK: - A failing indexer is distinct

  @Test func aFailingIndexerIsMarkedAndCounted() async {
    let (store, _) = await makeStore([
      indexer(id: 1, name: "Alpha"),
      indexer(id: 2, name: "Beta", failing: true),
      indexer(id: 3, name: "Gamma", failing: true),
    ])

    #expect(store.failingCount == 2)
    #expect(store.state.value?.first { $0.id == 2 }?.isFailing == true)
    #expect(store.state.value?.first { $0.id == 1 }?.isFailing == false)
  }

  @Test func aDisabledIndexerIsNotTheSameAsAFailingOne() async {
    // The user turning one off and Prowlarr taking one out of rotation are
    // different facts, and the row says different things about them.
    let (store, _) = await makeStore([indexer(id: 1, name: "Alpha", enabled: false)])

    let row = try! #require(store.state.value?.first)
    #expect(!row.isEnabled)
    #expect(!row.isFailing)
    #expect(store.failingCount == 0)
  }

  // MARK: - Toggle in place

  @Test func togglingPatchesTheRowWithoutRefetchingTheList() async {
    // The whole list is a two-request round trip (indexers plus stats), and
    // nothing else changes when one indexer is enabled.
    let (store, repository) = await makeStore([
      indexer(id: 1, name: "Alpha"), indexer(id: 2, name: "Beta"),
    ])
    let listCallsBefore = repository.listCalls

    await store.setEnabled(false, for: store.state.value![0])

    #expect(repository.enableWrites == [EnableWrite(id: 1, enabled: false)])
    #expect(repository.listCalls == listCallsBefore, "the list was refetched after a toggle")
    #expect(store.state.value?.first { $0.id == 1 }?.isEnabled == false)
    #expect(store.state.value?.first { $0.id == 2 }?.isEnabled == true, "another row moved")
  }

  @Test func aFailedToggleKeepsTheListAndLeavesTheRowAlone() async {
    let (store, repository) = await makeStore([indexer(id: 1, name: "Alpha")])
    repository.failActions = true

    await store.setEnabled(false, for: store.state.value![0])

    #expect(store.lastActionFailure == 1)
    guard case .actionFailed(let indexers, _) = store.state else {
      Issue.record("expected .actionFailed, got \(store.state)")
      return
    }
    #expect(indexers.count == 1)
    #expect(indexers[0].isEnabled, "the row flipped despite the failure")
  }

  @Test func aDoubleTapCannotToggleTwice() async {
    let (store, repository) = await makeStore([indexer(id: 1, name: "Alpha")])
    let target = store.state.value![0]

    async let first: Void = store.setEnabled(false, for: target)
    async let second: Void = store.setEnabled(false, for: target)
    _ = await (first, second)

    #expect(repository.enableWrites.count == 1)
  }

  // MARK: - Test in place

  @Test func aPassingTestIsRecordedOnTheRow() async {
    let (store, _) = await makeStore([indexer(id: 1, name: "Alpha")])

    await store.test(store.state.value![0])

    let result = try! #require(store.testResult(for: store.state.value![0]))
    #expect(result.isSuccess)
    #expect(store.lastActionSuccess == 1)
  }

  @Test func aFailingTestIsARowResultNotAListError() async {
    // A test is a question, not a mutation — `.actionFailed` is for things
    // that were supposed to change something and didn't. Blanking the list
    // because an indexer failed its test would be the wrong shape entirely.
    let (store, repository) = await makeStore([indexer(id: 1, name: "Alpha")])
    repository.testPasses = false

    await store.test(store.state.value![0])

    guard case .loaded = store.state else {
      Issue.record("a failed test changed the list state to \(store.state)")
      return
    }
    let result = try! #require(store.testResult(for: store.state.value![0]))
    #expect(!result.isSuccess)
    #expect(result.messages.first?.contains("403") == true, "got \(result.messages)")
    #expect(store.lastActionFailure == 1)
  }

  @Test func anUnreachableServiceIsReportedAsAFailedTestRatherThanSwallowed() async {
    let (store, repository) = await makeStore([indexer(id: 1, name: "Alpha")])
    repository.failActions = true

    await store.test(store.state.value![0])

    let result = try! #require(store.testResult(for: store.state.value![0]))
    #expect(!result.isSuccess)
    #expect(!result.messages.isEmpty, "a failed request said nothing")
  }

  @Test func aTestResultCanBeDismissed() async {
    let (store, _) = await makeStore([indexer(id: 1, name: "Alpha")])
    await store.test(store.state.value![0])
    #expect(store.testResult(for: store.state.value![0]) != nil)

    store.clearTestResult(for: store.state.value![0])

    #expect(store.testResult(for: store.state.value![0]) == nil)
  }

  // MARK: - Stats formatting

  @Test func theSuccessRateIsAFractionAndAbsentBeforeAnyQueries() async {
    let (store, _) = await makeStore(
      [indexer(id: 1, name: "Alpha"), indexer(id: 2, name: "Beta")],
      stats: [stats(id: 1, queries: 200, failed: 4), stats(id: 2, queries: 0, failed: 0)])

    let busy = try! #require(store.stats[1])
    #expect(abs((busy.successRate ?? 0) - 0.98) < 0.001)
    // A brand-new indexer is not "0% successful".
    #expect(store.stats[2]?.successRate == nil)
  }

  @Test func statsRowsFollowTheIndexerListsOrder() async {
    // The stats section and the indexer list should not disagree about order.
    let (store, _) = await makeStore(
      [indexer(id: 2, name: "Beta"), indexer(id: 1, name: "Alpha")],
      stats: [stats(id: 1, queries: 10, failed: 0), stats(id: 2, queries: 20, failed: 0)])

    #expect(store.statsRows.map(\.indexerID) == store.state.value?.map(\.id))
  }

  // MARK: - Delete and upsert

  @Test func deletingRemovesTheRow() async {
    let (store, repository) = await makeStore([
      indexer(id: 1, name: "Alpha"), indexer(id: 2, name: "Beta"),
    ])

    await store.delete(store.state.value![0])

    #expect(repository.deleted == [1])
    #expect(store.state.value?.map(\.id) == [2])
  }

  @Test func upsertAddsInSortedOrderAndReplacesInPlace() async {
    // The add/edit indexer form hands the saved indexer back here.
    let (store, _) = await makeStore([indexer(id: 1, name: "Alpha")])

    store.upsert(indexer(id: 2, name: "Beta"))
    #expect(store.state.value?.map(\.name) == ["Alpha", "Beta"])

    store.upsert(indexer(id: 2, name: "Beta", enabled: false))
    #expect(store.state.value?.count == 2, "an edit added a duplicate")
    #expect(store.state.value?.first { $0.id == 2 }?.isEnabled == false)
  }
}

struct EnableWrite: Equatable, Sendable {
  let id: Int
  let enabled: Bool
}

// MARK: - Stub

final class StubProwlarrRepository: ProwlarrRepositoryProtocol, @unchecked Sendable {
  let instance = ServiceInstance(
    kind: .prowlarr, name: "Prowlarr", baseURL: URL(string: "http://192.0.2.1:9696")!,
    credentials: .apiKey("k"))
  var arr: ArrClientCore { ArrClientCore(client: ServiceHTTPClient(instance: instance)) }

  private let lock = NSLock()
  private var stored: [ProwlarrIndexer]
  private let storedStats: [IndexerStats]

  var failActions = false
  var failStats = false
  var testPasses = true

  private(set) var listCalls = 0
  private(set) var historyCalls = 0
  private(set) var enableWrites: [EnableWrite] = []
  private(set) var deleted: [Int] = []
  private(set) var saved: [IndexerDraft] = []

  init(indexers: [ProwlarrIndexer], stats: [IndexerStats]) {
    self.stored = indexers
    self.storedStats = stats
  }

  func indexers() async throws -> [ProwlarrIndexer] {
    lock.withLock {
      listCalls += 1
      return stored
    }
  }

  func setEnabled(_ isEnabled: Bool, indexerID: Int) async throws {
    if failActions { throw AppError.serverUnreachable }
    lock.withLock {
      enableWrites.append(EnableWrite(id: indexerID, enabled: isEnabled))
      stored = stored.map { $0.id == indexerID ? $0.settingEnabled(isEnabled) : $0 }
    }
  }

  func test(indexerID: Int) async throws -> IndexerTestResult {
    if failActions { throw AppError.serverUnreachable }
    return testPasses
      ? IndexerTestResult(isSuccess: true, messages: [])
      : IndexerTestResult(
        isSuccess: false, messages: ["Unable to connect to indexer: 403 Forbidden"])
  }

  func delete(indexerID: Int) async throws {
    if failActions { throw AppError.serverUnreachable }
    lock.withLock {
      deleted.append(indexerID)
      stored.removeAll { $0.id == indexerID }
    }
  }

  /// Set by the add-indexer tests; empty for the list tests, which never ask.
  var schemaList: [IndexerSchema] = []

  func schemas() async throws -> [IndexerSchema] {
    if failActions { throw AppError.serverUnreachable }
    return schemaList
  }

  @discardableResult
  func save(_ draft: IndexerDraft) async throws -> ProwlarrIndexer {
    if failActions { throw AppError.serverUnreachable }
    lock.withLock { saved.append(draft) }
    return ProwlarrIndexer(
      id: draft.id ?? 99, name: draft.name, definitionName: draft.schema.definitionName,
      implementation: draft.schema.implementation, isEnabled: draft.isEnabled,
      downloadProtocol: draft.schema.downloadProtocol, privacy: draft.schema.privacy,
      priority: draft.priority, supportsRSS: true, supportsSearch: true,
      fields: draft.fields, tagIDs: [])
  }

  func test(_ draft: IndexerDraft) async throws -> IndexerTestResult {
    if failActions { throw AppError.serverUnreachable }
    return testPasses
      ? IndexerTestResult(isSuccess: true, messages: [])
      : IndexerTestResult(isSuccess: false, messages: ["Invalid credentials"])
  }

  func stats() async throws -> [IndexerStats] {
    if failStats { throw AppError.serverUnreachable }
    return storedStats
  }

  func history(indexerID: Int?) async throws -> [ProwlarrHistoryRecord] {
    lock.withLock {
      historyCalls += 1
      return [
        ProwlarrHistoryRecord(
          id: 1, indexerID: 1, date: Date(), isSuccessful: true, eventType: "indexerQuery",
          query: "example", source: "Radarr")
      ]
    }
  }
}
