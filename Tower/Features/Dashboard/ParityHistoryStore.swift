import Foundation
import Observation
import TowerCore
import TowerData

/// The Parity screen's history list: past checks, newest first.
@MainActor
@Observable
final class ParityHistoryStore: RefreshableStore {
  var state: Loadable<[ParityCheckRecord]> = .idle

  /// The one line `LoadingStore` needs per store — see `LoadTracker` for why it
  /// can't live in the protocol extension.
  let loads = LoadTracker()

  private let repository: any SystemRepositoryProtocol

  init(repository: any SystemRepositoryProtocol) {
    self.repository = repository
  }

  func load() async {
    await load { [self] in try await repository.parityHistory() }
  }

  /// Pull-to-refresh, and the re-read after a parity action ends a check.
  /// Keeps the list on screen if it fails.
  func refresh() async {
    guard state.value != nil else { return await load() }
    await mutate { try await repository.parityHistory() }
  }
}
