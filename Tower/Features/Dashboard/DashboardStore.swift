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

  private let repository: any SystemRepositoryProtocol

  init(repository: any SystemRepositoryProtocol) {
    self.repository = repository
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
