import Foundation
import Observation
import TowerCore
import TowerData

/// One `VmMutations` action a VM row or detail screen can trigger — see
/// `VMStore.perform(_:on:)`.
enum VMAction: Hashable, Sendable {
  case start, stop, forceStop, pause, resume, reboot, reset

  /// The verb as it appears on a button. Single source of the wording, so a
  /// row's swipe action, the context menu, and the detail screen can never
  /// disagree about what an action is called.
  var title: String {
    switch self {
    case .start: "Start"
    case .stop: "Stop"
    case .forceStop: "Force Stop"
    case .pause: "Pause"
    case .resume: "Resume"
    case .reboot: "Reboot"
    case .reset: "Reset"
    }
  }

  /// A stable slug for accessibility identifiers — `vmDetail.action.forceStop`.
  /// Deliberately not derived from `title`: a copy change ("Force Stop" →
  /// "Force Off") would silently repoint every UI test that names it, and the
  /// failure would look like a missing button rather than a renamed one.
  var identifier: String {
    switch self {
    case .start: "start"
    case .stop: "stop"
    case .forceStop: "forceStop"
    case .pause: "pause"
    case .resume: "resume"
    case .reboot: "reboot"
    case .reset: "reset"
    }
  }
}

@MainActor
@Observable
final class VMStore: LoadingStore {
  /// `VMInventory`, not `[VMDomain]`: `nil` domains means the VM manager isn't
  /// reporting at all, which is a different screen from "no VMs defined". See
  /// `VMInventory`'s doc comment.
  var state: Loadable<VMInventory> = .idle

  /// The one line `LoadingStore` needs per store — see `LoadTracker` for why it
  /// can't live in the protocol extension.
  let loads = LoadTracker()
  /// Bound to `VMListView`'s `.searchable(text:)`. Filtering lives here, not
  /// in the view, so it can be exercised without SwiftUI.
  var searchText: String = ""
  /// VM IDs with an action in flight. `VMRow`/`VMDetailView` read this to
  /// disable their own actions, and `perform(_:on:)` checks it first so a
  /// second tap on a busy row is ignored rather than firing a second mutation.
  var inFlight: Set<VMDomain.ID> = []
  /// Bumped once per action that resolves *successfully*, never by
  /// `load()`/`refresh()`, so `.sensoryFeedback` fires for something the user
  /// did and stays silent for a background poll. Mirrors `DockerStore`.
  private(set) var lastActionSuccess = 0
  /// The failure twin of `lastActionSuccess`.
  private(set) var lastActionFailure = 0
  /// Bumped once per action that completes successfully. `refresh()` captures
  /// this before issuing its own fetch and re-compares afterwards: a fetch
  /// that was in flight while an action completed predates that action and
  /// reflects stale server truth for whichever row it touched. Same guard as
  /// `DockerStore`, for actions that are slow and concurrent — and the window
  /// is *wider* here, because a VM shutdown takes far longer than a
  /// `docker stop`'s ~10s SIGTERM grace.
  private var mutationSequence = 0

  private let repository: any VMRepositoryProtocol

  init(repository: any VMRepositoryProtocol) {
    self.repository = repository
  }

  /// First load: `.loading` is correct, there is nothing on screen to
  /// preserve.
  func load() async {
    await load { [self] in try await repository.domains() }
  }

  /// Poll and pull-to-refresh: never passes through `.loading`, so a transient
  /// failure 30 seconds in doesn't blank a working list — a failure keeps the
  /// last good inventory on screen via `.actionFailed`.
  ///
  /// Drops its own result if an action completed while this fetch was in
  /// flight; see `mutationSequence`.
  func refresh() async {
    guard state.value != nil else { return await load() }
    let sequenceAtRequest = mutationSequence
    await mutate {
      let inventory = try await repository.domains()
      guard sequenceAtRequest == mutationSequence else {
        guard let current = state.value else {
          throw AppError.unknown("No VMs loaded.")
        }
        return current
      }
      return inventory
    }
  }

  /// Runs one `VMAction` against `domain`, going through `mutate` so a failure
  /// preserves the list on screen via `.actionFailed` rather than blanking it.
  ///
  /// **Re-fetches instead of merging a returned state.** Every `VmMutations`
  /// action returns a bare `Boolean!` (see `VMRepositoryProtocol`), so unlike
  /// `DockerStore.perform(_:on:)` there is no `ContainerStateUpdate` analogue
  /// to apply — and inventing one would be fabricating the very thing the user
  /// is watching for. libvirt transitions are asynchronous, so this re-fetch
  /// may legitimately still report the old state; the poll corrects it a
  /// moment later. That honest lag is the deliberate choice over an optimistic
  /// local state that would sometimes be wrong and always look right.
  ///
  /// A refusal (the repository throwing `AppError.actionRefused` on a `false`
  /// response) is a failure like any other here: it lands in `.actionFailed`,
  /// surfaces its message, and bumps `lastActionFailure`.
  ///
  /// Guards on `inFlight` *before* awaiting anything, so a second call for the
  /// same row while the first is still running returns immediately. The marker
  /// is removed unconditionally after `mutate` returns, which covers both
  /// outcomes — `mutate` never rethrows.
  func perform(_ action: VMAction, on domain: VMDomain) async {
    guard !inFlight.contains(domain.id) else { return }
    inFlight.insert(domain.id)

    var succeeded = false
    await mutate {
      try await run(action, id: domain.id)
      succeeded = true
      mutationSequence += 1
      // The action landed; the only honest way to learn the new state is to
      // ask.
      do {
        return try await repository.domains()
      } catch {
        // The action worked and only the re-fetch failed — two different
        // outcomes that must not be reported as one. Surfacing the bare
        // network error here would read as "Stop failed", which is a lie, and
        // a lie that invites a retry: a second `reset` on a VM that already
        // reset is a second hard reboot of a running guest. So the message
        // says what actually happened, while `succeeded` stays true so the
        // haptic still reflects the action's own outcome.
        throw AppError.unknown(
          "\(action.title) succeeded, but Tower couldn't refresh this VM's state. "
            + AppError.wrapping(error).message
        )
      }
    }

    inFlight.remove(domain.id)
    if succeeded {
      lastActionSuccess += 1
    } else {
      lastActionFailure += 1
    }
  }

  private func run(_ action: VMAction, id: String) async throws {
    switch action {
    case .start: try await repository.start(id: id)
    case .stop: try await repository.stop(id: id)
    case .forceStop: try await repository.forceStop(id: id)
    case .pause: try await repository.pause(id: id)
    case .resume: try await repository.resume(id: id)
    case .reboot: try await repository.reboot(id: id)
    case .reset: try await repository.reset(id: id)
    }
  }

  /// Whether the server declined to report VMs at all. Distinct from
  /// `filteredDomains.isEmpty`, which is also true for a server with no VMs
  /// and for a search that matched nothing — three states `VMListView` renders
  /// three different ways.
  var isUnavailable: Bool {
    state.value?.isUnavailable ?? false
  }

  /// The loaded domains narrowed by `searchText`, matching name
  /// case-insensitively. An empty (or all-whitespace) query returns
  /// everything. Empty for an unavailable inventory too — the view checks
  /// `isUnavailable` first, so this never has to encode "unavailable" as a
  /// special kind of empty.
  var filteredDomains: [VMDomain] {
    guard let domains = state.value?.domains else { return [] }
    let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !query.isEmpty else { return domains }
    return domains.filter { $0.displayName.localizedCaseInsensitiveContains(query) }
  }

  /// Whether the server reported an inventory containing no VMs — a healthy
  /// server with none defined, as opposed to one not reporting. Used by the
  /// view to pick between its two empty states.
  var isEmpty: Bool {
    state.value?.domains?.isEmpty ?? false
  }
}
