import Foundation
import Observation
import TowerCore
import TowerData

@MainActor
@Observable
final class DashboardStore: LoadingStore {
  var state: Loadable<DashboardSnapshot> = .idle

  /// The one line `LoadingStore` needs per store — see `LoadTracker` for why it
  /// can't live in the protocol extension.
  let loads = LoadTracker()

  /// The parity action in flight, if any. The controls read this to disable
  /// themselves, and `perform(_:correct:)` checks it first so a second tap is
  /// ignored rather than sending a second mutation.
  private(set) var parityActionInFlight: ParityAction?
  /// The array action in flight, if any, until the array reaches its new state
  /// or the wait ends. Never carries the passphrase.
  private(set) var arrayActionInFlight: ArrayAction?
  /// Whether any parity or array action runs. Every control on the hero card
  /// disables itself on this, and both `perform` methods return early on it:
  /// a stop cancels a running parity check, and a parity action on an array
  /// that is changing state can only fail.
  var isActionInFlight: Bool { parityActionInFlight != nil || arrayActionInFlight != nil }
  /// Bumped once per parity or array action the server accepts. `refresh()` captures it
  /// before its fetch and compares afterwards: a poll that was in flight while
  /// an action landed predates the action and shows the old parity state. Same
  /// guard as `VMStore` and `DockerStore`.
  private var mutationSequence = 0

  /// Live CPU and memory over the polled snapshot (issue #24). Kept apart from `state`, so a poll never overwrites a live value
  /// and a live value never reaches `.actionFailed` or the parity guard.
  ///
  /// Empty whenever no stream runs. The 30 s poll stays on beside the stream,
  /// because the array, the disks and the service counts come only from it.
  private(set) var liveMetrics = LiveMetrics()

  /// The last CPU temperature the stream sent this session, which the
  /// dashboard shows. Unlike CPU and memory, the poll has no temperature to
  /// fall back to, so a stale expiry or a stream failure keeps this value
  /// rather than removing the row, and the cards below do not jump. `nil`
  /// until the first reading, and again when the server reports no CPU sensor.
  private(set) var cpuTemperature: TemperatureReading?

  /// One pending expiry per metric. Each update replaces its metric's task.
  private var expiries: [LiveMetric: Task<Void, Never>] = [:]
  /// Bumped by each `streamLiveMetrics()` call; see its cleanup.
  private var streamGeneration = 0

  private let repository: any SystemRepositoryProtocol
  private let metrics: any MetricsStreaming
  private let staleAfter: [LiveMetric: Duration]
  private let sleep: @Sendable (Duration) async throws -> Void
  private let arrayPollInterval: Duration
  private let arrayPollAttempts: Int

  /// The wait between re-fetches after an array action: 2 s. `#if DEBUG`
  /// only, `UITEST_ARRAY_POLL_INTERVAL_MS` shortens it, so a UI test can reach
  /// the end of the wait without 60 real seconds. Not `UITEST_POLL_INTERVAL_MS`:
  /// a fast dashboard poll replaces the error line before a test can read it.
  static var defaultArrayPollInterval: Duration {
    #if DEBUG
    if let raw = ProcessInfo.processInfo.environment["UITEST_ARRAY_POLL_INTERVAL_MS"],
       let milliseconds = Int(raw) {
      return .milliseconds(milliseconds)
    }
    #endif
    return .seconds(2)
  }

  /// - Parameters:
  ///   - staleAfter: How long a live CPU or memory value stays on screen with
  ///     no new reading. About three times each metric's measured cadence
  ///     (CPU 1 s, memory 2 s), so one late reading does not flicker the polled
  ///     value in, and a stream that has gone quiet without closing does not
  ///     freeze an old reading on screen. The CPU temperature never expires;
  ///     see `cpuTemperature`.
  ///   - sleep: Injected, as `poll` injects it, so tests use no real time.
  ///   - arrayPollInterval, arrayPollAttempts: How often and how many times
  ///     `perform(_:passphrase:)` re-fetches while the array changes state.
  ///     30 times every 2 s is a minute.
  init(
    repository: any SystemRepositoryProtocol,
    metrics: any MetricsStreaming,
    staleAfter: [LiveMetric: Duration] = [
      .cpu: .seconds(3), .memory: .seconds(6),
    ],
    sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
    arrayPollInterval: Duration = DashboardStore.defaultArrayPollInterval,
    arrayPollAttempts: Int = 30
  ) {
    self.repository = repository
    self.metrics = metrics
    self.staleAfter = staleAfter
    self.sleep = sleep
    self.arrayPollInterval = arrayPollInterval
    self.arrayPollAttempts = arrayPollAttempts
  }

  /// The polled reading with the live values on top.
  func system(for snapshot: DashboardSnapshot) -> SystemInfo? {
    snapshot.array.system?.overlaid(with: liveMetrics)
  }

  /// Applies live readings until the stream ends or the caller's task is
  /// cancelled, then clears the CPU and memory readings so the polled values
  /// show again. The CPU temperature stays; see `cpuTemperature`.
  ///
  /// **Silent on failure.** A stream error never reaches `state`: no red
  /// text, and no `.actionFailed`. The dashboard falls back to its poll, which
  /// is the same number a few seconds older.
  ///
  /// **No restart here.** The live source retries each subscription itself
  /// (`LiveMetricsRepository`), so its stream ends only when this task is
  /// cancelled. A source that ends on its own (the UI tests' failing fake)
  /// stays ended until the dashboard appears again.
  func streamLiveMetrics() async {
    streamGeneration += 1
    let generation = streamGeneration
    do {
      for try await update in metrics.liveMetrics() {
        if case .cpuTemperature(let reading) = update {
          cpuTemperature = reading
        } else {
          liveMetrics.apply(update)
          expire(update.metric)
        }
      }
    } catch {
      // Deliberately ignored; see above.
    }
    // A tab switch cancels one stream and starts the next at the same time.
    // The old stream's cleanup must not clear the new stream's readings.
    guard generation == streamGeneration else { return }
    for task in expiries.values { task.cancel() }
    expiries = [:]
    liveMetrics = LiveMetrics()
  }

  /// Clears `metric` if no newer reading arrives within its `staleAfter`.
  private func expire(_ metric: LiveMetric) {
    expiries[metric]?.cancel()
    guard let delay = staleAfter[metric] else { return }
    expiries[metric] = Task { [weak self, sleep] in
      do { try await sleep(delay) } catch { return }
      // A newer reading cancelled this expiry. A test's `sleep` may return
      // normally after a cancel, so check rather than trust the throw.
      guard !Task.isCancelled, let self else { return }
      liveMetrics.clear(metric)
      expiries[metric] = nil
    }
  }

  /// First load: `.loading` is correct, there is nothing on screen yet to
  /// preserve.
  func load() async {
    await load { [self] in try await repository.dashboard() }
  }

  /// Poll and pull-to-refresh: never passes through `.loading`, so a
  /// transient failure 30 seconds in does not blank a working dashboard. A
  /// failure keeps the last good snapshot on screen via `.actionFailed`
  /// rather than discarding it.
  ///
  /// Drops its own result if a parity or array action landed while this fetch
  /// was in flight; see `mutationSequence`.
  func refresh() async {
    guard state.value != nil else { return await load() }
    let sequenceAtRequest = mutationSequence
    await mutate {
      let snapshot = try await repository.dashboard()
      guard sequenceAtRequest == mutationSequence else {
        guard let current = state.value else {
          throw AppError.unknown("No dashboard loaded.")
        }
        return current
      }
      return snapshot
    }
  }

  /// Runs one parity action, then re-fetches the dashboard for the new state.
  /// `correct` applies to `.start` only: it writes corrections to parity
  /// rather than only counting mismatches.
  ///
  /// Goes through `mutate`, so a failure keeps the dashboard on screen and
  /// shows the server's message via `.actionFailed`.
  ///
  /// **Re-fetches instead of assuming a state.** The mutations return untyped
  /// `JSON`, and Unraid starts, pauses and stops a check asynchronously, so
  /// the re-fetch can still show the old state for a moment. The next poll
  /// corrects it.
  func perform(_ action: ParityAction, correct: Bool = false) async {
    guard !isActionInFlight else { return }
    parityActionInFlight = action

    await mutate {
      try await run(action, correct: correct)
      mutationSequence += 1
      do {
        return try await repository.dashboard()
      } catch {
        // The action worked and only the re-fetch failed. "Cancel Check
        // failed" would be false, and it invites a retry of an action that
        // already happened.
        throw AppError.unknown(
          "\(action.title) succeeded, but Tower couldn't refresh the parity status. "
            + AppError.wrapping(error).message
        )
      }
    }

    parityActionInFlight = nil
  }

  /// Starts or stops the array (issue #25), then shows the array's new state.
  ///
  /// - If the server answers with the requested state, one re-fetch.
  /// - If it answers with another state, or the request times out, Unraid is
  ///   still working: re-fetch every `arrayPollInterval` until the array
  ///   reaches the requested state, at most `arrayPollAttempts` times. The
  ///   controls stay disabled for the whole wait.
  /// - A start that sent a passphrase and leaves the array stopped says the
  ///   passphrase may be wrong. Nobody has measured how Unraid reports a wrong
  ///   one, so this does not depend on an error from the server.
  /// - A server error, such as "The array is already started", shows as it
  ///   arrives.
  ///
  /// `passphrase` goes into the request and nowhere else: not into
  /// `arrayActionInFlight`, `state`, or any error text.
  func perform(_ action: ArrayAction, passphrase: String?) async {
    guard !isActionInFlight else { return }
    arrayActionInFlight = action

    await mutate {
      let reported = try await repository.setArrayState(action, passphrase: passphrase)
      mutationSequence += 1
      guard reported == action.targetState else {
        return try await waitForArray(action, unlocking: passphrase != nil)
      }
      do {
        return try await repository.dashboard()
      } catch {
        throw AppError.unknown(
          "\(action.title) succeeded, but Tower couldn't refresh the array status. "
            + AppError.wrapping(error).message
        )
      }
    }

    arrayActionInFlight = nil
  }

  /// Re-fetches until the array reports `action.targetState`. A failed
  /// re-fetch does not end the wait: the server can be busy while the array
  /// changes state.
  ///
  /// When the wait ends first, the newest snapshot goes on screen before the
  /// error, so the error line sits over the array's real state.
  private func waitForArray(_ action: ArrayAction, unlocking: Bool) async throws -> DashboardSnapshot {
    var latest: DashboardSnapshot?
    for _ in 0..<arrayPollAttempts {
      try await sleep(arrayPollInterval)
      guard let snapshot = try? await repository.dashboard() else { continue }
      // A poll that asked before this answer must not land over it.
      mutationSequence += 1
      latest = snapshot
      if snapshot.array.state == action.targetState { return snapshot }
    }
    if let latest { state = .loaded(latest) }
    if action == .start, unlocking, latest?.array.state == "STOPPED" {
      throw AppError.unknown("The array did not start. The passphrase may be wrong.")
    }
    throw AppError.stillRunning(
      action == .start
        ? "The array has not started yet. Pull to refresh to check again."
        : "The array has not stopped yet. Pull to refresh to check again."
    )
  }

  /// A store for the Parity screen's history list, on this dashboard's
  /// repository.
  func makeParityHistoryStore() -> ParityHistoryStore {
    ParityHistoryStore(repository: repository)
  }

  private func run(_ action: ParityAction, correct: Bool) async throws {
    switch action {
    case .start: try await repository.startParityCheck(correct: correct)
    case .pause: try await repository.pauseParityCheck()
    case .resume: try await repository.resumeParityCheck()
    case .cancel: try await repository.cancelParityCheck()
    }
  }
}
