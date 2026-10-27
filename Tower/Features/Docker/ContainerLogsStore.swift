import Foundation
import Observation
import TowerCore
import TowerData

/// Backs `ContainerLogsView` — fetches one container's log output via
/// `DockerRepositoryProtocol.logs(id:tail:since:)`. Not folded into
/// `DockerStore`: log lines aren't part of `[Container]`, and every
/// container's log view needs its own independent fetch depth and loading
/// state, not one shared across the whole tab.
///
/// **Why `loadMore()` grows `tail` instead of paging with `since`/`cursor`:**
/// Unraid's `since` is inclusive-*forward* — re-requesting with `since` set to
/// the oldest loaded line's own timestamp returns that same line again, not
/// anything earlier. That matches the schema's own doc comment on `cursor`
/// ("continue streaming logs"): it's built for resuming a live tail going
/// forward, not for paging backward into history. The only lever this API
/// offers for reaching further back is a larger `tail`, so `loadMore()`
/// re-requests the same query with `since: nil` and a bigger `tail` each time.
/// See `ContainerLogs`'s doc comment in `TowerCore` for the same reasoning at
/// the domain-model layer.
@MainActor
@Observable
final class ContainerLogsStore: LoadingStore {
  /// Lines on appear, and how much `loadMore()` grows the request by each time.
  static let pageSize = 200

  var state: Loadable<[ContainerLogLine]> = .idle

  /// The one line `LoadingStore` needs per store — see `LoadTracker` for why it
  /// can't live in the protocol extension.
  let loads = LoadTracker()
  /// Whether a fetch at the current `depth` returned as many lines as were
  /// asked for — Unraid treats `tail` as a maximum, not an exact count, so
  /// a response strictly shorter than `depth` is the one reliable signal
  /// that the container's entire log history is already on screen. Starts
  /// `true`: nothing has been fetched yet, so exhaustion can't be known.
  ///
  /// Plain `var`, not `private(set)` — matches `DockerStore.inFlight`'s
  /// identical choice (convention-enforced, not compiler-enforced) rather
  /// than `lastActionSuccess`'s `private(set)`: unlike `ContainerRow`, which
  /// takes `isInFlight` as a plain `Bool` parameter so its own previews
  /// never touch a store at all, `ContainerLogsView` reads `store.hasMore`
  /// directly — its `#Preview`s need to seed this field on a fixture store
  /// without a real fetch ever running.
  var hasMore = true
  /// Guards `loadMore()` against a second tap while the first is still in
  /// flight — the same reentrancy guard shape as `DockerStore.inFlight`,
  /// just keyed to this single store instead of a per-row set. Deliberately
  /// not folded into `state.isLoading`: `loadMore()` goes through `mutate`,
  /// which never touches `.loading` (that would blank out the lines already
  /// on screen), so this is the only signal a "Load more" button has to
  /// disable itself/show a spinner while its own fetch is outstanding.
  var isLoadingMore = false

  private let repository: any DockerRepositoryProtocol
  private let containerID: Container.ID
  /// How many lines the most recent (or in-flight) fetch asked for via
  /// `tail`. Reset to `Self.pageSize` by `load()`; grown by `Self.pageSize`
  /// on each `loadMore()`.
  private var depth = ContainerLogsStore.pageSize

  init(repository: any DockerRepositoryProtocol, containerID: Container.ID) {
    self.repository = repository
    self.containerID = containerID
  }

  /// Initial load: `.loading` is correct here, matching `DockerStore.load()`
  /// — there is nothing on screen yet to preserve. Also the reset point for
  /// `depth`, so re-appearing at this screen (or a future pull-to-refresh)
  /// starts back at the last `Self.pageSize` lines rather than wherever a
  /// previous visit's `loadMore()` calls had grown it to.
  func load() async {
    depth = Self.pageSize
    let requestedDepth = depth
    await load { [self] in
      let logs = try await repository.logs(id: containerID, tail: requestedDepth, since: nil)
      hasMore = logs.lines.count == requestedDepth
      return logs.lines
    }
  }

  /// Fetches a larger window from the end of the log and replaces `state`
  /// with it wholesale — the new fetch is a superset of what's already
  /// shown (same server, same container, just a bigger `tail`), so
  /// there's nothing to merge. Goes through `mutate`, not `load`, so a
  /// failure here surfaces via `.actionFailed` and keeps the lines already
  /// on screen rather than blanking them — the same reasoning as
  /// `DockerStore.refresh()`.
  func loadMore() async {
    guard !isLoadingMore, hasMore else { return }
    isLoadingMore = true
    let requestedDepth = depth + Self.pageSize
    await mutate {
      let logs = try await repository.logs(id: containerID, tail: requestedDepth, since: nil)
      depth = requestedDepth
      hasMore = logs.lines.count == requestedDepth
      return logs.lines
    }
    isLoadingMore = false
  }
}
