import Foundation
import Observation
import TowerCore
import TowerData

/// Prowlarr's indexers, stats, and history — the at-a-glance health of
/// the stack's supply line.
@MainActor
@Observable
final class ProwlarrIndexersStore: RefreshableStore {
  var state: Loadable<[ProwlarrIndexer]> = .idle
  let loads = LoadTracker()

  var searchText: String = ""

  /// Per-indexer counters, keyed by indexer id. Not a `Loadable`: they are a
  /// decoration on the list and on the stats section, and a stats failure must
  /// not cost the indexers.
  private(set) var stats: [Int: IndexerStats] = [:]
  var history: Loadable<[ProwlarrHistoryRecord]> = .idle

  private(set) var inFlight: Set<Int> = []
  /// The last test result per indexer, so the row can report pass or fail in
  /// place rather than pushing a screen or throwing an alert.
  private(set) var testResults: [Int: IndexerTestResult] = [:]

  private(set) var lastActionSuccess = 0
  private(set) var lastActionFailure = 0

  let repository: any ProwlarrRepositoryProtocol

  init(repository: any ProwlarrRepositoryProtocol) {
    self.repository = repository
  }

  // MARK: - Loading

  func load() async {
    await load { [self] in try await repository.indexers() }
    await loadStats()
  }

  func refresh() async {
    guard state.value != nil else { return await load() }
    await mutate { [self] in try await repository.indexers() }
    await loadStats()
  }

  /// Deliberately non-throwing: a Prowlarr that answers `/indexer` but not
  /// `/indexerstats` should still show its indexers.
  private func loadStats() async {
    guard let fetched = try? await repository.stats() else { return }
    stats = Dictionary(fetched.map { ($0.indexerID, $0) }, uniquingKeysWith: { first, _ in first })
  }

  /// History is loaded when its section is first opened — it is a separate
  /// request and most visits are to check the indexers.
  func loadHistory(force: Bool = false) async {
    if !force, history.value != nil { return }
    if history.value == nil { history = .loading }
    do {
      history = .loaded(try await repository.history(indexerID: nil))
    } catch {
      history = .failed(AppError.wrapping(error))
    }
  }

  var filteredIndexers: [ProwlarrIndexer] {
    guard let indexers = state.value else { return [] }
    let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !query.isEmpty else { return indexers }
    return indexers.filter {
      $0.name.localizedCaseInsensitiveContains(query)
        || $0.definitionName?.localizedCaseInsensitiveContains(query) == true
    }
  }

  /// The indexers Prowlarr has taken out of rotation — the thing the screen
  /// exists to surface, counted so the header can lead with it.
  var failingCount: Int { (state.value ?? []).filter(\.isFailing).count }

  func stats(for indexer: ProwlarrIndexer) -> IndexerStats? { stats[indexer.id] }
  func testResult(for indexer: ProwlarrIndexer) -> IndexerTestResult? { testResults[indexer.id] }
  func isInFlight(_ indexer: ProwlarrIndexer) -> Bool { inFlight.contains(indexer.id) }

  /// Every indexer that has stats, in a stable order for the stats section.
  var statsRows: [IndexerStats] {
    (state.value ?? []).compactMap { stats[$0.id] }
  }

  // MARK: - Actions

  /// Flips an indexer and patches just that row.
  ///
  /// **Patched, not refetched.** The toggle shows in place without a
  /// full-screen reload, and the whole list is a two-request round trip
  /// (indexers plus stats). Nothing else on the screen changes when one
  /// indexer is enabled, so nothing else needs re-reading.
  func setEnabled(_ isEnabled: Bool, for indexer: ProwlarrIndexer) async {
    guard !inFlight.contains(indexer.id) else { return }
    inFlight.insert(indexer.id)
    defer { inFlight.remove(indexer.id) }

    do {
      try await repository.setEnabled(isEnabled, indexerID: indexer.id)
      lastActionSuccess += 1
      if let indexers = state.value {
        state = .loaded(
          indexers.map { $0.id == indexer.id ? $0.settingEnabled(isEnabled) : $0 })
      }
    } catch {
      lastActionFailure += 1
      state = .actionFailed(state.value ?? [], AppError.wrapping(error))
    }
  }

  /// Tests an indexer and records the outcome against its row.
  ///
  /// A test is a *question*, not a mutation — so a failure is recorded on the
  /// row rather than pushed into `.actionFailed`, which is for things that were
  /// supposed to change something and didn't.
  func test(_ indexer: ProwlarrIndexer) async {
    guard !inFlight.contains(indexer.id) else { return }
    inFlight.insert(indexer.id)
    defer { inFlight.remove(indexer.id) }

    do {
      let result = try await repository.test(indexerID: indexer.id)
      testResults[indexer.id] = result
      if result.isSuccess { lastActionSuccess += 1 } else { lastActionFailure += 1 }
    } catch {
      // The request itself failed — the service is unreachable, which is a
      // different fact from the indexer failing its test.
      testResults[indexer.id] = IndexerTestResult(
        isSuccess: false, messages: [AppError.wrapping(error).message])
      lastActionFailure += 1
    }
  }

  func clearTestResult(for indexer: ProwlarrIndexer) {
    testResults[indexer.id] = nil
  }

  func delete(_ indexer: ProwlarrIndexer) async {
    await mutate { [self] in
      try await repository.delete(indexerID: indexer.id)
      return (state.value ?? []).filter { $0.id != indexer.id }
    }
  }

  /// Adds or replaces an indexer after the add/edit form saves.
  func upsert(_ indexer: ProwlarrIndexer) {
    guard let indexers = state.value else { return }
    if indexers.contains(where: { $0.id == indexer.id }) {
      state = .loaded(indexers.map { $0.id == indexer.id ? indexer : $0 })
    } else {
      state = .loaded(
        (indexers + [indexer]).sorted {
          $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        })
    }
  }
}

extension ProwlarrIndexer {
  /// A copy with the enabled flag flipped — the one field the list changes
  /// locally, between the service accepting and the next refresh.
  func settingEnabled(_ isEnabled: Bool) -> ProwlarrIndexer {
    ProwlarrIndexer(
      id: id, name: name, definitionName: definitionName, implementation: implementation,
      isEnabled: isEnabled, downloadProtocol: downloadProtocol, privacy: privacy,
      priority: priority, supportsRSS: supportsRSS, supportsSearch: supportsSearch,
      fields: fields, tagIDs: tagIDs, failureMessage: failureMessage,
      disabledUntil: disabledUntil)
  }
}
