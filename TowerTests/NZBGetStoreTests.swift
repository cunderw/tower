import Foundation
import Testing
import TowerCore
import TowerData

@testable import Tower

/// The NZBGet screen's queue, history, status, and actions.
@MainActor
@Suite
struct NZBGetStoreTests {
  private func group(
    id: Int, name: String, status: NZBGroupStatus = .queued, priority: NZBPriority = .normal,
    size: Int64 = 1_000, remaining: Int64 = 500, category: String? = nil
  ) -> NZBGroup {
    NZBGroup(
      id: id, name: name, status: status, category: category, sizeBytes: size,
      remainingBytes: remaining, downloadedBytes: size - remaining, priority: priority,
      health: 1, activeDownloads: 0)
  }

  private func makeStore(
    _ groups: [NZBGroup], history: [NZBHistoryItem] = [], failing: Bool = false
  ) async -> (NZBGetStore, StubNZBGetRepository) {
    let repository = StubNZBGetRepository(groups: groups, history: history, failing: failing)
    let store = NZBGetStore(repository: repository)
    await store.load()
    return (store, repository)
  }

  private func historyItem(id: Int, name: String, success: Bool = true) -> NZBHistoryItem {
    NZBHistoryItem(
      id: id, name: name, status: success ? "SUCCESS/ALL" : "FAILURE/PAR", isSuccess: success,
      category: nil, sizeBytes: 1_000, completedAt: Date(timeIntervalSince1970: 1_700_000_000),
      downloadSeconds: 60)
  }

  // MARK: - Loading

  @Test func theQueueAndStatusLoadTogether() async {
    let (store, _) = await makeStore([group(id: 1, name: "Alpha")])

    #expect(store.state.value?.count == 1)
    #expect(store.status != nil)
  }

  @Test func aStatusFailureDoesNotPutAnErrorWhereTheQueueShouldBe() async {
    // The status is context above the queue; the queue is the screen.
    let (store, repository) = await makeStore([group(id: 1, name: "Alpha")])
    repository.failStatusOnly = true
    await store.refresh()

    #expect(store.state.value?.count == 1, "the queue was lost to a status failure")
    #expect(store.status == nil)
  }

  @Test func historyIsNotLoadedUntilItsSectionIsOpened() async {
    // Most visits to this screen are to see what is downloading now, and
    // history is a second request against a possibly-remote service.
    let (store, repository) = await makeStore(
      [group(id: 1, name: "Alpha")], history: [historyItem(id: 30, name: "Old")])

    #expect(repository.historyCalls == 0)
    #expect(store.history.value == nil)

    await store.loadHistory()

    #expect(repository.historyCalls == 1)
    #expect(store.history.value?.count == 1)
  }

  @Test func historyIsNotRefetchedOnEveryVisit() async {
    let (store, repository) = await makeStore([], history: [historyItem(id: 30, name: "Old")])

    await store.loadHistory()
    await store.loadHistory()
    #expect(repository.historyCalls == 1)

    await store.loadHistory(force: true)
    #expect(repository.historyCalls == 2)
  }

  @Test func searchMatchesNameAndCategory() async {
    let (store, _) = await makeStore([
      group(id: 1, name: "Alpha"),
      group(id: 2, name: "Beta", category: "movies"),
    ])

    store.searchText = "movies"
    #expect(store.filteredQueue.map(\.id) == [2])
    store.searchText = "alph"
    #expect(store.filteredQueue.map(\.id) == [1])
  }

  // MARK: - Priority reorder

  @Test func changingPriorityPersistsAndReordersTheVisibleQueue() async {
    // NZBGet *orders the queue by priority*, so the point of the change is that
    // the row moves. Patching the row in place would show the new priority next
    // to the old position — the opposite of what was asked for.
    let (store, repository) = await makeStore([
      group(id: 1, name: "First", priority: .normal),
      group(id: 2, name: "Second", priority: .normal),
    ])
    #expect(store.filteredQueue.map(\.id) == [1, 2])

    await store.setPriority(.veryHigh, for: store.filteredQueue[1])

    #expect(repository.priorityWrites.count == 1)
    #expect(repository.priorityWrites[0].priority == .veryHigh)
    #expect(repository.priorityWrites[0].ids == [2])
    // The service reorders; the visible queue has to follow.
    #expect(store.filteredQueue.map(\.id) == [2, 1], "the queue did not reorder")
    #expect(store.filteredQueue[0].priority == .veryHigh, "the new priority didn't persist")
  }

  @Test func aFailedPriorityChangeKeepsTheQueueAndSaysWhy() async {
    let (store, repository) = await makeStore([group(id: 1, name: "Alpha")])
    repository.failWrites = true

    await store.setPriority(.high, for: store.filteredQueue[0])

    guard case .actionFailed(let groups, _) = store.state else {
      Issue.record("expected .actionFailed, got \(store.state)")
      return
    }
    #expect(groups.count == 1, "the queue was lost to a failed priority change")
    #expect(groups[0].priority == .normal)
  }

  // MARK: - Global speed limit

  @Test func theGlobalSpeedLimitRoundTripsSetAndClear() async {
    let (store, repository) = await makeStore([])

    await store.setSpeedLimit(bytesPerSecond: 5_242_880)
    #expect(repository.speedLimits == [5_242_880])
    #expect(store.status?.speedLimitBytesPerSecond == 5_242_880, "the new limit wasn't re-read")

    await store.setSpeedLimit(bytesPerSecond: nil)
    #expect(repository.speedLimits == [5_242_880, nil])
    #expect(store.status?.speedLimitBytesPerSecond == nil, "the cleared limit wasn't re-read")
  }

  @Test func aBlankLimitFieldMeansUnlimitedRatherThanZero() {
    #expect(NZBSpeedLimitSheet.bytesPerSecond("") == nil)
    #expect(NZBSpeedLimitSheet.bytesPerSecond("0") == nil)
    #expect(NZBSpeedLimitSheet.bytesPerSecond("nonsense") == nil)
    // The field is KB/s, which is NZBGet's own unit.
    #expect(NZBSpeedLimitSheet.bytesPerSecond("5120") == 5_242_880)
  }

  // MARK: - Queue actions

  @Test func pausingAGroupRereadsTheQueueAndTheStatus() async {
    // There is no useful local patch: every NZBGet
    // mutation changes the server's aggregate figures too.
    let (store, repository) = await makeStore([
      group(id: 1, name: "Alpha", status: .downloading)
    ])
    let statusCallsBefore = repository.statusCalls

    await store.setPaused(true, for: store.filteredQueue[0])

    #expect(repository.pausedIDs == [1])
    #expect(store.filteredQueue[0].status == .paused)
    #expect(repository.statusCalls > statusCallsBefore, "the status went stale after a pause")
  }

  @Test func deletingRemovesTheGroup() async {
    let (store, repository) = await makeStore([
      group(id: 1, name: "Alpha"), group(id: 2, name: "Beta"),
    ])

    await store.delete(store.filteredQueue[0])

    #expect(repository.deletedIDs == [1])
    #expect(store.filteredQueue.map(\.id) == [2])
  }

  @Test func theGlobalPauseIsTheServersOwnSwitch() async {
    let (store, repository) = await makeStore([group(id: 1, name: "Alpha")])
    #expect(!store.isDownloadPaused)

    await store.setDownloadPaused(true)

    #expect(repository.pauseAllCalls == 1)
    #expect(store.isDownloadPaused, "the header didn't reflect the paused server")

    await store.setDownloadPaused(false)
    #expect(repository.resumeAllCalls == 1)
    #expect(!store.isDownloadPaused)
  }

  // MARK: - History actions

  @Test func retryingRereadsTheQueueBecauseThatIsWhereTheItemReappears() async {
    // A retry that only refreshed the history would look like nothing happened.
    let (store, repository) = await makeStore(
      [], history: [historyItem(id: 30, name: "Old.Release", success: false)])
    await store.loadHistory()
    #expect(store.state.value?.isEmpty == true)

    await store.retry(store.history.value![0])

    #expect(repository.retriedIDs == [30])
    #expect(store.state.value?.count == 1, "the retried item never reached the queue")
    #expect(store.state.value?[0].name == "Old.Release")
    #expect(store.history.value?.isEmpty == true, "the history wasn't re-read")
  }

  @Test func deletingAHistoryEntryRemovesTheRecord() async {
    let (store, repository) = await makeStore(
      [], history: [historyItem(id: 30, name: "Old"), historyItem(id: 31, name: "Older")])
    await store.loadHistory()

    await store.deleteHistory(store.history.value![0])

    #expect(repository.deletedHistoryIDs == [30])
    #expect(store.history.value?.map(\.id) == [31])
  }

  @Test func aFailedHistoryActionKeepsTheListOnScreen() async {
    let (store, repository) = await makeStore([], history: [historyItem(id: 30, name: "Old")])
    await store.loadHistory()
    repository.failWrites = true

    await store.deleteHistory(store.history.value![0])

    guard case .actionFailed(let items, _) = store.history else {
      Issue.record("expected .actionFailed, got \(store.history)")
      return
    }
    #expect(items.count == 1, "the history was blanked by a failed delete")
  }
}

// MARK: - Stub

/// In-memory NZBGet. Ordering follows the service's rule — priority first — so
/// the reorder assertion is testing the store, not the stub's convenience.
final class StubNZBGetRepository: NZBGetRepositoryProtocol, @unchecked Sendable {
  let instance = ServiceInstance(
    kind: .nzbget, name: "NZBGet", baseURL: URL(string: "http://192.0.2.1:6789")!,
    credentials: .usernamePassword(username: "u", password: "p"))

  private let lock = NSLock()
  private var groups: [NZBGroup]
  private var historyItems: [NZBHistoryItem]
  private let failing: Bool
  private var speedLimit: Int64?
  private var paused = false

  var failWrites = false
  var failStatusOnly = false

  private(set) var historyCalls = 0
  private(set) var statusCalls = 0
  private(set) var pausedIDs: [Int] = []
  private(set) var deletedIDs: [Int] = []
  private(set) var retriedIDs: [Int] = []
  private(set) var deletedHistoryIDs: [Int] = []
  private(set) var priorityWrites: [(ids: [Int], priority: NZBPriority)] = []
  private(set) var speedLimits: [Int64?] = []
  private(set) var pauseAllCalls = 0
  private(set) var resumeAllCalls = 0

  init(groups: [NZBGroup], history: [NZBHistoryItem], failing: Bool) {
    self.groups = groups
    self.historyItems = history
    self.failing = failing
  }

  func queue() async throws -> [NZBGroup] {
    if failing { throw AppError.serverUnreachable }
    // NZBGet orders by priority, highest first, stable within a priority.
    return lock.withLock {
      groups.enumerated()
        .sorted {
          $0.element.priority.rawValue == $1.element.priority.rawValue
            ? $0.offset < $1.offset
            : $0.element.priority.rawValue > $1.element.priority.rawValue
        }
        .map(\.element)
    }
  }

  func history() async throws -> [NZBHistoryItem] {
    if failing { throw AppError.serverUnreachable }
    return lock.withLock {
      historyCalls += 1
      return historyItems
    }
  }

  func status() async throws -> NZBServerStatus {
    if failing || failStatusOnly { throw AppError.serverUnreachable }
    return lock.withLock {
      statusCalls += 1
      return NZBServerStatus(
        downloadRateBytesPerSecond: 1_000, remainingBytes: 500, downloadedBytes: 500,
        freeDiskSpaceBytes: 10_000, isDownloadPaused: paused,
        speedLimitBytesPerSecond: speedLimit, uptime: 60, postJobCount: 0, version: "21.1")
    }
  }

  func pause(ids: [Int]) async throws {
    if failing || failWrites { throw AppError.serverUnreachable }
    lock.withLock {
      pausedIDs.append(contentsOf: ids)
      groups = groups.map { ids.contains($0.id) ? $0.settingStatus(.paused) : $0 }
    }
  }

  func resume(ids: [Int]) async throws {
    if failing || failWrites { throw AppError.serverUnreachable }
    lock.withLock { groups = groups.map { ids.contains($0.id) ? $0.settingStatus(.queued) : $0 } }
  }

  func setPriority(_ priority: NZBPriority, ids: [Int]) async throws {
    if failing || failWrites { throw AppError.serverUnreachable }
    lock.withLock {
      priorityWrites.append((ids, priority))
      groups = groups.map { ids.contains($0.id) ? $0.settingPriority(priority) : $0 }
    }
  }

  func delete(ids: [Int]) async throws {
    if failing || failWrites { throw AppError.serverUnreachable }
    lock.withLock {
      deletedIDs.append(contentsOf: ids)
      groups.removeAll { ids.contains($0.id) }
    }
  }

  func pauseAll() async throws {
    if failing || failWrites { throw AppError.serverUnreachable }
    lock.withLock {
      pauseAllCalls += 1
      paused = true
    }
  }

  func resumeAll() async throws {
    if failing || failWrites { throw AppError.serverUnreachable }
    lock.withLock {
      resumeAllCalls += 1
      paused = false
    }
  }

  func setSpeedLimit(bytesPerSecond: Int64?) async throws {
    if failing || failWrites { throw AppError.serverUnreachable }
    lock.withLock {
      speedLimits.append(bytesPerSecond)
      speedLimit = bytesPerSecond
    }
  }

  func retryHistory(ids: [Int]) async throws {
    if failing || failWrites { throw AppError.serverUnreachable }
    lock.withLock {
      retriedIDs.append(contentsOf: ids)
      // NZBGet puts the item back in the queue and drops the history entry.
      for id in ids {
        guard let item = historyItems.first(where: { $0.id == id }) else { continue }
        groups.append(
          NZBGroup(
            id: item.id, name: item.name, status: .queued, category: item.category,
            sizeBytes: item.sizeBytes, remainingBytes: item.sizeBytes, downloadedBytes: 0,
            priority: .normal, health: 1, activeDownloads: 0))
      }
      historyItems.removeAll { ids.contains($0.id) }
    }
  }

  func deleteHistory(ids: [Int]) async throws {
    if failing || failWrites { throw AppError.serverUnreachable }
    lock.withLock {
      deletedHistoryIDs.append(contentsOf: ids)
      historyItems.removeAll { ids.contains($0.id) }
    }
  }
}

extension NZBGroup {
  fileprivate func settingStatus(_ status: NZBGroupStatus) -> NZBGroup {
    NZBGroup(
      id: id, name: name, status: status, category: category, sizeBytes: sizeBytes,
      remainingBytes: remainingBytes, downloadedBytes: downloadedBytes, priority: priority,
      health: health, activeDownloads: activeDownloads)
  }

  fileprivate func settingPriority(_ priority: NZBPriority) -> NZBGroup {
    NZBGroup(
      id: id, name: name, status: status, category: category, sizeBytes: sizeBytes,
      remainingBytes: remainingBytes, downloadedBytes: downloadedBytes, priority: priority,
      health: health, activeDownloads: activeDownloads)
  }
}
