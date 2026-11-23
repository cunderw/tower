import Foundation
import Observation
import TowerCore
import TowerData

/// One `DockerMutations` action a container row can trigger — see
/// `DockerStore.perform(_:on:)`. `update` pulls the latest image and
/// recreates the container; `perform` hands it to `DockerStore.update(_:)`.
enum ContainerAction: Sendable {
  case start, stop, restart, pause, unpause, update
}

/// How one container update ended.
enum ContainerUpdateOutcome: Equatable, Sendable {
  case updated
  /// The client stopped waiting. The server goes on with the update.
  case stillRunning
  case failed(AppError)
}

/// Where an "Update All" run is: updating the `position`th of `total`.
struct ContainerUpdateProgress: Equatable, Sendable {
  let position: Int
  let total: Int
  let containerName: String
}

/// The result of the last update run, one entry per container in run order.
/// `DockerListView` shows `summary` at the top of the list.
struct ContainerUpdateReport: Equatable, Sendable {
  struct Entry: Equatable, Sendable {
    let containerName: String
    let outcome: ContainerUpdateOutcome
  }

  let entries: [Entry]

  var hasFailure: Bool { entries.contains(where: \.isFailure) }
  var hasStillRunning: Bool { entries.contains { $0.outcome == .stillRunning } }

  /// One line for a single container. For several, a count line, then one
  /// line per container that did not update.
  var summary: String {
    if entries.count == 1, let entry = entries.first {
      return entry.summary
    }
    let updated = entries.filter { $0.outcome == .updated }.count
    let headline = updated == entries.count
      ? "Updated \(updated) containers."
      : "Updated \(updated) of \(entries.count) containers."
    let details = entries.filter { $0.outcome != .updated }.map(\.summary)
    return ([headline] + details).joined(separator: "\n")
  }
}

extension ContainerUpdateReport.Entry {
  var isFailure: Bool {
    if case .failed = outcome { true } else { false }
  }

  /// One sentence naming the container and how its update ended.
  var summary: String {
    switch outcome {
    case .updated: "Updated \(containerName)."
    case .stillRunning: "\(containerName) is still updating on the server. Refresh in a few minutes."
    case .failed(let error): "Couldn't update \(containerName). \(error.message)"
    }
  }
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

  /// Non-nil while `updateAll()` runs.
  private(set) var updateProgress: ContainerUpdateProgress?
  /// The last update run's result, until the next run or `dismissUpdateReport()`.
  /// The list shows its summary, and the detail screen shows its container's
  /// entry. Entries are keyed by name, not ID, because an update gives the
  /// container a new ID.
  private(set) var updateReport: ContainerUpdateReport?
  /// Old container ID to the ID of the container an update recreated from it.
  /// `container(id:)` follows it, so a screen that holds the old ID keeps
  /// showing the container.
  private(set) var replacedIDs: [Container.ID: Container.ID] = [:]
  /// The names of containers with an update in flight. `isBusy(_:)` reads it
  /// as well as `inFlight`, because a poll can show the recreated container,
  /// with its new ID, before the mutation answers.
  private var updatingNames: Set<String> = []
  /// The name of every container an update started for, by its old ID. Lets
  /// `container(id:)` find the recreated container before the alias exists,
  /// or when the alias never comes because the client stopped waiting.
  private var updateNames: [Container.ID: String] = [:]

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
    if action == .update {
      return await update(container)
    }
    guard !isBusy(container) else { return }
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
    case .update: preconditionFailure("perform(_:on:) sends .update to update(_:)")
    }
  }

  // MARK: - Updates

  /// Whether an action on `container` is in flight, an update included.
  func isBusy(_ container: Container) -> Bool {
    inFlight.contains(container.id) || updatingNames.contains(container.displayName)
  }

  /// Whether an update of `container` is in flight.
  func isUpdating(_ container: Container) -> Bool {
    updatingNames.contains(container.displayName)
  }

  /// Whether `updateAll()` is running. The per-container Update controls are
  /// off while it runs, so one container is never updated twice at once.
  var isUpdatingAll: Bool { updateProgress != nil }

  /// The containers that report an update, in list order.
  var containersWithUpdates: [Container] {
    state.value?.filter { $0.isUpdateAvailable == true } ?? []
  }

  /// The container `id` names, or the one an update recreated from it.
  ///
  /// An update gives a container a new ID (Docker recreates it), so a screen
  /// that holds the old ID would otherwise show "Container Not Found" while
  /// the container is still there. Follows `replacedIDs` first. Then, for a
  /// container an update started for, matches by name: the 30 s poll can show
  /// the recreated container before the mutation answers, and after a client
  /// timeout the alias never comes. Docker container names are unique on a
  /// host, so the name match finds one container or none.
  func container(id: Container.ID) -> Container? {
    guard let containers = state.value else { return nil }
    var candidate = id
    var visited: Set<Container.ID> = []
    while visited.insert(candidate).inserted {
      if let match = containers.first(where: { $0.id == candidate }) { return match }
      guard let next = replacedIDs[candidate] else { break }
      candidate = next
    }
    guard let name = updateNames[id] else { return nil }
    return containers.first { $0.displayName == name }
  }

  /// Updates one container: pulls its latest image and recreates it. Then
  /// refreshes the list, which is what the server shows after the recreate.
  func update(_ container: Container) async {
    guard !isBusy(container), !isUpdatingAll else { return }
    updateReport = nil
    let outcome = await runUpdate(container)
    finishUpdateRun([.init(containerName: container.displayName, outcome: outcome)])
    await refresh()
  }

  /// Updates every container that reports an update, one request each, in
  /// list order. Not `updateAllContainers`: the server runs that as one
  /// request that stops at the first failure and discards the updates before
  /// it. Here one failure does not stop the rest, and each result is kept.
  func updateAll() async {
    guard !isUpdatingAll else { return }
    let targets = containersWithUpdates.filter { !isBusy($0) }
    guard !targets.isEmpty else { return }
    updateReport = nil
    var entries: [ContainerUpdateReport.Entry] = []
    for (index, target) in targets.enumerated() {
      updateProgress = ContainerUpdateProgress(
        position: index + 1, total: targets.count, containerName: target.displayName)
      // A poll can have replaced the row since the run started.
      let current = container(id: target.id) ?? target
      let outcome = await runUpdate(current)
      entries.append(.init(containerName: target.displayName, outcome: outcome))
    }
    updateProgress = nil
    finishUpdateRun(entries)
    await refresh()
  }

  func dismissUpdateReport() {
    updateReport = nil
  }

  /// One `update(id:)` call, with the in-flight markers set around it. On
  /// success, puts the recreated container in the list in place of the old
  /// one. Never throws: the outcome says how it ended.
  private func runUpdate(_ container: Container) async -> ContainerUpdateOutcome {
    let name = container.displayName
    inFlight.insert(container.id)
    updatingNames.insert(name)
    updateNames[container.id] = name
    defer {
      inFlight.remove(container.id)
      updatingNames.remove(name)
    }

    let outcome: ContainerUpdateOutcome
    do {
      let updated = try await repository.update(id: container.id)
      mutationSequence += 1
      if updated.id != container.id {
        replacedIDs[container.id] = updated.id
      }
      // Read after the await, not before, for the reason `perform(_:on:)`
      // gives. Matched by name too: a poll can already hold the recreated
      // container under its new ID.
      if let containers = state.value {
        await mutate { Self.replacing(container, with: updated, in: containers) }
      }
      outcome = .updated
    } catch {
      let appError = AppError.wrapping(error)
      if case .stillRunning = appError {
        outcome = .stillRunning
      } else {
        outcome = .failed(appError)
      }
    }
    return outcome
  }

  private func finishUpdateRun(_ entries: [ContainerUpdateReport.Entry]) {
    let report = ContainerUpdateReport(entries: entries)
    updateReport = report
    if report.hasFailure {
      lastActionFailure += 1
    } else {
      lastActionSuccess += 1
    }
  }

  /// `containers` with `old` swapped for `new`, kept sorted by display name
  /// as `LiveDockerRepository.containers()` returns them.
  private static func replacing(_ old: Container, with new: Container, in containers: [Container]) -> [Container] {
    let others = containers.filter { $0.id != old.id && $0.displayName != old.displayName }
    return (others + [new]).sorted { $0.displayName < $1.displayName }
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
