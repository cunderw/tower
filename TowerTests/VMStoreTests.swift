import Foundation
import Testing
import TowerCore
import TowerData
@testable import Tower

@MainActor
struct VMStoreTests {
  @Test func loadsDomains() async {
    let domains = [VMDomain.stub(id: "1"), VMDomain.stub(id: "2")]
    let store = VMStore(repository: StubVMRepository(results: [.success(domains)]))
    await store.load()
    #expect(store.state.value?.domains == domains)
  }

  @Test func surfacesFailuresAsAppError() async {
    let store = VMStore(repository: StubVMRepository(results: [.failure(.unauthorized)]))
    await store.load()
    #expect(store.state.error == .unauthorized)
  }

  // MARK: - Unavailable vs. empty

  @Test func nilDomainsReportUnavailableAndNotEmpty() async {
    // The distinction the whole `VMInventory` type exists for: the server
    // returned `null` for `vms.domains`, meaning VM reporting is unavailable.
    // `VMListView` must render "VMs Unavailable", never "No VMs".
    let store = VMStore(repository: StubVMRepository(results: [.unavailable]))
    await store.load()

    #expect(store.isUnavailable)
    #expect(!store.isEmpty)
    #expect(store.filteredDomains.isEmpty)
  }

  @Test func emptyDomainsReportEmptyAndNotUnavailable() async {
    // A healthy server with no VMs defined. Same *visually empty* list, a
    // different sentence — and it must not claim the VM manager is broken.
    let store = VMStore(repository: StubVMRepository(results: [.success([])]))
    await store.load()

    #expect(!store.isUnavailable)
    #expect(store.isEmpty)
    #expect(store.filteredDomains.isEmpty)
  }

  @Test func neitherFlagIsSetBeforeTheFirstLoad() async {
    // `.idle` must not claim either state. A store that reported `isEmpty` in
    // `.idle` would flash "No VMs" before the first response arrived.
    let store = VMStore(repository: StubVMRepository(results: []))
    #expect(!store.isUnavailable)
    #expect(!store.isEmpty)
  }

  @Test func aSearchThatMatchesNothingIsNotTheSameAsAnEmptyServer() async {
    // Three-way distinction, from the store's side: this inventory has VMs, so
    // `isEmpty` is false even though `filteredDomains` is empty. That is what
    // lets the view show "no results" instead of "this server has no VMs".
    let store = VMStore(repository: StubVMRepository(results: [.success([.stub(id: "1", name: "Windows XP")])]))
    await store.load()

    store.searchText = "ubuntu"

    #expect(!store.isEmpty)
    #expect(!store.isUnavailable)
    #expect(store.filteredDomains.isEmpty)
  }

  // MARK: - Search

  @Test func searchFiltersByNameCaseInsensitively() async {
    let domains = [
      VMDomain.stub(id: "1", name: "Media Server"),
      VMDomain.stub(id: "2", name: "Windows XP"),
    ]
    let store = VMStore(repository: StubVMRepository(results: [.success(domains)]))
    await store.load()

    store.searchText = "media"

    #expect(store.filteredDomains.map(\.id) == ["1"])
  }

  @Test func searchMatchesTheFallbackNameOfAnUnnamedVM() async {
    // `name` is nullable, and `displayName` falls back to the UUID half of the
    // id. Searching has to see what the row actually shows, or an unnamed VM
    // becomes unfindable.
    let domains = [
      VMDomain(id: "hash:00000000-0000-4000-8000-000000000001", name: nil, state: .shutoff),
      VMDomain.stub(id: "2", name: "Windows XP"),
    ]
    let store = VMStore(repository: StubVMRepository(results: [.success(domains)]))
    await store.load()

    store.searchText = "000000000001"

    #expect(store.filteredDomains.map(\.id) == ["hash:00000000-0000-4000-8000-000000000001"])
  }

  @Test func emptySearchReturnsEverything() async {
    let domains = [VMDomain.stub(id: "1"), VMDomain.stub(id: "2")]
    let store = VMStore(repository: StubVMRepository(results: [.success(domains)]))
    await store.load()

    store.searchText = "   "

    #expect(store.filteredDomains == domains)
  }

  // MARK: - Refresh

  @Test func refreshKeepsPreviousDataOnFailure() async {
    // `refresh()` uses `mutate`, not `load`, so a transient poll failure 30
    // seconds in doesn't blank a working list.
    let domains = [VMDomain.stub(id: "1")]
    let store = VMStore(repository: StubVMRepository(results: [
      .success(domains),
      .failure(.serverUnreachable),
    ]))
    await store.load()
    await store.refresh()

    #expect(store.state.value?.domains == domains)
    #expect(store.state.error != nil)
  }

  @Test func refreshBeforeAnyLoadPerformsTheInitialLoad() async {
    // A poll can fire before the first load resolves (a tab selected while
    // `.idle`). Falling through to `mutate` there would leave `.actionFailed`
    // with no data to preserve.
    let domains = [VMDomain.stub(id: "1")]
    let store = VMStore(repository: StubVMRepository(results: [.success(domains)]))

    await store.refresh()

    #expect(store.state.value?.domains == domains)
  }

  // MARK: - Actions

  @Test func aSuccessfulActionRefetchesRatherThanFabricatingAState() async {
    // The structural difference from Docker: `VmMutations` actions return a
    // bare `Boolean!`, so the only honest way to learn the new state is to ask
    // again. The stub's *second* `domains()` response is what must land — if
    // the store fabricated `.running` locally, the second response's
    // `.crashed` (deliberately not the state a Start would produce) would
    // never appear.
    let stopped = VMDomain.stub(id: "1", state: .shutoff)
    let repository = StubVMRepository(
      results: [.success([stopped]), .success([VMDomain.stub(id: "1", state: .crashed)])],
      actionResults: [.success]
    )
    let store = VMStore(repository: repository)
    await store.load()

    await store.perform(.start, on: stopped)

    #expect(store.state.value?.domains?.first?.state == .crashed)
    #expect(store.lastActionSuccess == 1)
    #expect(store.lastActionFailure == 0)
  }

  @Test func aRefusedActionKeepsTheListAndSurfacesTheRefusal() async {
    // `AppError.actionRefused` is what the repository throws for a `false`
    // response. It has to reach the user as a message with the list intact —
    // the case exists precisely so a refusal isn't silent.
    let running = VMDomain.stub(id: "1", state: .running)
    let repository = StubVMRepository(
      results: [.success([running])],
      actionResults: [.failure(.actionRefused("Unraid didn't stop this VM."))]
    )
    let store = VMStore(repository: repository)
    await store.load()

    await store.perform(.stop, on: running)

    #expect(store.state.value?.domains == [running], "the list must survive a refusal")
    #expect(store.state.error == .actionRefused("Unraid didn't stop this VM."))
    #expect(store.lastActionFailure == 1)
    #expect(store.lastActionSuccess == 0)
  }

  @Test func aFailedRefetchAfterASuccessfulActionSaysSoRatherThanBlamingTheAction() async {
    // Two different outcomes that must not be reported as one: the Stop landed,
    // and then the re-fetch couldn't reach the server. Surfacing the bare
    // "Couldn't reach the server." would read as "Stop failed" — a lie, and one
    // that invites a retry. A retried `reset` on a VM that already reset is a
    // second hard reboot of a running guest, which is why this distinction is
    // worth carrying in the message rather than collapsing.
    let running = VMDomain.stub(id: "1", state: .running)
    let repository = StubVMRepository(
      results: [.success([running]), .failure(.serverUnreachable)],
      actionResults: [.success]
    )
    let store = VMStore(repository: repository)
    await store.load()

    await store.perform(.stop, on: running)

    #expect(store.state.value?.domains == [running], "the last good list stays on screen")
    let message = store.state.error?.message ?? ""
    #expect(message.contains("Stop succeeded"), "the message must not claim the action failed")
    #expect(message.contains("couldn't refresh"))
    #expect(message.contains(AppError.serverUnreachable.message), "the underlying cause is still reported")
    // The haptic follows the action's own outcome, which was success.
    #expect(store.lastActionSuccess == 1)
    #expect(store.lastActionFailure == 0)
  }

  @Test func actionMarksOnlyThatRowInFlight() async {
    let target = VMDomain.stub(id: "1", state: .shutoff)
    let other = VMDomain.stub(id: "2", state: .shutoff)
    let repository = GatedVMRepository(actionResult: .success)
    repository.domainsResults = [.success([target, other])]
    let store = VMStore(repository: repository)
    store.state = .loaded(VMInventory(domains: [target, other]))

    let task = Task { await store.perform(.start, on: target) }
    await repository.gate.waitUntilEntered(atLeast: 1)

    #expect(store.inFlight == ["1"])

    await repository.gate.releaseAll()
    await task.value

    #expect(store.inFlight.isEmpty)
  }

  @Test func inFlightClearsOnRefusalToo() async {
    // A row left permanently disabled after a refused action would be
    // unusable — and a refusal is the most likely failure of all.
    let target = VMDomain.stub(id: "1", state: .running)
    let repository = StubVMRepository(
      results: [.success([target])],
      actionResults: [.failure(.actionRefused("Unraid didn't stop this VM."))]
    )
    let store = VMStore(repository: repository)
    await store.load()

    await store.perform(.stop, on: target)

    #expect(store.inFlight.isEmpty)
  }

  @Test func aSecondActionOnABusyRowIsIgnored() async {
    // Guarded before any `await`, so the second call never reaches the
    // repository — the same race `ConnectStore.canSubmit` guards on connect.
    let target = VMDomain.stub(id: "1", state: .shutoff)
    let repository = GatedVMRepository(actionResult: .success)
    repository.domainsResults = [.success([target])]
    let store = VMStore(repository: repository)
    store.state = .loaded(VMInventory(domains: [target]))

    let first = Task { await store.perform(.start, on: target) }
    await repository.gate.waitUntilEntered(atLeast: 1)

    await store.perform(.reboot, on: target)
    #expect(repository.actionCallCount == 1, "the second action must not reach the repository")

    await repository.gate.releaseAll()
    await first.value

    #expect(repository.actionCallCount == 1)
  }

  @Test func refreshWhoseRequestPredatesAnActionDoesNotRevertItsResult() async {
    // The stale-poll guard. The window is wider for VMs than for Docker: a
    // guest shutdown can take far longer than a `docker stop`'s ~10s SIGTERM
    // grace, so a poll issued before the action can easily still be in flight
    // when it completes. Writing that response back wholesale would silently
    // revert the row the user just acted on.
    //
    // The two `domains()` responses differ deliberately, and each call claims
    // its own when it is *made* (see `GatedVMRepository.domainsResults`): the
    // poll asks first and so gets pre-action truth (`.running`), the
    // post-action re-fetch gets `.shutoff`. Without the guard the poll's late
    // answer overwrites the action's and this test reads `.running`.
    let running = VMDomain.stub(id: "1", state: .running)
    let repository = GatedVMRepository(actionResult: .success)
    repository.domainsResults = [
      .success([running]),
      .success([VMDomain.stub(id: "1", state: .shutoff)]),
    ]
    let store = VMStore(repository: repository)
    store.state = .loaded(VMInventory(domains: [running]))

    let refreshTask = Task { await store.refresh() }
    await repository.gate.waitUntilEntered(atLeast: 1)

    let stopTask = Task { await store.perform(.stop, on: running) }
    await repository.gate.waitUntilEntered(atLeast: 2)

    // Let the action through (index 1) and the re-fetch it triggers (index 2 —
    // released before it arrives, which `Gate.release(_:)` supports), so the
    // stop resolves completely first.
    await repository.gate.release(1)
    await repository.gate.release(2)
    await stopTask.value
    #expect(
      store.state.value?.domains?.first?.state == .shutoff,
      "the action's own re-fetch should already be reflected before the stale poll resolves"
    )

    // …then the poll's stale, pre-action response lands.
    await repository.gate.release(0)
    await refreshTask.value

    #expect(
      store.state.value?.domains?.first?.state == .shutoff,
      "a refresh requested before the action completed must not revert it"
    )
    #expect(store.state.error == nil, "a discarded stale refresh must not surface as a failure")
  }
}

/// `results`/`actionResults` are each a queue rather than a single fixed
/// outcome — same reasoning as `DockerStoreTests.StubDockerRepository`. All
/// seven action methods share one `actionResults` queue: these tests never care
/// which action ran, only the generic in-flight/success/refusal behaviour
/// `perform(_:on:)` provides regardless of which one it dispatches to.
///
/// `.unavailable` is its own case rather than `.success(nil)`: the nil-versus-
/// empty distinction is the thing under test, and a call site reading
/// `.success(nil)` would be one keystroke from meaning the opposite.
private final class StubVMRepository: VMRepositoryProtocol, @unchecked Sendable {
  enum Result { case success([VMDomain]), unavailable, failure(AppError) }
  enum ActionResult { case success, failure(AppError) }

  private var results: [Result]
  private var actionResults: [ActionResult]

  init(results: [Result] = [], actionResults: [ActionResult] = []) {
    self.results = results
    self.actionResults = actionResults
  }

  func domains() async throws -> VMInventory {
    precondition(!results.isEmpty, "domains() called more times than results were stubbed")
    switch results.removeFirst() {
    case .success(let domains): return VMInventory(domains: domains)
    case .unavailable: return VMInventory(domains: nil)
    case .failure(let error): throw error
    }
  }

  func start(id: String) async throws { try nextActionResult() }
  func stop(id: String) async throws { try nextActionResult() }
  func forceStop(id: String) async throws { try nextActionResult() }
  func pause(id: String) async throws { try nextActionResult() }
  func resume(id: String) async throws { try nextActionResult() }
  func reboot(id: String) async throws { try nextActionResult() }
  func reset(id: String) async throws { try nextActionResult() }

  private func nextActionResult() throws {
    precondition(!actionResults.isEmpty, "action called more times than results were stubbed")
    switch actionResults.removeFirst() {
    case .success: return
    case .failure(let error): throw error
    }
  }
}

/// Lets the in-flight and concurrency tests observe `VMStore` state *while* an
/// action (or a refresh) is still unresolved: every method — `domains()`
/// included — suspends on `gate` until the test releases it, by index or all at
/// once. See `Gate` for why that is deterministic rather than timing-dependent.
private final class GatedVMRepository: VMRepositoryProtocol, @unchecked Sendable {
  enum ActionResult { case success, failure(AppError) }
  enum StubResult { case success([VMDomain]), unavailable, failure(AppError) }

  let gate = Gate()
  let actionResult: ActionResult
  /// Queue of `domains()` responses. **Each call claims its response when it is
  /// made, not when it is released** — that ordering is the whole point for the
  /// stale-refresh test: a poll issued *before* an action must answer with
  /// pre-action server truth even though it resolves afterwards. The last entry
  /// repeats, so a test that only needs one fixed answer can seed one.
  var domainsResults: [StubResult] = [.success([])]
  private let lock = NSLock()
  private var _actionCallCount = 0
  var actionCallCount: Int { lock.withLock { _actionCallCount } }

  init(actionResult: ActionResult) { self.actionResult = actionResult }

  func domains() async throws -> VMInventory {
    let result: StubResult = lock.withLock {
      domainsResults.count > 1 ? domainsResults.removeFirst() : domainsResults[0]
    }
    _ = await gate.enter()
    switch result {
    case .success(let domains): return VMInventory(domains: domains)
    case .unavailable: return VMInventory(domains: nil)
    case .failure(let error): throw error
    }
  }

  func start(id: String) async throws { try await act() }
  func stop(id: String) async throws { try await act() }
  func forceStop(id: String) async throws { try await act() }
  func pause(id: String) async throws { try await act() }
  func resume(id: String) async throws { try await act() }
  func reboot(id: String) async throws { try await act() }
  func reset(id: String) async throws { try await act() }

  private func act() async throws {
    lock.withLock { _actionCallCount += 1 }
    _ = await gate.enter()
    switch actionResult {
    case .success: return
    case .failure(let error): throw error
    }
  }
}

extension VMDomain {
  /// A local fixture — `TowerCoreTests`' own helpers live in `TowerKit`'s test
  /// target and aren't visible from `TowerTests`.
  fileprivate static func stub(
    id: String, name: String? = "VM", state: VMState = .running
  ) -> VMDomain {
    VMDomain(id: id, name: name, state: state)
  }
}
