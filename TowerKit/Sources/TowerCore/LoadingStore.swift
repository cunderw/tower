import Foundation

/// Tracks a store's in-flight load so it can be cancelled, and so a superseded
/// load's late answer can be recognised and dropped.
///
/// A separate reference type because a protocol extension cannot add stored
/// state, and the alternatives were worse: making `LoadingStore` a base class
/// fights `@Observable final class`, and keying a side table by
/// `ObjectIdentifier` would leak. One `let loads = LoadTracker()` per store is
/// the whole cost.
///
/// **Why generations rather than comparing values.** A late response is not
/// distinguishable from a correct one by looking at what it contains — "stale"
/// and "genuinely unchanged" produce identical data. Only *when it was asked
/// for* separates them, which is what the counter records. Same reasoning as
/// `DockerStore.mutationSequence`, which guards a different axis (see
/// `LoadingStore.load(_:)`).
@MainActor
public final class LoadTracker {
  /// Bumped for every request. A response may only be written if its generation
  /// is still the current one.
  private var generation = 0
  private var task: Task<Void, Never>?

  /// When this store last **successfully** landed data, or `nil` if it never
  /// has.
  ///
  /// Here rather than on each store because this type is already the per-store
  /// home for load bookkeeping — the alternative was the same stored property
  /// repeated in a dozen stores, kept in sync by hand.
  ///
  /// **Success only.** A failed load must not count as fresh: a service that
  /// was unreachable would then sit showing its error for the whole staleness
  /// window after it came back, which is precisely the case refresh-on-appear
  /// exists for.
  public private(set) var lastLoadedAt: Date?

  public init() {}

  /// Stamps a successful load. Called by `LoadingStore`, not by stores.
  func markLoaded(at date: Date = Date()) {
    lastLoadedAt = date
  }

  /// Whether data older than `interval` is on screen — "should this refresh
  /// underneath on appear?". `true` when nothing has ever loaded, so a first
  /// appearance still loads.
  public func isStale(olderThan interval: TimeInterval, now: Date = Date()) -> Bool {
    guard let lastLoadedAt else { return true }
    return now.timeIntervalSince(lastLoadedAt) >= interval
  }

  /// Whether a load is running right now — what a view reads to decide whether
  /// to offer Cancel.
  public var isLoading: Bool { task != nil }

  /// Claims the next generation and cancels whatever was running.
  ///
  /// Cancelling the previous task matters even though the generation check would
  /// already discard its result: without it a superseded request keeps its socket
  /// and its 60-second timeout, and on a LAN that has gone away those pile up
  /// behind every retry.
  func begin() -> Int {
    task?.cancel()
    task = nil
    generation += 1
    return generation
  }

  /// Records the task backing generation `generation`, so `cancel()` can reach
  /// it. Ignored if a newer generation has already started — otherwise a slow
  /// hand-off could install an old task over a newer one and cancel the wrong
  /// request.
  func track(_ task: Task<Void, Never>, generation: Int) {
    guard generation == self.generation else {
      task.cancel()
      return
    }
    self.task = task
  }

  /// Whether `generation` is still the one whose answer the store wants.
  func isCurrent(_ generation: Int) -> Bool { generation == self.generation }

  /// The current generation without claiming a new one — for `mutate`, which
  /// joins the sequence rather than starting it: a refresh is not a load, must
  /// not cancel one, and must not make one look superseded.
  var currentGeneration: Int { generation }

  /// Clears the task handle once its work is done, so `isLoading` stops claiming
  /// a load is running. Only clears when the finishing task is still the current
  /// one.
  func finish(_ generation: Int) {
    guard generation == self.generation else { return }
    task = nil
  }

  /// Cancels the in-flight load. The store's own `catch` turns the resulting
  /// `CancellationError` into `AppError.cancelled`, which every screen already
  /// renders as a retryable failure.
  public func cancel() {
    task?.cancel()
  }
}

@MainActor
public protocol LoadingStore: AnyObject {
  associatedtype Value: Sendable
  var state: Loadable<Value> { get set }
  /// One line per store: `let loads = LoadTracker()`. See that type for why this
  /// can't live in the protocol extension.
  var loads: LoadTracker { get }
}

extension LoadingStore {
  /// Runs a fetch, driving `state` through `.loading` to `.loaded` or `.failed`.
  /// Existing data is discarded — use this for initial loads and retries.
  ///
  /// **Cancels any load already running, and drops a superseded load's answer.**
  /// Both matter for the same scenario, which is the one Tower is most likely to
  /// meet: a LAN address that has become unreachable, where a request neither
  /// succeeds nor fails fast. Adding a retry button without this would make
  /// things *worse* — a stale request's 60-second timeout can land after a
  /// successful retry and silently revert the screen to an error.
  ///
  /// This guards load-versus-load. `DockerStore`/`VMStore`'s own
  /// `mutationSequence` guards a different axis — a poll issued before a mutation
  /// completing after it — and both are still needed.
  // `@escaping` but **not** `@Sendable`: the closure is captured by a
  // `Task { @MainActor in }`, and everything here — the store, its repository,
  // the closure — is already main-actor-isolated, so nothing crosses an
  // isolation boundary. Requiring `@Sendable` would force every call site to
  // prove a repository is `Sendable` for no gain.
  public func load(_ operation: @escaping () async throws -> Value) async {
    let generation = loads.begin()
    state = .loading

    // Wrapped in a `Task` the tracker can hold, rather than run inline: a caller
    // is usually a `.task {}` in a view, and cancelling that only reaches this
    // work if there is a handle to cancel.
    let task = Task { @MainActor in
      do {
        let value = try await operation()
        guard loads.isCurrent(generation) else { return }
        state = .loaded(value)
        loads.markLoaded()
      } catch is CancellationError {
        guard loads.isCurrent(generation) else { return }
        state = .failed(.cancelled)
      } catch {
        guard loads.isCurrent(generation) else { return }
        // A cancelled `URLSession` request surfaces as `URLError.cancelled`
        // rather than `CancellationError`, so the mapping layer's own translation
        // is what catches that shape — see `AppError.wrapping`.
        state = .failed(AppError.wrapping(error))
      }
      loads.finish(generation)
    }
    loads.track(task, generation: generation)
    await task.value
  }

  /// Runs a mutation whose closure returns the resulting value, and never passes
  /// through `.loading` — blanking the screen mid-action is exactly what this
  /// method exists to avoid.
  ///
  /// On failure, previously loaded data is preserved via `.actionFailed` so the
  /// UI keeps showing it and surfaces the error transiently. The value is read
  /// through `state.value`, which resolves for both `.loaded` and
  /// `.actionFailed`, so repeated failures do not lose the original data.
  ///
  /// That read happens *after* `operation` returns/throws, not before —
  /// `state.value` is captured fresh at the moment it's needed, never
  /// pre-captured into a local before the `await`. A caller can take arbitrarily
  /// long (a `docker stop`'s SIGTERM grace, a slow network request); anything
  /// else that legitimately wrote `state` during that window must still be there
  /// when this fails, not be clobbered by a snapshot this call saw before it even
  /// started.
  ///
  /// **Takes a generation and drops its write if superseded**, like `load`, so a
  /// slow refresh can't overwrite a newer load's result. It deliberately does
  /// *not* cancel a running load or install a cancellable task: a mutation in
  /// flight against a real server must not be abandoned halfway, and a refresh is
  /// not something a user asked to be able to cancel.
  public func mutate(_ operation: () async throws -> Value) async {
    let generation = loads.currentGeneration
    do {
      let value = try await operation()
      guard loads.isCurrent(generation) else { return }
      state = .loaded(value)
      // A refresh that lands is as fresh as a load that lands — otherwise
      // pull-to-refresh would leave the store looking stale and the next
      // appearance would refetch immediately.
      loads.markLoaded()
    } catch {
      guard loads.isCurrent(generation) else { return }
      let appError = AppError.wrapping(error)
      state = state.value.map { .actionFailed($0, appError) } ?? .failed(appError)
    }
  }

  /// Cancels an in-flight load, leaving the screen on `.failed(.cancelled)` with
  /// its retry affordance. A no-op when nothing is running.
  public func cancelLoad() {
    loads.cancel()
  }

  /// Whether a load is in flight — what a view reads to decide whether to offer
  /// Cancel.
  public var isLoadInFlight: Bool { loads.isLoading }
}

/// A store whose screen can both load from cold and refresh underneath.
///
/// Exists so the "what should happen when this screen appears" rule lives in
/// one place instead of being retyped in every `.task {}`. A service store
/// outlives its screen, so a screen that loads once and never again (`guard
/// store.state.value == nil else { return }`) can show data that is
/// arbitrarily old, with nothing to refresh it.
@MainActor
public protocol RefreshableStore: LoadingStore {
  /// A cold load: passes through `.loading` and replaces what is there.
  func load() async
  /// A refresh underneath: keeps existing data on screen, never `.loading`.
  func refresh() async
}

extension RefreshableStore {
  /// What a screen should do when it appears: load if it never has, refresh
  /// underneath if what it holds is stale, and otherwise nothing at all.
  ///
  /// The stale path deliberately goes through `refresh()`, so a screen that
  /// already has data never blanks — the user sees the old list and it updates
  /// in place. A failed store has no `lastLoadedAt`, so it re-loads rather than
  /// sitting on an error that may no longer be true.
  ///
  /// - Parameter interval: how old is too old. 60 seconds: long enough that
  ///   flicking between two services doesn't refetch either, short enough that
  ///   a queue you come back to is not meaningfully wrong.
  public func appeared(staleAfter interval: TimeInterval = 60) async {
    guard state.value != nil else {
      await load()
      return
    }
    guard loads.isStale(olderThan: interval) else { return }
    await refresh()
  }
}
