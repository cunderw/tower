import Foundation
import Testing
import TowerCore
import TowerData
@testable import Tower

@MainActor
struct DockerStoreTests {
  @Test func loadsContainers() async {
    let containers = [Container.stub(id: "1"), Container.stub(id: "2")]
    let repository = StubDockerRepository(results: [.success(containers)])
    let store = DockerStore(repository: repository)
    await store.load()
    #expect(store.state.value == containers)
  }

  @Test func surfacesFailuresAsAppError() async {
    let repository = StubDockerRepository(results: [.failure(.unauthorized)])
    let store = DockerStore(repository: repository)
    await store.load()
    #expect(store.state.error == .unauthorized)
  }

  // `refresh()` must use `mutate`, not `load`, so a transient poll failure 30
  // seconds in does not blank a working container list. A failing refresh
  // must keep the first list on screen *and* surface the new error via
  // `.actionFailed`. Mirrors `DashboardStoreTests.refreshKeepsPreviousDataOnFailure`.
  @Test func refreshKeepsPreviousDataOnFailure() async {
    let containers = [Container.stub(id: "1")]
    let repository = StubDockerRepository(results: [
      .success(containers),
      .failure(.serverUnreachable),
    ])
    let store = DockerStore(repository: repository)
    await store.load()
    await store.refresh()
    #expect(store.state.value == containers)
    #expect(store.state.error != nil)
  }

  @Test func searchFiltersByNameCaseInsensitively() async {
    let containers = [
      Container.stub(id: "1", names: ["/Code-Server"]),
      Container.stub(id: "2", names: ["/plex"]),
    ]
    let repository = StubDockerRepository(results: [.success(containers)])
    let store = DockerStore(repository: repository)
    await store.load()

    store.searchText = "code"

    #expect(store.filteredContainers.map(\.id) == ["1"])
  }

  @Test func searchFiltersByImage() async {
    let containers = [
      Container.stub(id: "1", names: ["/one"], image: "linuxserver/code-server:latest"),
      Container.stub(id: "2", names: ["/two"], image: "lscr.io/linuxserver/plex"),
    ]
    let repository = StubDockerRepository(results: [.success(containers)])
    let store = DockerStore(repository: repository)
    await store.load()

    store.searchText = "code-server"

    #expect(store.filteredContainers.map(\.id) == ["1"])
  }

  @Test func emptySearchReturnsEverything() async {
    let containers = [Container.stub(id: "1"), Container.stub(id: "2")]
    let repository = StubDockerRepository(results: [.success(containers)])
    let store = DockerStore(repository: repository)
    await store.load()

    store.searchText = ""

    #expect(store.filteredContainers == containers)
  }

  // MARK: - Mutations

  @Test func startUpdatesOnlyTheTargetContainer() async {
    let target = Container.stub(id: "1", state: .exited, status: "Exited (0) 3 hours ago")
    let other = Container.stub(id: "2", state: .exited, status: "Exited (0) 3 hours ago")
    let repository = StubDockerRepository(
      results: [.success([target, other])],
      actionResults: [.success(ContainerStateUpdate(id: "1", state: .running, status: "Up less than a second"))]
    )
    let store = DockerStore(repository: repository)
    await store.load()

    await store.perform(.start, on: target)

    let updated = store.state.value
    #expect(updated?.first { $0.id == "1" }?.state == .running)
    #expect(updated?.first { $0.id == "1" }?.status == "Up less than a second")
    // The row nobody acted on must come through byte-for-byte unchanged.
    #expect(updated?.first { $0.id == "2" } == other)
  }

  @Test func failedActionKeepsTheListAndSurfacesTheError() async {
    let containers = [Container.stub(id: "1", state: .running)]
    let repository = StubDockerRepository(
      results: [.success(containers)],
      actionResults: [.failure(.serverUnreachable)]
    )
    let store = DockerStore(repository: repository)
    await store.load()

    await store.perform(.stop, on: containers[0])

    // `.actionFailed` — the list stays on screen *and* the error surfaces.
    #expect(store.state.value == containers)
    #expect(store.state.error == .serverUnreachable)
  }

  @Test func actionMarksOnlyThatRowInFlight() async {
    let containerA = Container.stub(id: "1")
    let containerB = Container.stub(id: "2")
    let repository = GatedDockerRepository(actionResult: .success(state: .exited, status: "Exited (0) 0 seconds ago"))
    let store = DockerStore(repository: repository)
    store.state = .loaded([containerA, containerB])

    let task = Task { await store.perform(.stop, on: containerA) }
    await repository.gate.waitUntilEntered(atLeast: 1)

    #expect(store.inFlight == ["1"])

    await repository.gate.releaseAll()
    await task.value
  }

  @Test func inFlightClearsOnSuccessAndOnFailure() async {
    let container = Container.stub(id: "1")
    let repository = StubDockerRepository(
      results: [.success([container])],
      actionResults: [
        .success(ContainerStateUpdate(id: "1", state: .exited, status: "Exited (0) 0 seconds ago")),
        .failure(.serverUnreachable),
      ]
    )
    let store = DockerStore(repository: repository)
    await store.load()

    await store.perform(.stop, on: container)
    #expect(store.inFlight.isEmpty)

    await store.perform(.start, on: container)
    #expect(store.inFlight.isEmpty)
    #expect(store.state.error == .serverUnreachable)
  }

  @Test func aSecondActionOnABusyRowIsIgnored() async {
    let container = Container.stub(id: "1")
    let repository = GatedDockerRepository(actionResult: .success(state: .exited, status: "Exited (0) 0 seconds ago"))
    let store = DockerStore(repository: repository)
    store.state = .loaded([container])

    let first = Task { await store.perform(.stop, on: container) }
    await repository.gate.waitUntilEntered(atLeast: 1)

    // Fired while the first mutation is still parked on the gate — must
    // return immediately without ever reaching the repository a second time.
    await store.perform(.stop, on: container)
    #expect(repository.callCount == 1)

    await repository.gate.releaseAll()
    await first.value
  }

  // MARK: - Concurrency: stale-snapshot write-back

  /// `perform(_:on:)` must not snapshot `state.value` at the *start* of its
  /// own mutation and write that snapshot back wholesale, because that discards
  /// anything else that wrote `state` during its own `await`. The scenario: tap
  /// Stop on plex, then Stop on sonarr while the first is still in flight.
  /// If both snapshot the same pre-action list, plex resolving first writes
  /// correctly, but sonarr resolving *second* writes back *its own* stale
  /// snapshot (captured before plex resolved) and reverts plex to Running even
  /// though it is genuinely stopped.
  @Test func concurrentActionsOnDifferentRowsDoNotClobberEachOther() async {
    let plex = Container.stub(id: "1", names: ["/plex"], state: .running)
    let sonarr = Container.stub(id: "2", names: ["/sonarr"], state: .running)
    let repository = GatedDockerRepository(actionResult: .success(state: .exited, status: "Exited (0) 0 seconds ago"))
    let store = DockerStore(repository: repository)
    store.state = .loaded([plex, sonarr])

    let plexTask = Task { await store.perform(.stop, on: plex) }
    await repository.gate.waitUntilEntered(atLeast: 1)
    let sonarrTask = Task { await store.perform(.stop, on: sonarr) }
    await repository.gate.waitUntilEntered(atLeast: 2)

    // plex resolves first and fully completes…
    await repository.gate.release(0)
    await plexTask.value
    // …*then* sonarr resolves. A correct implementation merges onto
    // whatever is current at that moment (which already has plex exited),
    // not onto the snapshot sonarr saw when it started.
    await repository.gate.release(1)
    await sonarrTask.value

    let containers = store.state.value
    #expect(
      containers?.first { $0.id == "1" }?.state == .exited,
      "plex must stay Exited — sonarr resolving later must not revert a different row"
    )
    #expect(containers?.first { $0.id == "2" }?.state == .exited)
  }

  /// An in-flight `refresh()` whose request predates a mutation, but whose
  /// response lands *after* that mutation completes, carries pre-mutation
  /// server truth. Writing it back wholesale reverts the row the mutation just
  /// changed. `GatedDockerRepository` gates `containers()` too, so this can
  /// force that exact interleaving:
  /// the poll's request goes out, then Stop is tapped and fully resolves,
  /// then (only after that) the stale poll response arrives.
  @Test func refreshWhoseRequestPredatesAMutationDoesNotRevertItsResult() async {
    let plex = Container.stub(id: "1", names: ["/plex"], state: .running)
    let repository = GatedDockerRepository(actionResult: .success(state: .exited, status: "Exited (0) 0 seconds ago"))
    // What the stale poll "sees" — server truth as of before the stop.
    repository.containersResult = [plex]
    let store = DockerStore(repository: repository)
    store.state = .loaded([plex])

    let refreshTask = Task { await store.refresh() }
    await repository.gate.waitUntilEntered(atLeast: 1)

    let stopTask = Task { await store.perform(.stop, on: plex) }
    await repository.gate.waitUntilEntered(atLeast: 2)

    // The stop resolves completely first…
    await repository.gate.release(1)
    await stopTask.value
    #expect(store.state.value?.first?.state == .exited, "stop should already be reflected before the stale poll resolves")

    // …*then* the poll's stale (pre-stop) response lands.
    await repository.gate.release(0)
    await refreshTask.value

    #expect(
      store.state.value?.first?.state == .exited,
      "a refresh requested before the mutation completed must not revert it"
    )
  }
}

/// Issue #23: updating a container recreates it under a new ID.
@MainActor
struct DockerStoreUpdateTests {
  private let old = Container.stub(id: "old", names: ["/webtop"], isUpdateAvailable: true)
  private let recreated = Container.stub(id: "new", names: ["/webtop"], isUpdateAvailable: false)

  @Test func updateSwapsInTheRecreatedContainerAndRefreshes() async {
    let repository = StubDockerRepository(
      results: [.success([old]), .success([recreated])],
      updateResults: [.success(recreated)]
    )
    let store = DockerStore(repository: repository)
    await store.load()

    await store.update(old)

    #expect(store.state.value == [recreated])
    #expect(repository.remainingResults == 0, "the list must refresh after the update")
    #expect(store.replacedIDs == ["old": "new"])
    #expect(store.updateReport?.summary == "Updated webtop.")
    #expect(store.lastActionSuccess == 1)
    #expect(!store.isBusy(recreated))
  }

  @Test func aScreenHoldingTheOldIDStillFindsTheContainer() async {
    let repository = StubDockerRepository(
      results: [.success([old]), .success([recreated])],
      updateResults: [.success(recreated)]
    )
    let store = DockerStore(repository: repository)
    await store.load()

    await store.update(old)

    #expect(store.container(id: "old") == recreated)
    #expect(store.container(id: "new") == recreated)
    #expect(store.container(id: "elsewhere") == nil)
  }

  @Test func aFailedUpdateKeepsTheListAndReportsTheServerMessage() async {
    let repository = StubDockerRepository(
      results: [.success([old]), .success([old])],
      updateResults: [.failure(.graphQL(["Error pulling image: manifest unknown"]))]
    )
    let store = DockerStore(repository: repository)
    await store.load()

    await store.update(old)

    #expect(store.state.value == [old])
    #expect(store.updateReport?.summary == "Couldn't update webtop. Error pulling image: manifest unknown")
    #expect(store.updateReport?.hasFailure == true)
    #expect(store.lastActionFailure == 1)
    #expect(store.replacedIDs.isEmpty)
  }

  @Test func aTimedOutUpdateReadsAsStillRunningNotAsAFailure() async {
    let repository = StubDockerRepository(
      results: [.success([old]), .success([old])],
      updateResults: [.failure(.stillRunning("The update is still running on the server."))]
    )
    let store = DockerStore(repository: repository)
    await store.load()

    await store.update(old)

    #expect(store.updateReport?.summary == "webtop is still updating on the server. Refresh in a few minutes.")
    #expect(store.updateReport?.hasFailure == false)
    #expect(store.lastActionFailure == 0)
  }

  /// A pull takes minutes, so the 30 s poll can show the recreated container,
  /// under its new ID, before the mutation answers. The detail screen still
  /// holds the old ID and must not read "Container Not Found".
  @Test func aPollThatShowsTheRecreatedContainerFirstDoesNotLoseIt() async {
    let repository = GatedUpdateRepository()
    repository.recreated = ["old": recreated]
    let store = DockerStore(repository: repository)
    store.state = .loaded([old])

    let updateTask = Task { await store.update(old) }
    await repository.updateGate.waitUntilEntered(atLeast: 1)

    repository.containersResult = [recreated]
    await store.refresh()
    #expect(store.state.value == [recreated])
    #expect(store.container(id: "old") == recreated, "the poll beat the mutation; the old ID must still resolve")
    #expect(store.isBusy(recreated), "the recreated row is still mid-update")

    await repository.updateGate.releaseAll()
    await updateTask.value
    #expect(store.state.value == [recreated], "one webtop, not two")
    #expect(store.container(id: "old") == recreated)
  }

  @Test func aSecondUpdateOfABusyContainerIsIgnored() async {
    let repository = GatedUpdateRepository()
    repository.recreated = ["old": recreated]
    repository.containersResult = [recreated]
    let store = DockerStore(repository: repository)
    store.state = .loaded([old])

    let first = Task { await store.update(old) }
    await repository.updateGate.waitUntilEntered(atLeast: 1)
    await store.update(old)
    await store.perform(.restart, on: old)
    await repository.updateGate.releaseAll()
    await first.value

    #expect(repository.updateCalls == ["old"])
  }

  /// One request per container, in list order, with "N of M" progress, and a
  /// failure does not stop the rest — the opposite of `updateAllContainers`.
  @Test func updateAllShowsProgressAndCarriesOnPastAFailure() async {
    let code = Container.stub(id: "c", names: ["/code-server"], isUpdateAvailable: true)
    let emby = Container.stub(id: "e", names: ["/emby"], isUpdateAvailable: true)
    let plex = Container.stub(id: "p", names: ["/plex"], isUpdateAvailable: nil)
    let webtop = Container.stub(id: "w", names: ["/webtop"], isUpdateAvailable: true)
    let repository = GatedUpdateRepository()
    repository.recreated = [
      "c": Container.stub(id: "c2", names: ["/code-server"], isUpdateAvailable: false),
      "w": Container.stub(id: "w2", names: ["/webtop"], isUpdateAvailable: false),
    ]
    repository.failures = ["e": .graphQL(["Error pulling image: manifest unknown"])]
    let store = DockerStore(repository: repository)
    store.state = .loaded([code, emby, plex, webtop])
    repository.containersResult = [repository.recreated["c"]!, emby, plex, repository.recreated["w"]!]

    let run = Task { await store.updateAll() }
    await repository.updateGate.waitUntilEntered(atLeast: 1)
    #expect(store.updateProgress == ContainerUpdateProgress(position: 1, total: 3, containerName: "code-server"))
    #expect(store.isUpdatingAll)
    await repository.updateGate.release(0)
    await repository.updateGate.waitUntilEntered(atLeast: 2)
    #expect(store.updateProgress == ContainerUpdateProgress(position: 2, total: 3, containerName: "emby"))
    await repository.updateGate.release(1)
    await repository.updateGate.waitUntilEntered(atLeast: 3)
    #expect(store.updateProgress == ContainerUpdateProgress(position: 3, total: 3, containerName: "webtop"))
    await repository.updateGate.release(2)
    await run.value

    #expect(repository.updateCalls == ["c", "e", "w"], "plex has no update and is not touched")
    #expect(store.updateProgress == nil)
    #expect(!store.isUpdatingAll)
    #expect(
      store.updateReport?.summary
        == "Updated 2 of 3 containers.\nCouldn't update emby. Error pulling image: manifest unknown"
    )
    #expect(store.state.value?.map(\.id) == ["c2", "e", "p", "w2"])
    #expect(store.lastActionFailure == 1)
  }

  @Test func reportSummaryWhenEveryUpdateSucceeds() {
    let report = ContainerUpdateReport(entries: [
      .init(containerName: "plex", outcome: .updated),
      .init(containerName: "webtop", outcome: .updated),
    ])
    #expect(report.summary == "Updated 2 containers.")
  }

  @Test func reportSummaryNamesAnUpdateStillRunning() {
    let report = ContainerUpdateReport(entries: [
      .init(containerName: "plex", outcome: .stillRunning),
      .init(containerName: "webtop", outcome: .updated),
    ])
    #expect(report.summary == "Updated 1 of 2 containers.\nplex is still updating on the server. Refresh in a few minutes.")
  }

  @Test func dismissClearsTheReport() async {
    let repository = StubDockerRepository(
      results: [.success([old]), .success([recreated])],
      updateResults: [.success(recreated)]
    )
    let store = DockerStore(repository: repository)
    await store.load()
    await store.update(old)

    store.dismissUpdateReport()

    #expect(store.updateReport == nil)
  }
}

/// `update(id:)` parks on `updateGate`; `containers()` answers
/// `containersResult` at once. `recreated` is what each update returns, by
/// the ID it was asked for, and `failures` is what it throws instead.
private final class GatedUpdateRepository: DockerRepositoryProtocol, @unchecked Sendable {
  let updateGate = Gate()
  var containersResult: [Container] = []
  var recreated: [Container.ID: Container] = [:]
  var failures: [Container.ID: AppError] = [:]
  private let lock = NSLock()
  private var _updateCalls: [Container.ID] = []
  var updateCalls: [Container.ID] { lock.withLock { _updateCalls } }

  func containers() async throws -> [Container] { containersResult }

  func update(id: String) async throws -> Container {
    lock.withLock { _updateCalls.append(id) }
    await updateGate.enter()
    if let failure = failures[id] { throw failure }
    guard let container = recreated[id] else { preconditionFailure("no recreated container for \(id)") }
    return container
  }

  func start(id: String) async throws -> ContainerStateUpdate { preconditionFailure("not used") }
  func stop(id: String) async throws -> ContainerStateUpdate { preconditionFailure("not used") }
  func restart(id: String) async throws -> ContainerStateUpdate { preconditionFailure("not used") }
  func pause(id: String) async throws -> ContainerStateUpdate { preconditionFailure("not used") }
  func unpause(id: String) async throws -> ContainerStateUpdate { preconditionFailure("not used") }
  func logs(id: String, tail: Int?, since: String?) async throws -> ContainerLogs {
    preconditionFailure("not used")
  }
}

/// `results`/`actionResults` are each a queue rather than a single fixed
/// outcome — same reasoning as `DashboardStoreTests.StubDashboardRepository`.
/// The five mutation methods share one `actionResults` queue: these tests
/// never care which specific action ran, only the generic
/// in-flight/success/failure behavior `perform(_:on:)` provides regardless
/// of which one it dispatches to.
private final class StubDockerRepository: DockerRepositoryProtocol, @unchecked Sendable {
  enum Result { case success([Container]), failure(AppError) }
  enum ActionResult { case success(ContainerStateUpdate), failure(AppError) }

  enum UpdateResult { case success(Container), failure(AppError) }

  private var results: [Result]
  private var actionResults: [ActionResult]
  private var updateResults: [UpdateResult]
  /// `containers()` results not yet used — 0 once every stubbed one was asked for.
  var remainingResults: Int { results.count }

  init(results: [Result] = [], actionResults: [ActionResult] = [], updateResults: [UpdateResult] = []) {
    self.results = results
    self.actionResults = actionResults
    self.updateResults = updateResults
  }

  func containers() async throws -> [Container] {
    precondition(!results.isEmpty, "containers() called more times than results were stubbed")
    switch results.removeFirst() {
    case .success(let containers): return containers
    case .failure(let error): throw error
    }
  }

  func start(id: String) async throws -> ContainerStateUpdate { try nextActionResult() }
  func stop(id: String) async throws -> ContainerStateUpdate { try nextActionResult() }
  func restart(id: String) async throws -> ContainerStateUpdate { try nextActionResult() }
  func pause(id: String) async throws -> ContainerStateUpdate { try nextActionResult() }
  func unpause(id: String) async throws -> ContainerStateUpdate { try nextActionResult() }

  func update(id: String) async throws -> Container {
    precondition(!updateResults.isEmpty, "update(id:) called more times than results were stubbed")
    switch updateResults.removeFirst() {
    case .success(let container): return container
    case .failure(let error): throw error
    }
  }

  /// Nothing in `DockerStoreTests` exercises logs — that's
  /// `ContainerLogsStoreTests`' job — so this exists only to keep this stub
  /// conforming to `DockerRepositoryProtocol`.
  func logs(id: String, tail: Int?, since: String?) async throws -> ContainerLogs {
    preconditionFailure("logs(id:tail:since:) not stubbed for DockerStoreTests")
  }

  private func nextActionResult() throws -> ContainerStateUpdate {
    precondition(!actionResults.isEmpty, "action called more times than results were stubbed")
    switch actionResults.removeFirst() {
    case .success(let update): return update
    case .failure(let error): throw error
    }
  }
}

/// Lets the in-flight and concurrency tests observe `DockerStore` state
/// *while* a mutation (or a refresh) is still unresolved: every method —
/// `containers()` included — suspends on `gate` until the test releases it,
/// either by index (`release(_:)`, for tests that need precise ordering
/// between two overlapping calls) or all at once (`releaseAll()`, for tests
/// that only need "let it through"). `Gate.waitUntilEntered(atLeast:)` lets
/// the test know a call has actually parked there — not just been
/// scheduled — before it asserts anything or releases another index, so
/// this is deterministic rather than timing-dependent.
private final class GatedDockerRepository: DockerRepositoryProtocol, @unchecked Sendable {
  enum ActionResult { case success(state: ContainerState, status: String), failure(AppError) }

  let gate = Gate()
  let actionResult: ActionResult
  /// What `containers()` returns once its own gated call is released —
  /// mutable so a test can seed it with stale, pre-mutation data.
  var containersResult: [Container] = []
  private let lock = NSLock()
  private var _callCount = 0
  var callCount: Int { lock.withLock { _callCount } }

  init(actionResult: ActionResult) { self.actionResult = actionResult }

  func containers() async throws -> [Container] {
    _ = await gate.enter()
    return containersResult
  }

  func start(id: String) async throws -> ContainerStateUpdate { try await act(id: id) }
  func stop(id: String) async throws -> ContainerStateUpdate { try await act(id: id) }
  func restart(id: String) async throws -> ContainerStateUpdate { try await act(id: id) }
  func pause(id: String) async throws -> ContainerStateUpdate { try await act(id: id) }
  func unpause(id: String) async throws -> ContainerStateUpdate { try await act(id: id) }
  func update(id: String) async throws -> Container {
    preconditionFailure("update(id:) goes through GatedUpdateRepository")
  }

  /// Nothing in `DockerStoreTests` exercises logs through `GatedDockerRepository`
  /// — see `StubDockerRepository`'s identical stub above.
  func logs(id: String, tail: Int?, since: String?) async throws -> ContainerLogs {
    preconditionFailure("logs(id:tail:since:) not stubbed for DockerStoreTests")
  }

  private func act(id: String) async throws -> ContainerStateUpdate {
    lock.withLock { _callCount += 1 }
    _ = await gate.enter()
    switch actionResult {
    case .success(let state, let status): return ContainerStateUpdate(id: id, state: state, status: status)
    case .failure(let error): throw error
    }
  }
}

extension Container {
  /// A local fixture, not `TowerCoreTests`' `Container.stub` — that one lives
  /// in `TowerKit`'s own test target and isn't visible from `TowerTests`.
  fileprivate static func stub(
    id: String, names: [String] = ["/container"], image: String = "image:latest",
    state: ContainerState = .running, status: String = "Up 2 hours",
    isUpdateAvailable: Bool? = nil
  ) -> Container {
    Container(
      id: id, names: names, image: image, state: state, status: status,
      autoStart: false, isUpdateAvailable: isUpdateAvailable, isOrphaned: false,
      webUiURL: nil, iconURL: nil, projectURL: nil, supportURL: nil, registryURL: nil,
      templatePath: nil, networkMode: nil, ports: []
    )
  }
}
