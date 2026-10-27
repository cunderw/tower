import Foundation
import Observation
import TowerCore
import TowerData

/// The shared *arr queue.
///
/// One store for every service — the queue endpoint, its shapes, and its two
/// removal decisions are identical across Radarr, Sonarr and Lidarr, which is
/// what `ArrClientCore` is for.
@MainActor
@Observable
final class ArrQueueStore: RefreshableStore {
  var state: Loadable<ArrQueuePage> = .idle
  let loads = LoadTracker()

  private let source: any ArrPickerSource

  init(source: any ArrPickerSource) {
    self.source = source
  }

  var items: [ArrQueueItem] {
    // Items needing attention first: a stuck import at the bottom of a long
    // queue is a stuck import nobody finds.
    (state.value?.items ?? []).sorted {
      ($0.needsAttention ? 0 : 1, $0.id) < ($1.needsAttention ? 0 : 1, $1.id)
    }
  }

  var isEmpty: Bool {
    guard let page = state.value else { return false }
    return page.items.isEmpty
  }

  func load() async {
    await load { [self] in try await source.queue() }
  }

  /// Poll and pull-to-refresh: never passes through `.loading`, so a transient
  /// failure doesn't blank a queue that is on screen.
  func refresh() async {
    guard state.value != nil else { return await load() }
    await mutate { [self] in try await source.queue() }
  }

  /// Removes an item and drops it from the list without a refetch.
  ///
  /// Both decisions are the caller's: `removeFromClient` deletes the download
  /// itself, and `blocklist` is what stops the *arr grabbing the same release
  /// again five minutes later — which is usually the entire point of removing a
  /// stuck one.
  func remove(_ item: ArrQueueItem, removeFromClient: Bool, blocklist: Bool) async {
    await mutate { [self] in
      try await source.removeQueueItem(
        id: item.id, removeFromClient: removeFromClient, blocklist: blocklist)
      guard let page = state.value else { return try await source.queue() }
      return ArrQueuePage(
        items: page.items.filter { $0.id != item.id },
        page: page.page,
        pageSize: page.pageSize,
        totalRecords: max(0, page.totalRecords - 1))
    }
  }
}
