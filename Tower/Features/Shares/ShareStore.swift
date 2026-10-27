import Foundation
import Observation
import TowerCore
import TowerData

/// The Shares tab's store.
///
/// Deliberately the smallest store in the app: `DockerStore` minus every
/// mutation concern. `Share` has no mutations in Unraid's schema, so there is no
/// `inFlight` set, no `lastActionSuccess`/`lastActionFailure` counters, and no
/// `mutationSequence` stale-fetch guard — all three exist to protect a list from
/// its own actions, and this list has none. Carrying them "for symmetry" would
/// be dead surface.
@MainActor
@Observable
final class ShareStore: LoadingStore {
  var state: Loadable<[Share]> = .idle

  /// The one line `LoadingStore` needs per store — see `LoadTracker` for why it
  /// can't live in the protocol extension.
  let loads = LoadTracker()
  /// Bound to `ShareListView`'s `.searchable(text:)`. Filtering lives here, not
  /// in the view, so it can be exercised without SwiftUI.
  var searchText: String = ""

  private let repository: any ShareRepositoryProtocol

  init(repository: any ShareRepositoryProtocol) {
    self.repository = repository
  }

  /// First load: `.loading` is correct, there is nothing on screen to preserve.
  func load() async {
    await load { [self] in try await repository.shares() }
  }

  /// Poll and pull-to-refresh: never passes through `.loading`, so a transient
  /// failure 30 seconds in doesn't blank a working list. A failure keeps the last
  /// good list on screen via `.actionFailed` rather than discarding it.
  func refresh() async {
    guard state.value != nil else { return await load() }
    await mutate { try await repository.shares() }
  }

  /// `state.value` narrowed by `searchText`, matching the share's name or its
  /// comment case-insensitively.
  ///
  /// Comment as well as name because that is what the row shows, and because
  /// comments are the only distinguishing text some shares have — searching
  /// "paperwork" should find the share whose comment reads "scanned
  /// paperwork", not just one named `paperwork`.
  ///
  /// An empty (or all-whitespace) query returns everything, which is what lets
  /// the view tell "this server has no shares" apart from "this search matched
  /// nothing".
  var filteredShares: [Share] {
    guard let shares = state.value else { return [] }
    let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !query.isEmpty else { return shares }
    return shares.filter {
      $0.displayName.localizedCaseInsensitiveContains(query)
        || $0.comment?.localizedCaseInsensitiveContains(query) == true
    }
  }
}
