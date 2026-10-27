import Foundation
import Observation
import TowerCore
import TowerData

/// One `DockerMutations` action a container row can trigger — see
/// `DockerStore.perform(_:on:)`.
enum ContainerAction: Sendable {
  case start, stop, restart, pause, unpause
}

@MainActor
@Observable
final class DockerStore: LoadingStore {
  var state: Loadable<[Container]> = .idle

  /// The one line `LoadingStore` needs per store — see `LoadTracker` for why it
  /// can't live in the protocol extension.
  let loads = LoadTracker()
  /// Bound to `DockerListView`'s `.searchable(text:)`. Filtering lives here,
  /// not in the view, so `searchFiltersByNameCaseInsensitively` and friends
  /// can exercise it without SwiftUI.
  var searchText: String = ""
  /// Container IDs with a mutation in flight — swiped or tapped but not yet
  /// resolved. `ContainerRow` reads this to disable its own actions and show
  /// a busy indicator, and `perform(_:on:)` itself checks it first so a
  /// second tap on a busy row is ignored rather than firing a second
  /// mutation — the same race `ConnectStore.canSubmit` guards against on the
  /// connect screen.
  var inFlight: Set<Container.ID> = []
  /// Bumped once per mutation that resolves *successfully* through
  /// `perform(_:on:)` — never by `load()`/`refresh()`, which must stay
  /// silent. `DockerListView` drives `.sensoryFeedback(.success, trigger:)`
  /// off this so a background poll never buzzes the user, only an action
  /// they actually took.
  private(set) var lastActionSuccess = 0
  /// The failure twin of `lastActionSuccess`, driving
  /// `.sensoryFeedback(.error, trigger:)`.
  private(set) var lastActionFailure = 0
  /// Monotonically increasing, bumped once per mutation that *completes
  /// successfully* through `perform(_:on:)`. `refresh()` captures this
  /// counter's value before issuing its own `containers()` request and compares
  /// it again once that request resolves: if a mutation completed while the
  /// fetch was in flight, the fetch was requested before that mutation happened
  /// and reflects stale, pre-mutation server truth for whichever row it
  /// touched. See `refresh()`'s doc comment: a `docker stop`'s ~10s SIGTERM
  /// grace makes this a real window for the 30s poll, not a theoretical one.
  private var mutationSequence = 0

  private let repository: any DockerRepositoryProtocol

  init(repository: any DockerRepositoryProtocol) {
    self.repository = repository
  }

  /// First load: `.loading` is correct, there is nothing on screen yet to
  /// preserve.
  func load() async {
    await load { [self] in try await repository.containers() }
  }

  /// Poll and pull-to-refresh: never passes through `.loading`, so a
  /// transient failure 30 seconds in does not blank a working list. A
  /// failure keeps the last good container list on screen via
  /// `.actionFailed` rather than discarding it.
  ///
  /// Drops its own result if a `perform(_:on:)` mutation completed while
  /// this fetch was in flight: that fetch's request predates the mutation,
  /// so its answer is stale for whichever row the mutation touched.
  /// Writing it back wholesale would silently revert that row for up to the
  /// next poll interval. `mutationSequence` is compared, not the list contents,
  /// because a content diff can't tell "stale" apart from "genuinely
  /// unchanged."
  func refresh() async {
    guard state.value != nil else { return await load() }
    let sequenceAtRequest = mutationSequence
    await mutate {
      let containers = try await repository.containers()
      guard sequenceAtRequest == mutationSequence else {
        guard let current = state.value else {
          throw AppError.unknown("No containers loaded.")
        }
        return current
      }
      return containers
    }
  }

  /// Runs one `ContainerAction` against `container`, going through `mutate`
  /// so a failure preserves the list on screen via `.actionFailed` (see
  /// `LoadingStore.mutate`) instead of blanking it.
  ///
  /// Guards on `inFlight` *before* awaiting anything, so a second call for
  /// the same row made while the first is still in flight returns
  /// immediately without ever reaching the repository — the exact race
  /// `ConnectStore.canSubmit` guards on the connect screen. The marker is
  /// inserted synchronously here and removed unconditionally after `mutate`
  /// returns, which covers **both** the success and failure paths: `mutate`
  /// never rethrows, so by the time `await mutate { ... }` completes the
  /// action has already resolved one way or the other.
  ///
  /// Docker state transitions are asynchronous — a container that just
  /// returned `RUNNING` from `start` may still report `EXITED` on the next
  /// poll for a moment. `Container.applyingStateUpdate(_:)` takes the
  /// mutation's response as authoritative for this one row, leaving every
  /// other field (and every other row) untouched until the next successful
  /// `refresh()`/`load()` — this does not fight the poll.
  ///
  /// `state.value` is read *after* `run(action:id:)` resolves, not before —
  /// two rows can be in flight at once (the per-row `inFlight` guard above
  /// only stops a second action *on the same row*), and reading it early
  /// would snapshot the list at this call's own start and write that stale
  /// snapshot back wholesale, discarding whatever a different row's
  /// concurrently-resolving action already wrote (two Stops racing on
  /// different containers could revert one of them to Running while it was
  /// actually stopped).
  func perform(_ action: ContainerAction, on container: Container) async {
    guard !inFlight.contains(container.id) else { return }
    inFlight.insert(container.id)

    var succeeded = false
    await mutate {
      let update = try await run(action, id: container.id)
      succeeded = true
      mutationSequence += 1
      guard let containers = state.value else {
        // Unreachable in practice — a row can only trigger an action once
        // it's on screen, which means `state.value` is already non-nil —
        // but `mutate` needs *some* value to fall back on, and silently
        // discarding the mutation's result would be worse than a clear
        // error.
        throw AppError.unknown("No containers loaded.")
      }
      return containers.map { $0.id == update.id ? $0.applyingStateUpdate(update) : $0 }
    }

    inFlight.remove(container.id)
    if succeeded {
      lastActionSuccess += 1
    } else {
      lastActionFailure += 1
    }
  }

  private func run(_ action: ContainerAction, id: String) async throws -> ContainerStateUpdate {
    switch action {
    case .start: try await repository.start(id: id)
    case .stop: try await repository.stop(id: id)
    case .restart: try await repository.restart(id: id)
    case .pause: try await repository.pause(id: id)
    case .unpause: try await repository.unpause(id: id)
    }
  }

  /// `state.value` narrowed by `searchText`, matching container name or
  /// image case-insensitively. An empty (or all-whitespace) query returns
  /// every container unfiltered — this is what lets `DockerListView`
  /// distinguish "no containers on the server" (`state.value` itself empty)
  /// from "this search matched nothing" (`filteredContainers` empty but
  /// `state.value` is not) without duplicating that logic in the view.
  var filteredContainers: [Container] {
    guard let containers = state.value else { return [] }
    let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !query.isEmpty else { return containers }
    return containers.filter {
      $0.displayName.localizedCaseInsensitiveContains(query)
        || $0.image.localizedCaseInsensitiveContains(query)
    }
  }

  /// Builds a fresh `ContainerLogsStore` for `containerID`, sharing this
  /// store's own `repository` — the reason this is a factory
  /// method rather than exposing `repository` itself: `repository` stays
  /// `private`, and every caller (today, just `DockerListView`'s
  /// `navigationDestination(for: ContainerLogsRoute.self)`) gets a properly
  /// constructed store without needing to know what `DockerRepositoryProtocol`
  /// instance backs this one. Logs aren't part of `DockerStore.state` — a
  /// container's log output isn't in `[Container]` and doesn't belong in the
  /// list's own poll — so each call returns an independent store rather than
  /// something cached here.
  func makeLogsStore(containerID: Container.ID) -> ContainerLogsStore {
    ContainerLogsStore(repository: repository, containerID: containerID)
  }
}
