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
  func refresh() async {
    guard state.value != nil else { return await load() }
    await mutate { try await repository.dashboard() }
  }
}
