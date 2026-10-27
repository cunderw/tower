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
}

extension DashboardSnapshot {
  fileprivate static func fixture(state: String) -> DashboardSnapshot {
    DashboardSnapshot(
      array: ArrayStatus(
        state: state, capacity: ArrayCapacity(free: 1, used: 3, total: 4),
        disks: [], parities: [], caches: [], system: nil
      ),
      parity: ParityStatus(
        state: .neverRun, progressPercent: nil, errors: nil,
        speed: nil, lastRunTimestamp: nil, durationSeconds: nil, correcting: false
      ),
      services: ServiceCounts(
        containersRunning: 0, containersTotal: 0, vmsRunning: 0, vmsTotal: 0,
        sharesTotal: 0
      )
    )
  }
}
