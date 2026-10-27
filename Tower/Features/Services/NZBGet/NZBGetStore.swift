import Foundation
import Observation
import TowerCore
import TowerData

/// NZBGet: the queue, the history, and the server status.
///
/// **One store for all three.**
/// They are three sections of one screen here rather than a list that pushes a
/// detail, and they are genuinely coupled: pausing a group changes the server's
/// rate, retrying a history item puts it back in the queue. Keeping them
/// together is what lets an action refresh exactly what it affected.
@MainActor
@Observable
final class NZBGetStore: RefreshableStore {
  /// The queue is the screen's primary content, so it is the one that drives
  /// `LoadingStore`'s spinner and error states.
  var state: Loadable<[NZBGroup]> = .idle
  let loads = LoadTracker()

  var history: Loadable<[NZBHistoryItem]> = .idle
  /// The status header. Not a `Loadable`: it is context above the queue, and a
  /// status failure must not put an error where the queue should be.
  private(set) var status: NZBServerStatus?

  var searchText: String = ""

  let repository: any NZBGetRepositoryProtocol

  init(repository: any NZBGetRepositoryProtocol) {
    self.repository = repository
  }

  // MARK: - Loading

  func load() async {
    await load { [self] in try await repository.queue() }
    await loadStatus()
  }

  func refresh() async {
    guard state.value != nil else { return await load() }
    await mutate { [self] in try await repository.queue() }
    await loadStatus()
  }

  private func loadStatus() async {
    status = try? await repository.status()
  }

  /// History is loaded when its section is first opened, not with the queue —
  /// it is a second request against a service that may be remote, and most
  /// visits to this screen are to look at what is downloading now.
  func loadHistory(force: Bool = false) async {
    if !force, history.value != nil { return }
    if history.value == nil { history = .loading }
    do {
      history = .loaded(try await repository.history())
    } catch {
      history = .failed(AppError.wrapping(error))
    }
  }

  var filteredQueue: [NZBGroup] {
    guard let queue = state.value else { return [] }
    let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !query.isEmpty else { return queue }
    return queue.filter {
      $0.name.localizedCaseInsensitiveContains(query)
        || $0.category?.localizedCaseInsensitiveContains(query) == true
    }
  }

  var isDownloadPaused: Bool { status?.isDownloadPaused ?? false }

  // MARK: - Queue actions

  func setPaused(_ isPaused: Bool, for group: NZBGroup) async {
    await runQueueAction { [self] in
      if isPaused {
        try await repository.pause(ids: [group.id])
      } else {
        try await repository.resume(ids: [group.id])
      }
    }
  }

  /// Changes a group's priority and re-reads the queue.
  ///
  /// **Re-read, not patched.** NZBGet *orders the queue by priority* — the
  /// point of the change is that the row moves — so patching the row in place
  /// would show the new priority next to the old position, which is the
  /// opposite of what the user asked for.
  func setPriority(_ priority: NZBPriority, for group: NZBGroup) async {
    await runQueueAction { [self] in
      try await repository.setPriority(priority, ids: [group.id])
    }
  }

  func delete(_ group: NZBGroup) async {
    await runQueueAction { [self] in try await repository.delete(ids: [group.id]) }
  }

  // MARK: - Global actions

  func setDownloadPaused(_ isPaused: Bool) async {
    await runQueueAction { [self] in
      if isPaused {
        try await repository.pauseAll()
      } else {
        try await repository.resumeAll()
      }
    }
  }

  /// The global rate cap, in bytes per second. `nil` clears it.
  func setSpeedLimit(bytesPerSecond: Int64?) async {
    await runQueueAction { [self] in
      try await repository.setSpeedLimit(bytesPerSecond: bytesPerSecond)
    }
  }

  // MARK: - History actions

  /// Re-enqueues a finished item. The queue is re-read as well as the history,
  /// because that is where the item reappears — a retry that only refreshed
  /// the history would look like nothing happened.
  func retry(_ item: NZBHistoryItem) async {
    await runHistoryAction { [self] in try await repository.retryHistory(ids: [item.id]) }
    await mutate { [self] in try await repository.queue() }
  }

  func deleteHistory(_ item: NZBHistoryItem) async {
    await runHistoryAction { [self] in try await repository.deleteHistory(ids: [item.id]) }
  }

  // MARK: - Plumbing

  /// Runs an action, then re-reads the queue and the status.
  ///
  /// Every NZBGet mutation changes the server's aggregate figures — pausing a
  /// group drops the rate, a priority change reorders the queue — so there is
  /// no useful local patch here. On failure the
  /// queue is left exactly as it was and the error surfaces through
  /// `.actionFailed`.
  private func runQueueAction(_ action: @escaping () async throws -> Void) async {
    await mutate { [self] in
      try await action()
      return try await repository.queue()
    }
    await loadStatus()
  }

  private func runHistoryAction(_ action: @escaping () async throws -> Void) async {
    do {
      try await action()
      history = .loaded(try await repository.history())
    } catch {
      // Keeps whatever history is on screen, and says why.
      history = .actionFailed(history.value ?? [], AppError.wrapping(error))
    }
  }
}
