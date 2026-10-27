import Testing
import TowerCore
import TowerData
@testable import Tower

@MainActor
struct ConnectStoreTests {
  private func makeStore(
    repository: SystemRepositoryProtocol,
    store serverStore: ServerStoring = InMemoryServerStore()
  ) -> ConnectStore {
    ConnectStore(serverStore: serverStore, makeRepository: { _ in repository })
  }

  @Test func rejectsAnEmptyURLWithoutHittingTheNetwork() async {
    let repository = StubSystemRepository(result: .success(true))
    let store = makeStore(repository: repository)
    store.urlText = ""
    store.apiKey = "abc"
    await store.connect()
    #expect(store.state.error == .invalidServerURL)
    #expect(repository.callCount == 0)
  }

  @Test func rejectsAURLWithoutAScheme() async {
    let repository = StubSystemRepository(result: .success(true))
    let store = makeStore(repository: repository)
    store.urlText = "192.0.2.10"
    store.apiKey = "abc"
    await store.connect()
    #expect(store.state.error == .invalidServerURL)
  }

  @Test func savesTheServerOnSuccess() async throws {
    let serverStore = InMemoryServerStore()
    let store = makeStore(
      repository: StubSystemRepository(result: .success(true)),
      store: serverStore
    )
    store.urlText = "http://192.0.2.10"
    store.apiKey = "abc"
    await store.connect()
    // Asserts the actual value, not merely its presence — a regression that
    // saved the right server but returned a different/placeholder one in
    // `state` would still pass a bare `!= nil` check.
    #expect(store.state.value?.apiKey == "abc")
    #expect(store.state.value?.url.absoluteString == "http://192.0.2.10")
    #expect(try serverStore.load()?.apiKey == "abc")
  }

  @Test func doesNotSaveWhenTheServerRejectsTheKey() async throws {
    let serverStore = InMemoryServerStore()
    let store = makeStore(
      repository: StubSystemRepository(result: .failure(.unauthorized)),
      store: serverStore
    )
    store.urlText = "http://192.0.2.10"
    store.apiKey = "wrong"
    await store.connect()
    #expect(store.state.error == .unauthorized)
    #expect(try serverStore.load() == nil)
  }

  // Distinct from `doesNotSaveWhenTheServerRejectsTheKey`: that test throws
  // inside `testConnection()`, never reaching the `guard reachable` line in
  // `connect()`. This is the only test that exercises `testConnection()`
  // returning `false` without throwing — the case the guard exists for.
  @Test func doesNotSaveWhenTheServerReportsUnreachable() async throws {
    let serverStore = InMemoryServerStore()
    let store = makeStore(
      repository: StubSystemRepository(result: .success(false)),
      store: serverStore
    )
    store.urlText = "http://192.0.2.10"
    store.apiKey = "abc"
    await store.connect()
    #expect(store.state.error == .serverUnreachable)
    #expect(try serverStore.load() == nil)
  }

  @Test func trimsWhitespaceFromPastedCredentials() async throws {
    let serverStore = InMemoryServerStore()
    let store = makeStore(
      repository: StubSystemRepository(result: .success(true)),
      store: serverStore
    )
    store.urlText = "  http://192.0.2.10/  "
    store.apiKey = "  abc\n"
    await store.connect()
    // Covers both trims: a URL still carrying its whitespace or trailing
    // slash fails to parse and `connect()` returns before ever saving, so a
    // regression dropping either trim shows up as a nil load, not a
    // mismatched value.
    #expect(try serverStore.load()?.url.absoluteString == "http://192.0.2.10")
    #expect(try serverStore.load()?.apiKey == "abc")
  }

  @Test func normalizedURLPreservesACustomPort() {
    let url = ConnectStore.normalizedURL(from: "http://192.0.2.10:8443")
    #expect(url?.port == 8443)
    #expect(url?.host() == "192.0.2.10")
  }

  @Test func normalizedURLAcceptsAnIPv6Literal() {
    let url = ConnectStore.normalizedURL(from: "http://[::1]:8443")
    #expect(url?.port == 8443)
  }

  @Test func normalizedURLAcceptsHTTPSAndStripsTrailingSlashes() {
    #expect(ConnectStore.normalizedURL(from: "https://tower.local/")?.scheme == "https")
    #expect(ConnectStore.normalizedURL(from: "http://192.0.2.10///")?.absoluteString == "http://192.0.2.10")
  }

  @Test func normalizedURLRejectsANonHTTPScheme() {
    #expect(ConnectStore.normalizedURL(from: "ftp://192.0.2.10") == nil)
  }

  // The only thing preventing a double-tap from racing
  // `KeychainServerStore`'s check-then-act save path — regressing
  // either half of this condition reopens that race.
  @Test func canSubmitRequiresNonEmptyFieldsAndNotLoading() {
    let store = makeStore(repository: StubSystemRepository(result: .success(true)))
    #expect(store.canSubmit == false)

    store.urlText = "http://192.0.2.10"
    store.apiKey = "abc"
    #expect(store.canSubmit == true)

    store.state = .loading
    #expect(store.canSubmit == false)
  }
}

private final class StubSystemRepository: SystemRepositoryProtocol, @unchecked Sendable {
  enum Result { case success(Bool), failure(AppError) }
  let result: Result
  private(set) var callCount = 0

  init(result: Result) { self.result = result }

  func testConnection() async throws -> Bool {
    callCount += 1
    switch result {
    case .success(let value): return value
    case .failure(let error): throw error
    }
  }

  func dashboard() async throws -> DashboardSnapshot {
    DashboardSnapshot(
      array: ArrayStatus(state: "STARTED", capacity: nil, disks: [], parities: [], caches: [], system: nil),
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
