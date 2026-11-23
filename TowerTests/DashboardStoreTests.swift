import Foundation
import Testing
import TowerCore
import TowerData
@testable import Tower

@MainActor
struct DashboardStoreTests {
  @Test func loadsDashboardSnapshot() async {
    let snapshot = DashboardSnapshot.fixture(state: "STARTED")
    let repository = StubDashboardRepository(results: [.success(snapshot)])
    let store = DashboardStore(repository: repository, metrics: ScriptedMetricsStream())
    await store.load()
    #expect(store.state.value?.array.state == "STARTED")
  }

  @Test func surfacesFailuresAsAppError() async {
    let repository = StubDashboardRepository(results: [.failure(.unauthorized)])
    let store = DashboardStore(repository: repository, metrics: ScriptedMetricsStream())
    await store.load()
    #expect(store.state.error == .unauthorized)
  }

  // The one that earns its place: `refresh()` must use `mutate`, not `load`,
  // so a transient poll failure 30 seconds in does not blank a working
  // dashboard. A failing refresh must keep the first snapshot on screen
  // *and* surface the new error via `.actionFailed`.
  @Test func refreshKeepsPreviousDataOnFailure() async {
    let snapshot = DashboardSnapshot.fixture(state: "STARTED")
    let repository = StubDashboardRepository(results: [
      .success(snapshot),
      .failure(.serverUnreachable),
    ])
    let store = DashboardStore(repository: repository, metrics: ScriptedMetricsStream())
    await store.load()
    await store.refresh()
    #expect(store.state.value == snapshot)
    #expect(store.state.error != nil)
  }

  // MARK: - Parity actions

  @Test func eachParityActionCallsItsOwnMutationThenRefetches() async {
    let running = DashboardSnapshot.fixture(state: "STARTED", parity: .running)
    let paused = DashboardSnapshot.fixture(state: "STARTED", parity: .paused)
    let repository = GatedDashboardRepository(dashboardResults: [.success(paused)])
    await repository.gate.releaseAll()
    let store = DashboardStore(repository: repository, metrics: ScriptedMetricsStream())
    store.state = .loaded(running)

    await store.perform(.pause)

    #expect(repository.calls == ["pause", "dashboard"])
    #expect(store.state == .loaded(paused))
    #expect(store.parityActionInFlight == nil)
  }

  @Test func startPassesTheCorrectChoiceThrough() async {
    for correct in [true, false] {
      let idle = DashboardSnapshot.fixture(state: "STARTED", parity: .completed)
      let repository = GatedDashboardRepository(dashboardResults: [.success(idle)])
      await repository.gate.releaseAll()
      let store = DashboardStore(repository: repository, metrics: ScriptedMetricsStream())
      store.state = .loaded(idle)

      await store.perform(.start, correct: correct)

      #expect(repository.calls == ["start(correct: \(correct))", "dashboard"])
    }
  }

  @Test func aFailedParityActionKeepsTheDashboardAndShowsTheServersMessage() async {
    let running = DashboardSnapshot.fixture(state: "STARTED", parity: .running)
    let repository = GatedDashboardRepository(
      dashboardResults: [.success(running)],
      actionResult: .failure(.graphQL(["Array must be started to check parity"]))
    )
    await repository.gate.releaseAll()
    let store = DashboardStore(repository: repository, metrics: ScriptedMetricsStream())
    store.state = .loaded(running)

    await store.perform(.cancel)

    #expect(store.state.value == running)
    #expect(store.state.error?.message == "Array must be started to check parity")
    #expect(repository.calls == ["cancel"], "a failed action must not re-fetch")
    #expect(store.parityActionInFlight == nil)
  }

  @Test func aFailedRefetchAfterASuccessfulActionSaysTheActionSucceeded() async {
    // "Cancel Check failed" would be false, and it invites a retry of an
    // action that already happened.
    let running = DashboardSnapshot.fixture(state: "STARTED", parity: .running)
    let repository = GatedDashboardRepository(dashboardResults: [.failure(.serverUnreachable)])
    await repository.gate.releaseAll()
    let store = DashboardStore(repository: repository, metrics: ScriptedMetricsStream())
    store.state = .loaded(running)

    await store.perform(.cancel)

    #expect(store.state.value == running)
    let message = store.state.error?.message ?? ""
    #expect(message.hasPrefix("Cancel Check succeeded, but Tower couldn't refresh the parity status."), "\(message)")
  }

  @Test func aSecondParityActionWhileOneIsInFlightIsIgnored() async {
    let running = DashboardSnapshot.fixture(state: "STARTED", parity: .running)
    let repository = GatedDashboardRepository(dashboardResults: [.success(running)])
    let store = DashboardStore(repository: repository, metrics: ScriptedMetricsStream())
    store.state = .loaded(running)

    let first = Task { await store.perform(.pause) }
    await repository.gate.waitUntilEntered(atLeast: 1)
    #expect(store.parityActionInFlight == .pause)

    await store.perform(.cancel)
    #expect(repository.calls == ["pause"], "the second action must not reach the repository")

    await repository.gate.releaseAll()
    await first.value
    #expect(repository.calls == ["pause", "dashboard"])
    #expect(store.parityActionInFlight == nil)
  }

  @Test func aPollIssuedBeforeAParityActionDoesNotRevertIt() async {
    // The poll asks first and so claims the pre-action snapshot (running);
    // the action's re-fetch claims the post-action one (paused). Without the
    // guard the poll's late answer lands last and the card reads "running".
    let running = DashboardSnapshot.fixture(state: "STARTED", parity: .running)
    let paused = DashboardSnapshot.fixture(state: "STARTED", parity: .paused)
    let repository = GatedDashboardRepository(dashboardResults: [.success(running), .success(paused)])
    let store = DashboardStore(repository: repository, metrics: ScriptedMetricsStream())
    store.state = .loaded(running)

    let poll = Task { await store.refresh() }
    await repository.gate.waitUntilEntered(atLeast: 1)

    let pause = Task { await store.perform(.pause) }
    await repository.gate.waitUntilEntered(atLeast: 2)
    await repository.gate.release(1)
    await repository.gate.release(2)
    await pause.value
    #expect(store.state.value?.parity.state == .paused)

    await repository.gate.release(0)
    await poll.value

    #expect(store.state.value?.parity.state == .paused, "a poll issued before the action must not revert it")
    #expect(store.state.error == nil)
  }
}

// MARK: - Array actions (issue #25)

// A time limit, because these tests park the store on gates: a regression
// there hangs rather than fails.
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct DashboardArrayActionTests {
  private let started = DashboardSnapshot.fixture(state: "STARTED")
  private let stopped = DashboardSnapshot.fixture(state: "STOPPED")

  /// No real time: every re-fetch follows the last at once.
  private func makeStore(_ repository: GatedDashboardRepository, attempts: Int = 30) -> DashboardStore {
    DashboardStore(
      repository: repository, metrics: ScriptedMetricsStream(),
      arrayPollInterval: .zero, arrayPollAttempts: attempts
    )
  }

  @Test func anAnswerWithTheNewStateRefetchesOnce() async {
    let repository = GatedDashboardRepository(dashboardResults: [.success(stopped)], arrayResults: [.success("STOPPED")])
    await repository.gate.releaseAll()
    let store = makeStore(repository)
    store.state = .loaded(started)

    await store.perform(.stop)

    #expect(repository.calls == ["setArrayState(stop, passphrase: false)", "dashboard"])
    #expect(store.state == .loaded(stopped))
    #expect(store.arrayActionInFlight == nil)
  }

  @Test func thePassphraseGoesIntoTheRequestAndNowhereElse() async {
    let started = DashboardSnapshot.fixture(state: "STARTED")
    let repository = GatedDashboardRepository(dashboardResults: [.success(started)], arrayResults: [.success("STARTED")])
    let store = makeStore(repository)
    store.state = .loaded(stopped)

    let start = Task { await store.perform(.start, passphrase: "hunter2-secret") }
    await repository.gate.waitUntilEntered(atLeast: 1)
    #expect(store.arrayActionInFlight == .start)
    #expect(!String(describing: store.arrayActionInFlight).contains("hunter2"))
    await repository.gate.releaseAll()
    await start.value

    #expect(repository.passphrases == ["hunter2-secret"])
    #expect(store.state == .loaded(started))
    #expect(!String(describing: store.state).contains("hunter2"))
  }

  /// Unraid can answer before the change is done.
  @Test func anAnswerWithTheOldStatePollsUntilTheArrayChanges() async {
    let repository = GatedDashboardRepository(
      dashboardResults: [.success(started), .failure(.serverUnreachable), .success(stopped)],
      arrayResults: [.success("STARTED")]
    )
    await repository.gate.releaseAll()
    let store = makeStore(repository)
    store.state = .loaded(started)

    await store.perform(.stop)

    #expect(repository.calls == ["setArrayState(stop, passphrase: false)", "dashboard", "dashboard", "dashboard"])
    #expect(store.state == .loaded(stopped), "a failed re-fetch must not end the wait")
    #expect(store.arrayActionInFlight == nil)
  }

  /// A request that times out reached the server. Poll, do not fail.
  @Test func aTimedOutRequestPollsToo() async {
    let repository = GatedDashboardRepository(
      dashboardResults: [.success(stopped), .success(started)], arrayResults: [.success(nil)]
    )
    await repository.gate.releaseAll()
    let store = makeStore(repository)
    store.state = .loaded(stopped)

    await store.perform(.start)

    #expect(store.state == .loaded(started))
    #expect(store.state.error == nil)
  }

  @Test func theControlsStayDisabledForTheWholeWait() async {
    let repository = GatedDashboardRepository(
      dashboardResults: [.success(started), .success(stopped)], arrayResults: [.success("STARTED")]
    )
    let store = makeStore(repository)
    store.state = .loaded(started)
    let stop = Task { await store.perform(.stop) }

    await repository.gate.release(0)
    await repository.gate.waitUntilEntered(atLeast: 2)
    #expect(store.arrayActionInFlight == .stop, "the in-flight action ended before the array stopped")
    #expect(store.isActionInFlight)

    await repository.gate.releaseAll()
    await stop.value
    #expect(store.arrayActionInFlight == nil)
  }

  @Test func anEncryptedStartThatLeavesTheArrayStoppedSaysThePassphraseMayBeWrong() async {
    let repository = GatedDashboardRepository(
      dashboardResults: [.success(stopped), .success(stopped), .success(stopped)],
      arrayResults: [.success("STOPPED")]
    )
    await repository.gate.releaseAll()
    let store = makeStore(repository, attempts: 3)
    store.state = .loaded(stopped)

    await store.perform(.start, passphrase: "wrong")

    #expect(repository.calls.filter { $0 == "dashboard" }.count == 3)
    #expect(store.state.value == stopped)
    #expect(store.state.error?.message == "The array did not start. The passphrase may be wrong.")
    #expect(store.arrayActionInFlight == nil)
  }

  @Test func aPlainStartThatNeverStartsSaysItHasNotStartedYet() async {
    let repository = GatedDashboardRepository(
      dashboardResults: [.success(stopped), .success(stopped)], arrayResults: [.success("STOPPED")]
    )
    await repository.gate.releaseAll()
    let store = makeStore(repository, attempts: 2)
    store.state = .loaded(stopped)

    await store.perform(.start)

    #expect(store.state.error == .stillRunning("The array has not started yet. Pull to refresh to check again."))
  }

  /// The wait ends on the newest snapshot, not the one from before the action.
  @Test func aWaitThatEndsShowsTheNewestStateUnderTheError() async {
    let changed = DashboardSnapshot.fixture(state: "STARTED", parity: .completed)
    let repository = GatedDashboardRepository(
      dashboardResults: [.success(changed)], arrayResults: [.success("STARTED")]
    )
    await repository.gate.releaseAll()
    let store = makeStore(repository, attempts: 1)
    store.state = .loaded(started)

    await store.perform(.stop)

    #expect(store.state.value == changed)
    #expect(store.state.error == .stillRunning("The array has not stopped yet. Pull to refresh to check again."))
  }

  @Test func aServerErrorShowsItsMessageAndKeepsTheDashboard() async {
    let repository = GatedDashboardRepository(
      dashboardResults: [], arrayResults: [.failure(.graphQL(["Array state is still being updated"]))]
    )
    await repository.gate.releaseAll()
    let store = makeStore(repository)
    store.state = .loaded(started)

    await store.perform(.stop)

    #expect(store.state.value == started)
    #expect(store.state.error?.message == "Array state is still being updated")
    #expect(repository.calls == ["setArrayState(stop, passphrase: false)"], "a failed action must not re-fetch")
    #expect(store.arrayActionInFlight == nil)
  }

  @Test func aFailedRefetchAfterTheNewStateSaysTheActionSucceeded() async {
    let repository = GatedDashboardRepository(
      dashboardResults: [.failure(.serverUnreachable)], arrayResults: [.success("STOPPED")]
    )
    await repository.gate.releaseAll()
    let store = makeStore(repository)
    store.state = .loaded(started)

    await store.perform(.stop)

    let message = store.state.error?.message ?? ""
    #expect(message.hasPrefix("Stop Array succeeded, but Tower couldn't refresh the array status."), "\(message)")
  }

  @Test func noSecondActionOfEitherKindWhileAnArrayActionRuns() async {
    let repository = GatedDashboardRepository(dashboardResults: [.success(stopped)], arrayResults: [.success("STOPPED")])
    let store = makeStore(repository)
    store.state = .loaded(started)

    let stop = Task { await store.perform(.stop) }
    await repository.gate.waitUntilEntered(atLeast: 1)
    await store.perform(.stop)
    await store.perform(.start)
    await store.perform(.pause)
    #expect(repository.calls == ["setArrayState(stop, passphrase: false)"])

    await repository.gate.releaseAll()
    await stop.value
    #expect(repository.calls == ["setArrayState(stop, passphrase: false)", "dashboard"])
  }

  @Test func noArrayActionWhileAParityActionRuns() async {
    let running = DashboardSnapshot.fixture(state: "STARTED", parity: .running)
    let repository = GatedDashboardRepository(dashboardResults: [.success(running)])
    let store = makeStore(repository)
    store.state = .loaded(running)

    let pause = Task { await store.perform(.pause) }
    await repository.gate.waitUntilEntered(atLeast: 1)
    #expect(store.isActionInFlight)
    await store.perform(.stop)
    #expect(repository.calls == ["pause"])

    await repository.gate.releaseAll()
    await pause.value
  }

  @Test func aPollIssuedBeforeAnArrayActionDoesNotRevertIt() async {
    let repository = GatedDashboardRepository(
      dashboardResults: [.success(started), .success(stopped)], arrayResults: [.success("STOPPED")]
    )
    let store = makeStore(repository)
    store.state = .loaded(started)

    let poll = Task { await store.refresh() }
    await repository.gate.waitUntilEntered(atLeast: 1)
    let stop = Task { await store.perform(.stop) }
    await repository.gate.waitUntilEntered(atLeast: 2)
    await repository.gate.release(1)
    await repository.gate.release(2)
    await stop.value
    #expect(store.state.value?.array.state == "STOPPED")

    await repository.gate.release(0)
    await poll.value

    #expect(store.state.value?.array.state == "STOPPED", "a poll issued before the action must not revert it")
  }
}

// MARK: - Live metrics (issue #24)

// A time limit, because these tests park the store on gates: a regression
// there hangs rather than fails.
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct DashboardLiveMetricsTests {
  private static func system(cpu: Double, memory: Double) -> SystemInfo {
    SystemInfo(
      distro: nil, release: nil, bootTimestamp: nil, cpuBrand: nil, cpuCores: 8, cpuThreads: 16,
      cpuPercent: cpu, memoryPercent: memory,
      memoryUsedBytes: 28_000_000_000, memoryTotalBytes: 32_000_000_000
    )
  }

  private let polled = DashboardSnapshot.fixture(
    state: "STARTED", system: Self.system(cpu: 12, memory: 88))
  private let celsius52 = TemperatureReading(value: 52, unit: .celsius)

  /// Yields to the main actor until `condition` holds or 1,000 yields pass.
  /// Callers `#expect` the condition afterwards, so running out is a failure.
  private func settle(_ condition: () -> Bool) async {
    for _ in 0..<1_000 where !condition() { await Task.yield() }
  }

  @Test func liveReadingsShowOverThePolledSnapshotAndLeaveStateAlone() async {
    let metrics = ScriptedMetricsStream()
    let store = DashboardStore(repository: StubDashboardRepository(results: []), metrics: metrics)
    store.state = .loaded(polled)
    let streaming = Task { await store.streamLiveMetrics() }

    await metrics.waitForCall(0)
    metrics.continuation(0).yield(.cpu(percent: 47))
    metrics.continuation(0).yield(.cpuTemperature(celsius52))
    await settle { store.cpuTemperature != nil }

    #expect(store.system(for: polled)?.cpuPercent == 47)
    #expect(store.system(for: polled)?.memoryPercent == 88)
    #expect(store.cpuTemperature == celsius52)
    #expect(store.state == .loaded(polled))
    streaming.cancel()
    await streaming.value
  }

  // The poll stays on for the array, disks and counts. Its CPU reading is
  // older than the stream's, so it must not replace the live value.
  @Test func aPollDoesNotOverwriteALiveValue() async {
    let newer = DashboardSnapshot.fixture(state: "STARTED", system: Self.system(cpu: 20, memory: 80))
    let metrics = ScriptedMetricsStream()
    let store = DashboardStore(
      repository: StubDashboardRepository(results: [.success(newer)]), metrics: metrics)
    store.state = .loaded(polled)
    let streaming = Task { await store.streamLiveMetrics() }
    await metrics.waitForCall(0)
    metrics.continuation(0).yield(.cpu(percent: 47))
    await settle { store.liveMetrics.cpuPercent != nil }

    await store.refresh()

    #expect(store.state == .loaded(newer))
    #expect(store.system(for: newer)?.cpuPercent == 47)
    #expect(store.system(for: newer)?.memoryPercent == 80)
    streaming.cancel()
    await streaming.value
  }

  @Test func aStreamThatEndsLeavesThePolledValues() async {
    let metrics = ScriptedMetricsStream()
    let store = DashboardStore(repository: StubDashboardRepository(results: []), metrics: metrics)
    store.state = .loaded(polled)
    let streaming = Task { await store.streamLiveMetrics() }
    await metrics.waitForCall(0)
    metrics.continuation(0).yield(.cpu(percent: 47))
    metrics.continuation(0).yield(.cpuTemperature(celsius52))

    metrics.continuation(0).finish()
    await streaming.value

    #expect(store.liveMetrics.isEmpty)
    #expect(store.system(for: polled)?.cpuPercent == 12)
  }

  // The acceptance criterion: a websocket failure shows no alarming
  // message. `.actionFailed` is what renders the dashboard's red caption.
  @Test func aStreamFailureFallsBackSilently() async {
    let metrics = ScriptedMetricsStream()
    let store = DashboardStore(repository: StubDashboardRepository(results: []), metrics: metrics)
    store.state = .loaded(polled)
    let streaming = Task { await store.streamLiveMetrics() }
    await metrics.waitForCall(0)
    metrics.continuation(0).yield(.cpu(percent: 47))

    metrics.continuation(0).finish(throwing: AppError.serverUnreachable)
    await streaming.value

    #expect(store.state == .loaded(polled))
    #expect(store.state.error == nil)
    #expect(store.liveMetrics.isEmpty)
  }

  // Leaving the tab or backgrounding the app cancels the `.task`.
  @Test func cancellingTheStreamClearsTheLiveValues() async {
    let metrics = ScriptedMetricsStream()
    let store = DashboardStore(repository: StubDashboardRepository(results: []), metrics: metrics)
    let streaming = Task { await store.streamLiveMetrics() }
    await metrics.waitForCall(0)
    metrics.continuation(0).yield(.cpu(percent: 47))
    await settle { store.liveMetrics.cpuPercent != nil }

    streaming.cancel()
    await streaming.value

    #expect(store.liveMetrics.isEmpty)
  }

  // A stream that goes quiet without closing must not freeze an old reading
  // on screen. Each metric expires on its own cadence.
  @Test func aQuietMetricExpiresWithoutTheOthers() async {
    let cpuClock = Gate()
    let memoryClock = Gate()
    let metrics = ScriptedMetricsStream()
    let store = DashboardStore(
      repository: StubDashboardRepository(results: []), metrics: metrics,
      staleAfter: [.cpu: .seconds(1), .memory: .seconds(2)],
      sleep: { delay in
        if delay == .seconds(1) { await cpuClock.enter() } else { await memoryClock.enter() }
      }
    )
    let streaming = Task { await store.streamLiveMetrics() }
    await metrics.waitForCall(0)
    metrics.continuation(0).yield(.cpu(percent: 47))
    metrics.continuation(0).yield(.memory(percent: 50, usedBytes: 1, totalBytes: 2))
    await cpuClock.waitUntilEntered(atLeast: 1)
    await memoryClock.waitUntilEntered(atLeast: 1)

    await cpuClock.release(0)
    await settle { store.liveMetrics.cpuPercent == nil }

    #expect(store.liveMetrics.cpuPercent == nil)
    #expect(store.liveMetrics.memory?.percent == 50)
    streaming.cancel()
    await streaming.value
  }

  @Test func aNewReadingPostponesItsMetricsExpiry() async {
    let clock = Gate()
    let metrics = ScriptedMetricsStream()
    let store = DashboardStore(
      repository: StubDashboardRepository(results: []), metrics: metrics,
      sleep: { _ in await clock.enter() }
    )
    let streaming = Task { await store.streamLiveMetrics() }
    await metrics.waitForCall(0)
    metrics.continuation(0).yield(.cpu(percent: 47))
    await clock.waitUntilEntered(atLeast: 1)
    metrics.continuation(0).yield(.cpu(percent: 50))
    await clock.waitUntilEntered(atLeast: 2)

    // The first reading's expiry wakes, but the second reading replaced it.
    await clock.release(0)
    for _ in 0..<100 { await Task.yield() }
    #expect(store.liveMetrics.cpuPercent == 50)

    await clock.release(1)
    await settle { store.liveMetrics.cpuPercent == nil }
    #expect(store.liveMetrics.cpuPercent == nil)
    streaming.cancel()
    await streaming.value
  }

  // The poll has no temperature to fall back to. Removing the row on every
  // stale expiry or dropped stream made every card below it jump, so the last
  // reading stays for the session.
  @Test func theTemperatureOutlivesTheCpuExpiryAndTheStream() async {
    let cpuClock = Gate()
    let metrics = ScriptedMetricsStream()
    let store = DashboardStore(
      repository: StubDashboardRepository(results: []), metrics: metrics,
      staleAfter: [.cpu: .seconds(1), .memory: .seconds(2)],
      sleep: { delay in
        if delay == .seconds(1) { await cpuClock.enter() } else { try await Task.sleep(for: .seconds(3_600)) }
      }
    )
    let streaming = Task { await store.streamLiveMetrics() }
    await metrics.waitForCall(0)
    metrics.continuation(0).yield(.cpu(percent: 47))
    metrics.continuation(0).yield(.cpuTemperature(celsius52))
    await cpuClock.waitUntilEntered(atLeast: 1)

    await cpuClock.release(0)
    await settle { store.liveMetrics.cpuPercent == nil }
    #expect(store.liveMetrics.cpuPercent == nil)
    #expect(store.cpuTemperature == celsius52, "a stale CPU expiry removed the temperature row")

    metrics.continuation(0).finish(throwing: AppError.serverUnreachable)
    await streaming.value
    #expect(store.liveMetrics.isEmpty)
    #expect(store.cpuTemperature == celsius52, "a failed stream removed the temperature row")
  }

  @Test func aServerWithNoCpuSensorHidesTheTemperature() async {
    let metrics = ScriptedMetricsStream()
    let store = DashboardStore(repository: StubDashboardRepository(results: []), metrics: metrics)
    let streaming = Task { await store.streamLiveMetrics() }
    await metrics.waitForCall(0)
    metrics.continuation(0).yield(.cpuTemperature(celsius52))
    await settle { store.cpuTemperature != nil }
    #expect(store.cpuTemperature == celsius52)

    metrics.continuation(0).yield(.cpuTemperature(nil))
    await settle { store.cpuTemperature == nil }
    #expect(store.cpuTemperature == nil)
    streaming.cancel()
    await streaming.value
  }

  // A tab switch cancels one stream and starts the next together. The old
  // stream's cleanup lands second and must not wipe the new readings.
  @Test func anOldStreamsCleanupLeavesANewStreamsReadings() async {
    let metrics = ScriptedMetricsStream()
    let store = DashboardStore(repository: StubDashboardRepository(results: []), metrics: metrics)
    let first = Task { await store.streamLiveMetrics() }
    await metrics.waitForCall(0)
    let second = Task { await store.streamLiveMetrics() }
    await metrics.waitForCall(1)
    metrics.continuation(1).yield(.cpu(percent: 47))
    await settle { store.liveMetrics.cpuPercent != nil }

    metrics.continuation(0).finish()
    await first.value

    #expect(store.liveMetrics.cpuPercent == 47)
    second.cancel()
    await second.value
  }
}

/// A live stream each test drives by hand. Every `liveMetrics()` call makes a
/// new stream, so a test can hold two at once.
final class ScriptedMetricsStream: MetricsStreaming, @unchecked Sendable {
  typealias Continuation = AsyncThrowingStream<LiveMetricsUpdate, any Error>.Continuation
  private let lock = NSLock()
  private var continuations: [Continuation] = []

  func liveMetrics() -> AsyncThrowingStream<LiveMetricsUpdate, any Error> {
    let (stream, continuation) = AsyncThrowingStream<LiveMetricsUpdate, any Error>.makeStream()
    lock.withLock { continuations.append(continuation) }
    return stream
  }

  var callCount: Int { lock.withLock { continuations.count } }

  func continuation(_ index: Int) -> Continuation {
    lock.withLock { continuations[index] }
  }

  /// Yields until `liveMetrics()` has been called `index + 1` times, or the
  /// test is cancelled. A suite's time limit cancels the test, so a call that
  /// never comes fails the test instead of hanging the run.
  func waitForCall(_ index: Int) async {
    while lock.withLock({ continuations.count }) <= index, !Task.isCancelled {
      await Task.yield()
    }
  }
}

@MainActor
struct ParityHistoryStoreTests {
  @Test func loadsTheRepositorysHistory() async {
    let records = [
      ParityCheckRecord(id: 0, date: nil, durationSeconds: 100, speed: "120 MB/s", state: .completed, errors: 0),
    ]
    let repository = GatedDashboardRepository(dashboardResults: [], history: [.success(records)])
    await repository.gate.releaseAll()
    let store = ParityHistoryStore(repository: repository)

    await store.load()

    #expect(store.state == .loaded(records))
  }

  @Test func aFailedRefreshKeepsTheList() async {
    let records = [
      ParityCheckRecord(id: 0, date: nil, durationSeconds: 100, speed: "120 MB/s", state: .completed, errors: 0),
    ]
    let repository = GatedDashboardRepository(
      dashboardResults: [], history: [.success(records), .failure(.serverUnreachable)]
    )
    await repository.gate.releaseAll()
    let store = ParityHistoryStore(repository: repository)

    await store.load()
    await store.refresh()

    #expect(store.state.value == records)
    #expect(store.state.error == .serverUnreachable)
  }
}

/// `results` is a queue rather than a single fixed outcome:
/// `refreshKeepsPreviousDataOnFailure` needs `dashboard()` to answer
/// differently across two calls (a successful load, then a failing
/// refresh), which a single stored `Result` can't express.
private final class StubDashboardRepository: SystemRepositoryProtocol, @unchecked Sendable {
  enum Result { case success(DashboardSnapshot), failure(AppError) }
  private var results: [Result]

  init(results: [Result]) { self.results = results }

  func testConnection() async throws -> Bool { true }

  func dashboard() async throws -> DashboardSnapshot {
    precondition(!results.isEmpty, "dashboard() called more times than results were stubbed")
    switch results.removeFirst() {
    case .success(let snapshot): return snapshot
    case .failure(let error): throw error
    }
  }

  func startParityCheck(correct: Bool) async throws { unreachable() }
  func pauseParityCheck() async throws { unreachable() }
  func resumeParityCheck() async throws { unreachable() }
  func cancelParityCheck() async throws { unreachable() }
  func parityHistory() async throws -> [ParityCheckRecord] { unreachable() }
  func setArrayState(_ action: ArrayAction, passphrase: String?) async throws -> String? { unreachable() }

  private func unreachable() -> Never {
    preconditionFailure("the load and refresh tests never trigger parity or array actions")
  }
}

/// Records every call in order and suspends each on `gate` until the test
/// releases it, so the in-flight and stale-poll tests can observe the store
/// mid-action. Each `dashboard()` call claims its result when it is made, not
/// when it is released, the same as `VMStoreTests.GatedVMRepository`.
private final class GatedDashboardRepository: SystemRepositoryProtocol, @unchecked Sendable {
  enum Result<Value> { case success(Value), failure(AppError) }

  let gate = Gate()
  private let lock = NSLock()
  private var dashboardResults: [Result<DashboardSnapshot>]
  private var historyResults: [Result<[ParityCheckRecord]>]
  private let actionResult: Result<Void>
  private var arrayResults: [Result<String?>]
  private var _calls: [String] = []
  private var _passphrases: [String] = []
  var calls: [String] { lock.withLock { _calls } }
  /// Every passphrase `setArrayState` received. `calls` records only whether
  /// one was sent.
  var passphrases: [String] { lock.withLock { _passphrases } }

  init(
    dashboardResults: [Result<DashboardSnapshot>],
    history: [Result<[ParityCheckRecord]>] = [],
    actionResult: Result<Void> = .success(()),
    arrayResults: [Result<String?>] = []
  ) {
    self.dashboardResults = dashboardResults
    self.historyResults = history
    self.actionResult = actionResult
    self.arrayResults = arrayResults
  }

  func testConnection() async throws -> Bool { true }

  func dashboard() async throws -> DashboardSnapshot {
    let result = lock.withLock {
      _calls.append("dashboard")
      return dashboardResults.removeFirst()
    }
    _ = await gate.enter()
    switch result {
    case .success(let snapshot): return snapshot
    case .failure(let error): throw error
    }
  }

  func startParityCheck(correct: Bool) async throws { try await act("start(correct: \(correct))") }
  func pauseParityCheck() async throws { try await act("pause") }
  func resumeParityCheck() async throws { try await act("resume") }
  func cancelParityCheck() async throws { try await act("cancel") }

  func parityHistory() async throws -> [ParityCheckRecord] {
    let result = lock.withLock { historyResults.removeFirst() }
    switch result {
    case .success(let records): return records
    case .failure(let error): throw error
    }
  }

  func setArrayState(_ action: ArrayAction, passphrase: String?) async throws -> String? {
    let result = lock.withLock {
      _calls.append("setArrayState(\(action), passphrase: \(passphrase != nil))")
      if let passphrase { _passphrases.append(passphrase) }
      return arrayResults.removeFirst()
    }
    _ = await gate.enter()
    switch result {
    case .success(let state): return state
    case .failure(let error): throw error
    }
  }

  private func act(_ name: String) async throws {
    lock.withLock { _calls.append(name) }
    _ = await gate.enter()
    if case .failure(let error) = actionResult { throw error }
  }
}

extension DashboardSnapshot {
  fileprivate static func fixture(
    state: String, parity: ParityCheckState = .neverRun, system: SystemInfo? = nil
  ) -> DashboardSnapshot {
    DashboardSnapshot(
      array: ArrayStatus(
        state: state, capacity: ArrayCapacity(free: 1, used: 3, total: 4),
        disks: [], parities: [], caches: [], system: system
      ),
      parity: ParityStatus(
        state: parity, progressPercent: nil, errors: nil,
        speed: nil, lastRunTimestamp: nil, durationSeconds: nil, correcting: false
      ),
      services: ServiceCounts(
        containersRunning: 0, containersTotal: 0, vmsRunning: 0, vmsTotal: 0,
        sharesTotal: 0
      )
    )
  }
}
