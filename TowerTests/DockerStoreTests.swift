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

/// `results`/`actionResults` are each a queue rather than a single fixed
/// outcome — same reasoning as `DashboardStoreTests.StubDashboardRepository`.
/// The five mutation methods share one `actionResults` queue: these tests
/// never care which specific action ran, only the generic
/// in-flight/success/failure behavior `perform(_:on:)` provides regardless
/// of which one it dispatches to.
private final class StubDockerRepository: DockerRepositoryProtocol, @unchecked Sendable {
  enum Result { case success([Container]), failure(AppError) }
  enum ActionResult { case success(ContainerStateUpdate), failure(AppError) }

  private var results: [Result]
  private var actionResults: [ActionResult]

  init(results: [Result] = [], actionResults: [ActionResult] = []) {
    self.results = results
    self.actionResults = actionResults
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
    state: ContainerState = .running, status: String = "Up 2 hours"
  ) -> Container {
    Container(
      id: id, names: names, image: image, state: state, status: status,
      autoStart: false, isUpdateAvailable: nil, isOrphaned: false,
      webUiURL: nil, iconURL: nil, projectURL: nil, supportURL: nil, registryURL: nil,
      templatePath: nil, networkMode: nil, ports: []
    )
  }
}
