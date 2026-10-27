import Testing
@testable import TowerCore

@MainActor
private final class CounterStore: LoadingStore {
  let loads = LoadTracker()
  var state: Loadable<Int> = .idle
}

@MainActor
struct LoadingStoreTests {
  @Test func loadMovesIdleToLoaded() async {
    let store = CounterStore()
    await store.load { 5 }
    #expect(store.state == .loaded(5))
  }

  @Test func loadFailureMovesToFailed() async {
    let store = CounterStore()
    await store.load { throw AppError.unauthorized }
    #expect(store.state == .failed(.unauthorized))
  }

  @Test func mutateFailurePreservesLoadedData() async {
    let store = CounterStore()
    await store.load { 5 }
    await store.mutate { throw AppError.serverUnreachable }
    #expect(store.state == .actionFailed(5, .serverUnreachable))
  }

  @Test func mutateFailureWithoutDataMovesToFailed() async {
    let store = CounterStore()
    await store.mutate { throw AppError.serverUnreachable }
    #expect(store.state == .failed(.serverUnreachable))
  }

  @Test func nonAppErrorIsWrappedAsUnknown() async {
    struct Boom: Error {}
    let store = CounterStore()
    await store.load { throw Boom() }
    // Assert the case, not merely that some error exists — `!= nil` passes
    // even if `wrapping` were changed to return an unrelated AppError.
    #expect(store.state.error == .unknown(String(describing: Boom())))
  }

  @Test func appErrorPassesThroughWithoutDoubleWrapping() async {
    let store = CounterStore()
    await store.load { throw AppError.unauthorized }
    #expect(store.state.error == .unauthorized)
  }

  @Test func mutateSuccessReplacesTheValue() async {
    let store = CounterStore()
    await store.load { 5 }
    await store.mutate { 9 }
    #expect(store.state == .loaded(9))
  }

  @Test func mutateSuccessClearsAPriorActionError() async {
    let store = CounterStore()
    await store.load { 5 }
    await store.mutate { throw AppError.serverUnreachable }
    await store.mutate { 9 }
    #expect(store.state == .loaded(9))
  }

  // The regression this whole type exists to prevent: a second consecutive
  // mutation failure must not lose the originally loaded data.
  @Test func repeatedMutateFailuresKeepTheOriginalData() async {
    let store = CounterStore()
    await store.load { 5 }
    await store.mutate { throw AppError.serverUnreachable }
    await store.mutate { throw AppError.unauthorized }
    #expect(store.state == .actionFailed(5, .unauthorized))
  }

  // A `mutate` that captured `state.value` *before* calling `operation` would
  // revert a failure to whatever was loaded when the operation *started* —
  // discarding anything that wrote `state` during the operation's own `await`.
  // `DockerStore.perform` goes through `mutate`, and its operation is slow
  // enough — a `docker stop` — for another concurrent write to land first.
  // Simulating that
  // here needs no real concurrency: the operation closure itself mutates
  // `store.state` before throwing, standing in for "something else wrote
  // state while this operation was in flight."
  @Test func mutateFailureUsesTheStateCurrentAtFailureNotAPreOperationSnapshot() async {
    let store = CounterStore()
    await store.load { 5 }
    await store.mutate {
      store.state = .loaded(9)
      throw AppError.serverUnreachable
    }
    #expect(store.state == .actionFailed(9, .serverUnreachable))
  }
}

// MARK: - Cancellation and generation guarding

/// A store whose loads suspend until released, so a *superseded* load's late
/// answer can be made to arrive after a newer one has already written — the
/// case the generation guard exists to prevent, and the one that makes a retry
/// button dangerous without it.
///
/// The parked operation checks `Task.isCancelled` when it resumes and rethrows,
/// because that is what a real request does: `URLSession` reports cancellation by
/// failing the request, it doesn't return a value. A fake that resumed
/// successfully regardless would let the store look correct while doing nothing:
/// it passes the stale case while the cancel case is broken.
@MainActor
private final class GatedStore: LoadingStore {
  var state: Loadable<String> = .idle
  let loads = LoadTracker()

  private var continuations: [CheckedContinuation<String, Error>] = []
  /// Whether each load's operation saw itself cancelled when it resumed, keyed by
  /// the label its caller gave it.
  ///
  /// This is how cancellation is asserted, because the `Task` a test holds is the
  /// *outer* one it created — not the inner task `load` tracks and cancels — so
  /// `task.isCancelled` reads false even when the work was cancelled correctly.
  ///
  /// Keyed rather than an array in start order: entries are appended when each
  /// operation *resumes*, and these tests deliberately resume them out of order,
  /// so positional access reads whichever load finished first, and an assertion
  /// that looks right inspects the wrong load.
  private(set) var cancellationsObserved: [String: Bool] = [:]

  /// - Parameter honoursCancellation: when `false`, the operation returns
  ///   successfully even though its task was cancelled — which models a real
  ///   request that already had its response in hand when the cancel landed.
  ///   That is the case where **only** the generation check protects the state,
  ///   and it is the one worth testing separately: cancellation is best-effort,
  ///   the guard is not.
  func beginLoad(_ label: String, honoursCancellation: Bool = true) -> Task<Void, Never> {
    Task { [self] in
      await load { [self] in
        let value = try await withCheckedThrowingContinuation { continuation in
          continuations.append(continuation)
        }
        cancellationsObserved[label] = Task.isCancelled
        if honoursCancellation {
          try Task.checkCancellation()
        }
        return value
      }
    }
  }

  /// Parks a `mutate`'s continuation in the same queue, so a refresh and a load
  /// can be resolved in either order.
  func enqueue(_ continuation: CheckedContinuation<String, Error>) {
    continuations.append(continuation)
  }

  /// Lets the load that started `index`-th resolve with `value`.
  func release(_ index: Int, with value: String) {
    guard index < continuations.count else { return }
    continuations[index].resume(returning: value)
  }

  func waitUntilPending(atLeast count: Int) async {
    while continuations.count < count { await Task.yield() }
  }
}

@MainActor
@Test func aSupersededLoadsLateAnswerIsDropped() async {
  // The assertion this suite exists for. Without the generation guard, a
  // stale request's late response — a 60-second timeout landing after a
  // successful retry — silently overwrites newer state. That is why a retry
  // button without this would make things *worse* than a plain spinner.
  let store = GatedStore()

  let first = store.beginLoad("first")
  await store.waitUntilPending(atLeast: 1)

  // A retry: supersedes the first, which is still in flight.
  let second = store.beginLoad("second")
  await store.waitUntilPending(atLeast: 2)

  // The retry answers first…
  store.release(1, with: "second")
  await second.value
  #expect(store.state.value == "second")

  // …and only then does the superseded request come back.
  store.release(0, with: "stale")
  await first.value

  #expect(store.state.value == "second", "a superseded load's late answer overwrote newer state")
}

@MainActor
@Test func aSupersededLoadThatIgnoresCancellationStillCannotWrite() async {
  // The case that isolates the generation guard from cancellation. A real request
  // that already received its response completes *successfully* even though its
  // task was cancelled — `URLSession` doesn't un-receive bytes — so cancellation
  // cannot be the only protection. Here the superseded operation ignores
  // cancellation, so the `isCurrent` check in `load` is the only thing between
  // its answer and the newer state.
  let store = GatedStore()

  let first = store.beginLoad("first", honoursCancellation: false)
  await store.waitUntilPending(atLeast: 1)
  let second = store.beginLoad("second")
  await store.waitUntilPending(atLeast: 2)

  store.release(1, with: "second")
  await second.value
  #expect(store.state.value == "second")

  // Resolves successfully despite having been cancelled.
  store.release(0, with: "stale")
  await first.value

  #expect(store.state.value == "second", "a superseded load wrote over newer state")
  #expect(store.cancellationsObserved["first"] == true, "precondition: it was cancelled and ignored it")
}

@MainActor
@Test func startingASecondLoadCancelsTheFirst() async {
  // Cancelling the superseded request matters beyond correctness: without it the
  // abandoned request keeps its socket and its 60-second timeout, and on a LAN
  // that has gone away those pile up behind every retry.
  //
  // Asserted from inside the operation, via `cancellationsObserved` — the `Task`
  // this test holds is the outer one it created, not the inner task `load`
  // tracks and cancels, so `first.isCancelled` would be false even when the work
  // was cancelled correctly.
  let store = GatedStore()

  let first = store.beginLoad("first")
  await store.waitUntilPending(atLeast: 1)
  let second = store.beginLoad("second")
  await store.waitUntilPending(atLeast: 2)

  store.release(0, with: "stale")
  await first.value
  #expect(store.cancellationsObserved["first"] == true, "the superseded load was not cancelled")

  store.release(1, with: "second")
  await second.value
  #expect(store.state.value == "second")
}

@MainActor
@Test func cancellingALoadLandsOnAFailureWithARetryPathRatherThanASpinner() async {
  // `.cancelled` rather than back to `.idle`: every screen renders `.failed` with
  // a "Try Again" button, so a cancelled load ends somewhere with a way forward
  // instead of on the indefinite spinner the user was trying to escape.
  let store = GatedStore()
  let task = store.beginLoad("only")
  await store.waitUntilPending(atLeast: 1)

  store.cancelLoad()
  store.release(0, with: "too late")
  await task.value

  #expect(store.state.error == .cancelled)
  #expect(store.state.error?.recoverySuggestion != nil, "a cancelled load offered no way forward")
}

@MainActor
@Test func isLoadInFlightIsFalseBeforeAndAfterALoad() async {
  // What the Cancel button's visibility reads. `.idle` shows a spinner too — the
  // moment between a screen appearing and its `.task` running — and offering
  // Cancel there would be a button that does nothing.
  let store = GatedStore()
  #expect(!store.isLoadInFlight)

  let task = store.beginLoad("only")
  await store.waitUntilPending(atLeast: 1)
  #expect(store.isLoadInFlight)

  store.release(0, with: "value")
  await task.value
  #expect(!store.isLoadInFlight)
}

@MainActor
@Test func aSupersededMutateDoesNotOverwriteANewerLoad() async {
  // `mutate` joins the generation sequence without claiming a new one, so a slow
  // refresh that started before a load cannot write its result over the load's.
  // It deliberately doesn't *cancel* anything: a mutation in flight against a
  // real server must not be abandoned halfway.
  let store = GatedStore()
  store.state = .loaded("original")

  let refresh = Task { [store] in
    await store.mutate {
      try await withCheckedThrowingContinuation { continuation in
        store.enqueue(continuation)
      }
    }
  }
  await store.waitUntilPending(atLeast: 1)

  // A load supersedes it and finishes first.
  let load = store.beginLoad("load")
  await store.waitUntilPending(atLeast: 2)
  store.release(1, with: "reloaded")
  await load.value
  #expect(store.state.value == "reloaded")

  // The refresh's late answer must be discarded.
  store.release(0, with: "stale refresh")
  await refresh.value

  #expect(store.state.value == "reloaded", "a superseded refresh overwrote a newer load")
}

// MARK: - Freshness

@MainActor
@Suite struct LoadFreshnessTests {
  /// The smallest thing that conforms: `RefreshableStore` needs a load and a
  /// refresh, and these record which one ran.
  private final class Spy: RefreshableStore {
    var state: Loadable<Int> = .idle
    let loads = LoadTracker()
    var result: Result<Int, AppError> = .success(1)
    private(set) var loadCount = 0
    private(set) var refreshCount = 0

    func load() async {
      loadCount += 1
      await load { try self.result.get() }
    }

    func refresh() async {
      refreshCount += 1
      await mutate { try self.result.get() }
    }
  }

  @Test func aSuccessfulLoadStampsTheClock() async {
    let store = Spy()
    #expect(store.loads.lastLoadedAt == nil)

    await store.load()

    #expect(store.loads.lastLoadedAt != nil)
  }

  @Test func aFailedLoadDoesNotCountAsFresh() async {
    // Otherwise a service that was unreachable would sit showing its error for
    // the whole staleness window after it came back up.
    let store = Spy()
    store.result = .failure(.serverUnreachable)

    await store.load()

    #expect(store.loads.lastLoadedAt == nil)
    #expect(store.loads.isStale(olderThan: 60))
  }

  @Test func aSuccessfulRefreshIsAsFreshAsALoad() async {
    // Otherwise pull-to-refresh would leave the store looking stale and the
    // next appearance would refetch immediately.
    let store = Spy()
    await store.load()
    let afterLoad = store.loads.lastLoadedAt

    await store.refresh()

    #expect(store.loads.lastLoadedAt != nil)
    #expect(store.loads.lastLoadedAt! >= afterLoad!)
  }

  @Test func stalenessIsMeasuredFromTheLastSuccess() async {
    let store = Spy()
    await store.load()
    let stamped = try! #require(store.loads.lastLoadedAt)

    #expect(!store.loads.isStale(olderThan: 60, now: stamped.addingTimeInterval(59)))
    #expect(store.loads.isStale(olderThan: 60, now: stamped.addingTimeInterval(61)))
  }

  @Test func appearingWithNoDataLoads() async {
    let store = Spy()

    await store.appeared()

    #expect(store.loadCount == 1)
    #expect(store.refreshCount == 0)
  }

  @Test func appearingWithFreshDataDoesNothing() async {
    // Coming back to a service you just left must not hit the network at all.
    let store = Spy()
    await store.load()

    await store.appeared()

    #expect(store.loadCount == 1, "a fresh store refetched on appear")
    #expect(store.refreshCount == 0)
  }

  @Test func appearingWithStaleDataRefreshesRatherThanLoads() async {
    // `refresh` and not `load`, so the list stays on screen while it updates.
    let store = Spy()
    await store.load()

    await store.appeared(staleAfter: 0)

    #expect(store.loadCount == 1)
    #expect(store.refreshCount == 1)
    #expect(store.state.value != nil, "the data blanked during a stale refresh")
  }

  @Test func appearingAfterAFailureLoadsAgain() async {
    // A retained store keeps its error, which is right — but it must not keep
    // it forever once the service is back.
    let store = Spy()
    store.result = .failure(.serverUnreachable)
    await store.load()
    store.result = .success(7)

    await store.appeared()

    #expect(store.loadCount == 2)
    #expect(store.state.value == 7)
  }
}
