import Foundation
import Testing
import TowerCore
import TowerData
@testable import Tower

/// Exercises `AppEnvironment.signOut()` and `performSignOut` against a spy
/// `ServerStoring`, not the real keychain (see `KeychainServerStoreTests`
/// for that) and not through SwiftUI — the whole point of extracting this
/// logic out of `RootView`'s button closure is that it's reachable without
/// driving a single view.
@MainActor
@Suite
struct SignOutTests {
  @Test func signOutClearsStoredCredentials() async {
    let spy = SpyServerStore()
    let environment = AppEnvironment(
      serverStore: spy,
      makeRepository: { _ in StubRepository() },
      makeDockerRepository: { _ in StubDockerRepository() },
      makeVMRepository: { _ in StubVMRepository() },
      makeShareRepository: { _ in StubShareRepository() },
      makeNotificationRepository: { _ in StubNotificationRepository() },
      makeLogRepository: { _ in StubLogRepository() },
      serviceDirectory: ServiceDirectory.inMemory(),
      serviceStatusChecker: StaticServiceStatusChecker(),
      makeServiceRepository: { _ in nil }
    )

    environment.signOut()

    #expect(spy.clearCallCount == 1)
  }

  // The one that matters most, against the actual privacy guarantee rather
  // than a restatement of the compiler's rules: `performSignOut` (extracted
  // from `RootView.handleSignOut`) must call `dismiss` and `onSignOut` even
  // when the store's `clear()` throws. Today that's true because
  // `AppEnvironment.signOut()` happens to be non-throwing, but this test
  // asserts on the actual side effects (did `dismiss`/`onSignOut` run), not
  // on a local variable that merely restates "control reached the next
  // line." If someone later wraps `signOut()` in a `do`/`catch` or adds a
  // guard that skips `onSignOut()` on failure — a reasonable-looking
  // "improvement" that would silently keep the user signed in with
  // credentials they believe are gone — this test catches it.
  @Test func signOutStillReturnsToConnectWhenClearFails() async {
    let spy = SpyServerStore(clearError: KeychainError.unexpectedStatus(-1))
    let environment = AppEnvironment(
      serverStore: spy,
      makeRepository: { _ in StubRepository() },
      makeDockerRepository: { _ in StubDockerRepository() },
      makeVMRepository: { _ in StubVMRepository() },
      makeShareRepository: { _ in StubShareRepository() },
      makeNotificationRepository: { _ in StubNotificationRepository() },
      makeLogRepository: { _ in StubLogRepository() },
      serviceDirectory: ServiceDirectory.inMemory(),
      serviceStatusChecker: StaticServiceStatusChecker(),
      makeServiceRepository: { _ in nil }
    )
    var didDismiss = false
    var didCallOnSignOut = false

    performSignOut(
      environment: environment,
      dismiss: { didDismiss = true },
      onSignOut: { didCallOnSignOut = true }
    )

    #expect(didDismiss, "a failed keychain clear must not stop the settings sheet from dismissing")
    #expect(didCallOnSignOut, "a failed keychain clear must not stop the app from returning to Connect")
    #expect(spy.clearCallCount == 1)
  }
}

/// Records how many times `clear()` was called and, when `clearError` is
/// set, fails every call with it. Backed by an `NSLock` around the counter
/// (the same pattern `TowerData`'s `InMemoryServerStore` uses) rather than
/// an unsynchronized `var` behind `@unchecked Sendable` — this project
/// otherwise enforces Swift 6 strict concurrency for real, not just at the
/// type-conformance level.
private final class SpyServerStore: ServerStoring, @unchecked Sendable {
  private let lock = NSLock()
  private var storedClearCallCount = 0
  private let clearError: Error?

  init(clearError: Error? = nil) {
    self.clearError = clearError
  }

  var clearCallCount: Int {
    lock.withLock { storedClearCallCount }
  }

  func save(_ server: Server) throws {}

  func load() throws -> Server? { nil }

  func clear() throws {
    lock.withLock { storedClearCallCount += 1 }
    if let clearError { throw clearError }
  }
}

private struct StubRepository: SystemRepositoryProtocol {
  func testConnection() async throws -> Bool { true }
  func dashboard() async throws -> DashboardSnapshot {
    DashboardSnapshot(
      array: ArrayStatus(state: "STARTED", capacity: nil, disks: [], parities: [], caches: [], system: nil),
      parity: ParityStatus(
        state: .neverRun, progressPercent: nil, errors: nil,
        speed: nil, lastRunTimestamp: nil, durationSeconds: nil, correcting: false
      ),
      services: ServiceCounts(containersRunning: 0, containersTotal: 0, vmsRunning: 0, vmsTotal: 0, sharesTotal: 0)
    )
  }
}

private struct StubDockerRepository: DockerRepositoryProtocol {
  func containers() async throws -> [Container] { [] }
  func start(id: String) async throws -> ContainerStateUpdate { unreachable() }
  func stop(id: String) async throws -> ContainerStateUpdate { unreachable() }
  func restart(id: String) async throws -> ContainerStateUpdate { unreachable() }
  func pause(id: String) async throws -> ContainerStateUpdate { unreachable() }
  func unpause(id: String) async throws -> ContainerStateUpdate { unreachable() }
  func logs(id: String, tail: Int?, since: String?) async throws -> ContainerLogs { unreachable() }

  /// Nothing in `SignOutTests` ever triggers a container action or fetches
  /// logs — these exist only so this stub keeps conforming to
  /// `DockerRepositoryProtocol`.
  private func unreachable() -> Never {
    preconditionFailure("SignOutTests never triggers a Docker mutation")
  }
}

/// Same reasoning as `StubDockerRepository` above, for the VM repository
/// `AppEnvironment` holds. `signOut()` touches no repository at all; these
/// exist so the environment can be constructed.
private struct StubVMRepository: VMRepositoryProtocol {
  func domains() async throws -> VMInventory { VMInventory(domains: []) }
  func start(id: String) async throws { unreachable() }
  func stop(id: String) async throws { unreachable() }
  func forceStop(id: String) async throws { unreachable() }
  func pause(id: String) async throws { unreachable() }
  func resume(id: String) async throws { unreachable() }
  func reboot(id: String) async throws { unreachable() }
  func reset(id: String) async throws { unreachable() }

  private func unreachable() -> Never {
    preconditionFailure("SignOutTests never triggers a VM action")
  }
}

/// A repository `AppEnvironment` holds. Shares are read-only, so there is
/// nothing here that could be unreachable.
private struct StubShareRepository: ShareRepositoryProtocol {
  func shares() async throws -> [Share] { [] }
}

/// A repository `AppEnvironment` holds. `signOut()` touches none of
/// them; these exist so the environment can be constructed.
private struct StubNotificationRepository: NotificationRepositoryProtocol {
  func overview() async throws -> NotificationOverview { .zero }
  func page(kind: NotificationKind, offset: Int, limit: Int) async throws -> NotificationPage {
    NotificationPage(notifications: [], requestedLimit: limit)
  }
  func archive(id: String) async throws -> NotificationOverview { unreachable() }
  func markUnread(id: String) async throws -> NotificationOverview { unreachable() }
  func delete(id: String, kind: NotificationKind) async throws -> NotificationOverview { unreachable() }
  func archiveAll() async throws -> NotificationOverview { unreachable() }

  private func unreachable() -> Never {
    preconditionFailure("SignOutTests never triggers a notification mutation")
  }
}

/// A repository `AppEnvironment` holds. Read-only, so there is nothing
/// here that could be unreachable.
private struct StubLogRepository: LogRepositoryProtocol {
  func logFiles() async throws -> [LogFile] { [] }
  func logFile(path: String, lines: Int?) async throws -> LogFileContents {
    LogFileContents(path: path, lines: [], totalLines: 0, startLine: nil)
  }
}
