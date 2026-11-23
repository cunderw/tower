import Foundation
import Testing
import TowerCore
import TowerData
@testable import Tower

@MainActor
struct DashboardStoreTests {
  @Test func loadsDashboardSnapshot() async {
    let snapshot = DashboardSnapshot.fixture(state: "STARTED")
    let repository = StubDashboardRepository(results: [.success(snapshot)])
    let store = DashboardStore(repository: repository)
    await store.load()
    #expect(store.state.value?.array.state == "STARTED")
  }

  @Test func surfacesFailuresAsAppError() async {
    let repository = StubDashboardRepository(results: [.failure(.unauthorized)])
    let store = DashboardStore(repository: repository)
    await store.load()
    #expect(store.state.error == .unauthorized)
  }

  // The one that earns its place: `refresh()` must use `mutate`, not `load`,
  // so a transient poll failure 30 seconds in does not blank a working
  // dashboard. A failing refresh must keep the first snapshot on screen
  // *and* surface the new error via `.actionFailed`.
  @Test func refreshKeepsPreviousDataOnFailure() async {
    let snapshot = DashboardSnapshot.fixture(state: "STARTED")
    let repository = StubDashboardRepository(results: [
      .success(snapshot),
      .failure(.serverUnreachable),
    ])
    let store = DashboardStore(repository: repository)
    await store.load()
    await store.refresh()
    #expect(store.state.value == snapshot)
    #expect(store.state.error != nil)
  }

  // MARK: - Parity actions

  @Test func eachParityActionCallsItsOwnMutationThenRefetches() async {
    let running = DashboardSnapshot.fixture(state: "STARTED", parity: .running)
    let paused = DashboardSnapshot.fixture(state: "STARTED", parity: .paused)
    let repository = GatedDashboardRepository(dashboardResults: [.success(paused)])
    await repository.gate.releaseAll()
    let store = DashboardStore(repository: repository)
    store.state = .loaded(running)

    await store.perform(.pause)

    #expect(repository.calls == ["pause", "dashboard"])
    #expect(store.state == .loaded(paused))
    #expect(store.parityActionInFlight == nil)
  }

  @Test func startPassesTheCorrectChoiceThrough() async {
    for correct in [true, false] {
      let idle = DashboardSnapshot.fixture(state: "STARTED", parity: .completed)
      let repository = GatedDashboardRepository(dashboardResults: [.success(idle)])
      await repository.gate.releaseAll()
      let store = DashboardStore(repository: repository)
      store.state = .loaded(idle)

      await store.perform(.start, correct: correct)

      #expect(repository.calls == ["start(correct: \(correct))", "dashboard"])
    }
  }

  @Test func aFailedParityActionKeepsTheDashboardAndShowsTheServersMessage() async {
    let running = DashboardSnapshot.fixture(state: "STARTED", parity: .running)
    let repository = GatedDashboardRepository(
      dashboardResults: [.success(running)],
      actionResult: .failure(.graphQL(["Array must be started to check parity"]))
    )
    await repository.gate.releaseAll()
    let store = DashboardStore(repository: repository)
    store.state = .loaded(running)

    await store.perform(.cancel)

    #expect(store.state.value == running)
    #expect(store.state.error?.message == "Array must be started to check parity")
    #expect(repository.calls == ["cancel"], "a failed action must not re-fetch")
    #expect(store.parityActionInFlight == nil)
  }

  @Test func aFailedRefetchAfterASuccessfulActionSaysTheActionSucceeded() async {
    // "Cancel Check failed" would be false, and it invites a retry of an
    // action that already happened.
    let running = DashboardSnapshot.fixture(state: "STARTED", parity: .running)
    let repository = GatedDashboardRepository(dashboardResults: [.failure(.serverUnreachable)])
    await repository.gate.releaseAll()
    let store = DashboardStore(repository: repository)
    store.state = .loaded(running)

    await store.perform(.cancel)

    #expect(store.state.value == running)
    let message = store.state.error?.message ?? ""
    #expect(message.hasPrefix("Cancel Check succeeded, but Tower couldn't refresh the parity status."), "\(message)")
  }

  @Test func aSecondParityActionWhileOneIsInFlightIsIgnored() async {
    let running = DashboardSnapshot.fixture(state: "STARTED", parity: .running)
    let repository = GatedDashboardRepository(dashboardResults: [.success(running)])
    let store = DashboardStore(repository: repository)
    store.state = .loaded(running)

    let first = Task { await store.perform(.pause) }
    await repository.gate.waitUntilEntered(atLeast: 1)
    #expect(store.parityActionInFlight == .pause)

    await store.perform(.cancel)
    #expect(repository.calls == ["pause"], "the second action must not reach the repository")

    await repository.gate.releaseAll()
    await first.value
    #expect(repository.calls == ["pause", "dashboard"])
    #expect(store.parityActionInFlight == nil)
  }

  @Test func aPollIssuedBeforeAParityActionDoesNotRevertIt() async {
    // The poll asks first and so claims the pre-action snapshot (running);
    // the action's re-fetch claims the post-action one (paused). Without the
    // guard the poll's late answer lands last and the card reads "running".
    let running = DashboardSnapshot.fixture(state: "STARTED", parity: .running)
    let paused = DashboardSnapshot.fixture(state: "STARTED", parity: .paused)
    let repository = GatedDashboardRepository(dashboardResults: [.success(running), .success(paused)])
    let store = DashboardStore(repository: repository)
    store.state = .loaded(running)

    let poll = Task { await store.refresh() }
    await repository.gate.waitUntilEntered(atLeast: 1)

    let pause = Task { await store.perform(.pause) }
    await repository.gate.waitUntilEntered(atLeast: 2)
    await repository.gate.release(1)
    await repository.gate.release(2)
    await pause.value
    #expect(store.state.value?.parity.state == .paused)

    await repository.gate.release(0)
    await poll.value

    #expect(store.state.value?.parity.state == .paused, "a poll issued before the action must not revert it")
    #expect(store.state.error == nil)
  }
}

@MainActor
struct ParityHistoryStoreTests {
  @Test func loadsTheRepositorysHistory() async {
    let records = [
      ParityCheckRecord(id: 0, date: nil, durationSeconds: 100, speed: "120 MB/s", state: .completed, errors: 0),
    ]
    let repository = GatedDashboardRepository(dashboardResults: [], history: [.success(records)])
    await repository.gate.releaseAll()
    let store = ParityHistoryStore(repository: repository)

    await store.load()

    #expect(store.state == .loaded(records))
  }

  @Test func aFailedRefreshKeepsTheList() async {
    let records = [
      ParityCheckRecord(id: 0, date: nil, durationSeconds: 100, speed: "120 MB/s", state: .completed, errors: 0),
    ]
    let repository = GatedDashboardRepository(
      dashboardResults: [], history: [.success(records), .failure(.serverUnreachable)]
    )
    await repository.gate.releaseAll()
    let store = ParityHistoryStore(repository: repository)

    await store.load()
    await store.refresh()

    #expect(store.state.value == records)
    #expect(store.state.error == .serverUnreachable)
  }
}

/// `results` is a queue rather than a single fixed outcome:
/// `refreshKeepsPreviousDataOnFailure` needs `dashboard()` to answer
/// differently across two calls (a successful load, then a failing
/// refresh), which a single stored `Result` can't express.
private final class StubDashboardRepository: SystemRepositoryProtocol, @unchecked Sendable {
  enum Result { case success(DashboardSnapshot), failure(AppError) }
  private var results: [Result]

  init(results: [Result]) { self.results = results }

  func testConnection() async throws -> Bool { true }

  func dashboard() async throws -> DashboardSnapshot {
    precondition(!results.isEmpty, "dashboard() called more times than results were stubbed")
    switch results.removeFirst() {
    case .success(let snapshot): return snapshot
    case .failure(let error): throw error
    }
  }

  func startParityCheck(correct: Bool) async throws { unreachable() }
  func pauseParityCheck() async throws { unreachable() }
  func resumeParityCheck() async throws { unreachable() }
  func cancelParityCheck() async throws { unreachable() }
  func parityHistory() async throws -> [ParityCheckRecord] { unreachable() }

  private func unreachable() -> Never {
    preconditionFailure("the load and refresh tests never trigger parity")
  }
}

/// Records every call in order and suspends each on `gate` until the test
/// releases it, so the in-flight and stale-poll tests can observe the store
/// mid-action. Each `dashboard()` call claims its result when it is made, not
/// when it is released, the same as `VMStoreTests.GatedVMRepository`.
private final class GatedDashboardRepository: SystemRepositoryProtocol, @unchecked Sendable {
  enum Result<Value> { case success(Value), failure(AppError) }

  let gate = Gate()
  private let lock = NSLock()
  private var dashboardResults: [Result<DashboardSnapshot>]
  private var historyResults: [Result<[ParityCheckRecord]>]
  private let actionResult: Result<Void>
  private var _calls: [String] = []
  var calls: [String] { lock.withLock { _calls } }

  init(
    dashboardResults: [Result<DashboardSnapshot>],
    history: [Result<[ParityCheckRecord]>] = [],
    actionResult: Result<Void> = .success(())
  ) {
    self.dashboardResults = dashboardResults
    self.historyResults = history
    self.actionResult = actionResult
  }

  func testConnection() async throws -> Bool { true }

  func dashboard() async throws -> DashboardSnapshot {
    let result = lock.withLock {
      _calls.append("dashboard")
      return dashboardResults.removeFirst()
    }
    _ = await gate.enter()
    switch result {
    case .success(let snapshot): return snapshot
    case .failure(let error): throw error
    }
  }

  func startParityCheck(correct: Bool) async throws { try await act("start(correct: \(correct))") }
  func pauseParityCheck() async throws { try await act("pause") }
  func resumeParityCheck() async throws { try await act("resume") }
  func cancelParityCheck() async throws { try await act("cancel") }

  func parityHistory() async throws -> [ParityCheckRecord] {
    let result = lock.withLock { historyResults.removeFirst() }
    switch result {
    case .success(let records): return records
    case .failure(let error): throw error
    }
  }

  private func act(_ name: String) async throws {
    lock.withLock { _calls.append(name) }
    _ = await gate.enter()
    if case .failure(let error) = actionResult { throw error }
  }
}

extension DashboardSnapshot {
  fileprivate static func fixture(state: String, parity: ParityCheckState = .neverRun) -> DashboardSnapshot {
    DashboardSnapshot(
      array: ArrayStatus(
        state: state, capacity: ArrayCapacity(free: 1, used: 3, total: 4),
        disks: [], parities: [], caches: [], system: nil
      ),
      parity: ParityStatus(
        state: parity, progressPercent: nil, errors: nil,
        speed: nil, lastRunTimestamp: nil, durationSeconds: nil, correcting: false
      ),
      services: ServiceCounts(
        containersRunning: 0, containersTotal: 0, vmsRunning: 0, vmsTotal: 0,
        sharesTotal: 0
      )
    )
  }
}
