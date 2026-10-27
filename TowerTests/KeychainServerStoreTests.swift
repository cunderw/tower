import Foundation
import Testing
import TowerCore
import TowerData
@testable import Tower

/// Exercises the real `KeychainServerStore` against the real keychain.
///
/// `swift test` can never run these: `TowerData`'s package target has no
/// entitlements, so every `SecItemAdd`/`SecItemUpdate` call fails with
/// `errSecMissingEntitlement` (-34018) when the host process is unsigned.
/// `TowerTests` is hosted by the `Tower` app (see `TEST_HOST`/`BUNDLE_LOADER`
/// in `project.pbxproj`), and the `Tower` app target carries a real
/// (ad-hoc) code signature — so the host process has a keychain-access-group
/// entitlement and these tests can hit the real keychain.
///
/// Each test uses a unique `service` string so runs never collide with each
/// other or with the real app's stored credential, and clears its own entry
/// in a `defer` so a failed assertion still cleans up.
@Suite
struct KeychainServerStoreTests {
  private func makeStore() -> KeychainServerStore {
    KeychainServerStore(service: "com.cunderw.tower.tests.\(UUID().uuidString)")
  }

  @Test func saveThenLoadRoundTripsTheWholeServerValue() throws {
    let store = makeStore()
    defer { try? store.clear() }

    let server = Server(name: "Tower", url: URL(string: "http://192.0.2.10")!, apiKey: "abc123")
    try store.save(server)

    // Compares the whole value (id/name/url/apiKey), not one field — a
    // regression that saved the right key but returned a stale/placeholder
    // server would still pass a bare `apiKey ==` check.
    #expect(try store.load() == server)
  }

  @Test func savingTwiceReturnsTheSecondValueOnLoad() throws {
    let store = makeStore()
    defer { try? store.clear() }

    let url = URL(string: "http://192.0.2.10")!
    try store.save(Server(name: "Tower", url: url, apiKey: "first-key"))
    let second = Server(name: "Tower", url: url, apiKey: "second-key")
    try store.save(second)

    // This is the `SecItemUpdate` branch of `KeychainServerStore.save()` —
    // the actual target of this test file. A regression here (e.g. `save()`
    // silently no-oping on the second call, or `SecItemAdd`-ing a duplicate
    // item instead of updating) would break reconnect for every real user.
    #expect(try store.load() == second)
  }

  @Test func clearThenLoadReturnsNil() throws {
    let store = makeStore()

    try store.save(Server(name: "Tower", url: URL(string: "http://192.0.2.10")!, apiKey: "abc123"))
    try store.clear()

    #expect(try store.load() == nil)
  }

  /// `save()` is check-then-act (`SecItemCopyMatching`, then add or
  /// update) across two non-atomic Security calls, so concurrent callers can both
  /// see `errSecItemNotFound`, both call `SecItemAdd`, and the loser gets
  /// `errSecDuplicateItem`. Passed through, that is an opaque
  /// `.unexpectedStatus(-25299)` — telling a user their credential failed to save
  /// when the item is in fact there.
  ///
  /// **This test is probabilistic about the race and deterministic about the
  /// outcome**, and it's worth being explicit about which: nothing here can force
  /// the interleaving, because doing so would mean injecting a seam between the
  /// lookup and the add inside `save()`. What it does assert unconditionally is
  /// the property that matters — that no concurrent save *throws*, and that the
  /// store ends holding exactly one of the values that was written. A save that
  /// loses the race retries as an update rather than throwing.
  @Test func concurrentSavesNeverThrowAndLeaveOneCoherentValue() async throws {
    let store = makeStore()
    defer { try? store.clear() }

    let url = URL(string: "http://192.0.2.10")!
    let servers = (1...8).map { Server(name: "Tower", url: url, apiKey: "key-\($0)") }

    await withTaskGroup(of: Void.self) { group in
      for server in servers {
        group.addTask {
          // A throw here is the failure under test, so it's recorded
          // rather than propagated — the point is which call failed, not that the
          // group did.
          do {
            try store.save(server)
          } catch {
            Issue.record("a concurrent save threw: \(error)")
          }
        }
      }
    }

    let loaded = try #require(try store.load())
    #expect(servers.contains(loaded), "the store holds a value nobody saved: \(loaded)")
  }

  @Test func clearOnAnEmptyStoreDoesNotThrow() throws {
    let store = makeStore()
    try store.clear()
  }
}
