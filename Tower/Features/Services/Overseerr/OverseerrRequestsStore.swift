import Foundation
import Observation
import TowerCore
import TowerData

/// Overseerr's requests list — the single most-used flow in the stack.
///
/// **Paginated, unlike the other service lists.** The *arr libraries and
/// the NZBGet queue fetch everything and filter locally, because a media
/// library is a few hundred rows. A busy Overseerr accumulates thousands of
/// requests, so this one pages, and the filter is applied *by the service*
/// rather than locally — filtering client-side would page through approved
/// requests looking for pending ones.
@MainActor
@Observable
final class OverseerrRequestsStore: RefreshableStore {
  var state: Loadable<[OverseerrRequest]> = .idle
  let loads = LoadTracker()

  /// Changing this reloads from page 1 — a filter is a different query, not a
  /// view onto what is already here.
  var filter: RequestFilter = .pending {
    didSet {
      guard filter != oldValue else { return }
      Task { await load() }
    }
  }

  private(set) var page = 1
  private(set) var hasMore = false
  private(set) var isLoadingMore = false
  /// Requests with an action in flight, so a row can't be approved twice by an
  /// impatient double-tap — the same guard `DockerStore.inFlight` provides.
  private(set) var inFlight: Set<Int> = []

  /// Bumped once per action that resolves successfully; the view drives
  /// `.sensoryFeedback(.success, trigger:)` off it. Never bumped by a load or
  /// a poll, so a background refresh can't buzz the user.
  private(set) var lastActionSuccess = 0
  private(set) var lastActionFailure = 0

  let repository: any OverseerrRepositoryProtocol

  init(repository: any OverseerrRepositoryProtocol) {
    self.repository = repository
  }

  // MARK: - Loading

  func load() async {
    page = 1
    await load { [self] in
      let result = try await repository.requests(filter: filter, page: 1)
      hasMore = result.hasMore
      return result.requests
    }
  }

  func refresh() async {
    guard state.value != nil else { return await load() }
    await mutate { [self] in
      // Refreshing re-reads only what is on screen, not every page fetched so
      // far: re-fetching five pages on every pull would make the gesture cost
      // five round trips.
      let result = try await repository.requests(filter: filter, page: 1)
      hasMore = result.hasMore
      page = 1
      return result.requests
    }
  }

  /// Appends the next page. Called when the last row appears.
  func loadMore() async {
    guard hasMore, !isLoadingMore, let existing = state.value else { return }
    isLoadingMore = true
    defer { isLoadingMore = false }
    do {
      let result = try await repository.requests(filter: filter, page: page + 1)
      page += 1
      hasMore = result.hasMore
      // Deduplicated: a request approved between two page fetches shifts the
      // window, and the same row can arrive twice. `ForEach` over duplicate
      // ids is a runtime warning and a visibly repeated row.
      var seen = Set(existing.map(\.id))
      let fresh = result.requests.filter { seen.insert($0.id).inserted }
      state = .loaded(existing + fresh)
    } catch {
      // Keeps the pages already on screen, and leaves `page` and `hasMore` as
      // they were, so the next scroll to the end retries the same page.
      state = .actionFailed(existing, AppError.wrapping(error))
    }
  }

  var isEmpty: Bool { (state.value ?? []).isEmpty }

  func isInFlight(_ request: OverseerrRequest) -> Bool { inFlight.contains(request.id) }

  // MARK: - Actions

  func approve(_ request: OverseerrRequest) async {
    await act(on: request) { [self] in try await repository.approve(requestID: request.id) }
  }

  func decline(_ request: OverseerrRequest) async {
    await act(on: request) { [self] in try await repository.decline(requestID: request.id) }
  }

  /// Runs an approve or decline, then reconciles the row.
  ///
  /// **The row is re-read, not patched.** Approving does more than change a
  /// number: Overseerr hands the request to the *arr, which sets the media
  /// status too, and on the pending filter the row should *leave the list*
  /// entirely. Guessing all of that locally would be a worse lie than a short
  /// wait.
  private func act(
    on request: OverseerrRequest, _ action: @escaping () async throws -> Void
  ) async {
    guard !inFlight.contains(request.id) else { return }
    inFlight.insert(request.id)
    defer { inFlight.remove(request.id) }

    do {
      try await action()
      lastActionSuccess += 1
      await reconcile(request)
    } catch {
      lastActionFailure += 1
      state = .actionFailed(state.value ?? [], AppError.wrapping(error))
    }
  }

  /// Re-reads the one request and either replaces it or drops it, depending on
  /// whether it still belongs under the current filter.
  private func reconcile(_ request: OverseerrRequest) async {
    guard let existing = state.value else { return }
    guard let updated = try? await repository.request(id: request.id) else {
      // The service accepted the action but won't tell us the new state.
      // Dropping the row on the pending filter is still right — it is no
      // longer pending, whatever else is true.
      state = .loaded(filter == .pending ? existing.filter { $0.id != request.id } : existing)
      return
    }
    if filter == .pending && !updated.status.isActionable {
      state = .loaded(existing.filter { $0.id != request.id })
    } else {
      state = .loaded(existing.map { $0.id == updated.id ? updated : $0 })
    }
  }
}
