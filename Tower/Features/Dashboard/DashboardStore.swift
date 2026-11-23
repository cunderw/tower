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
  /// Bumped once per parity action the server accepts. `refresh()` captures it
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
  private let retryAfter: Duration
  private let sleep: @Sendable (Duration) async throws -> Void

  /// - Parameters:
  ///   - staleAfter: How long a live CPU or memory value stays on screen with
  ///     no new reading. About three times each metric's measured cadence
  ///     (CPU 1 s, memory 2 s), so one late reading does not flicker the polled
  ///     value in, and a stream that has gone quiet without closing does not
  ///     freeze an old reading on screen. The CPU temperature never expires;
  ///     see `cpuTemperature`.
  ///   - retryAfter: How long `keepStreamingLiveMetrics()` waits after a
  ///     stream ends before it starts the next one. The poll's interval, so a
  ///     dropped socket comes back by the next poll.
  ///   - sleep: Injected, as `poll` injects it, so tests use no real time.
  init(
    repository: any SystemRepositoryProtocol,
    metrics: any MetricsStreaming,
    staleAfter: [LiveMetric: Duration] = [
      .cpu: .seconds(3), .memory: .seconds(6),
    ],
    retryAfter: Duration = .towerPoll,
    sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
  ) {
    self.repository = repository
    self.metrics = metrics
    self.staleAfter = staleAfter
    self.retryAfter = retryAfter
    self.sleep = sleep
  }

  /// The polled reading with the live values on top.
  func system(for snapshot: DashboardSnapshot) -> SystemInfo? {
    snapshot.array.system?.overlaid(with: liveMetrics)
  }

  /// Runs the live stream until the caller's task is cancelled. When a
  /// stream ends or fails, the next one starts `retryAfter` later, so one
  /// dropped socket costs at most one poll interval of live values, not the
  /// rest of the visit.
  func keepStreamingLiveMetrics() async {
    while !Task.isCancelled {
      await streamLiveMetrics()
      // Cancellation ended that stream: the dashboard has gone, so stop here.
      guard !Task.isCancelled else { return }
      do { try await sleep(retryAfter) } catch { return }
    }
  }

  /// Applies live readings until the stream ends or the caller's task is
  /// cancelled, then clears the CPU and memory readings so the polled values
  /// show again. The CPU temperature stays; see `cpuTemperature`.
  ///
  /// **Silent on failure.** A stream error never reaches `state`: no red
  /// text, and no `.actionFailed`. The dashboard falls back to its poll, which
  /// is the same number a few seconds older.
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
  /// Drops its own result if a parity action landed while this fetch was in
  /// flight; see `mutationSequence`.
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
    guard parityActionInFlight == nil else { return }
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
