import Foundation
import Testing
import TowerCore
@testable import Tower

/// The registry that keeps a service's store alive across navigation.
@MainActor
@Suite
struct ServiceStoreRegistryTests {
  /// A stand-in for a real store: the registry is generic over the type and
  /// never looks inside one, so the tests need nothing more than identity.
  private final class Box {
    let tag: String
    init(tag: String) { self.tag = tag }
  }

  private func id(_ n: Int) -> UUID {
    UUID(uuidString: "D0000000-0000-0000-0000-0000000000\(String(format: "%02d", n))")!
  }

  @Test func theSecondRequestForAnInstanceGetsTheStoreTheFirstOneBuilt() {
    // Re-entering a service must not rebuild its store; a rebuilt store makes
    // every visit a cold load.
    let registry = ServiceStoreRegistry()
    var builds = 0

    let first = registry.store(for: id(1)) { builds += 1; return Box(tag: "a") }
    let second = registry.store(for: id(1)) { builds += 1; return Box(tag: "b") }

    #expect(builds == 1, "the store was rebuilt on the second request")
    #expect(first === second)
    #expect(second.tag == "a", "a rebuilt store would carry the second tag")
  }

  @Test func differentInstancesGetDifferentStores() {
    // Two Radarrs are two independent libraries — the multi-instance promise.
    let registry = ServiceStoreRegistry()

    let one = registry.store(for: id(1)) { Box(tag: "one") }
    let two = registry.store(for: id(2)) { Box(tag: "two") }

    #expect(one !== two)
    #expect(registry.count == 2)
  }

  @Test func pastTheCapacityTheLeastRecentlyTouchedIsDropped() {
    let registry = ServiceStoreRegistry(capacity: 3)
    for n in 1...3 { _ = registry.store(for: id(n)) { Box(tag: "\(n)") } }

    _ = registry.store(for: id(4)) { Box(tag: "4") }

    #expect(registry.count == 3)
    #expect(!registry.isRetaining(id(1)), "the oldest entry should have been evicted")
    #expect(registry.isRetaining(id(4)))
  }

  @Test func touchingAnEntryProtectsItFromEviction() {
    // Least recently *touched*, not least recently created — a service the user
    // keeps coming back to must survive a sweep through several others.
    let registry = ServiceStoreRegistry(capacity: 3)
    for n in 1...3 { _ = registry.store(for: id(n)) { Box(tag: "\(n)") } }

    _ = registry.store(for: id(1)) { Box(tag: "rebuilt") }  // touch the oldest
    _ = registry.store(for: id(4)) { Box(tag: "4") }

    #expect(registry.isRetaining(id(1)), "the touched entry was evicted anyway")
    #expect(!registry.isRetaining(id(2)), "the now-oldest entry should have gone")
  }

  @Test func invalidatingDropsOneEntryAndLeavesTheRest() {
    let registry = ServiceStoreRegistry()
    let kept = registry.store(for: id(1)) { Box(tag: "kept") }
    _ = registry.store(for: id(2)) { Box(tag: "dropped") }

    registry.invalidate(id(2))

    #expect(registry.isRetaining(id(1)))
    #expect(!registry.isRetaining(id(2)))
    #expect(registry.store(for: id(1)) { Box(tag: "rebuilt") } === kept)
  }

  @Test func anInvalidatedInstanceIsRebuiltRatherThanResurrected() {
    // The reason invalidation exists: an edited instance may point at a
    // different address or carry a different key, so the store built on the
    // previous repository must not come back.
    let registry = ServiceStoreRegistry()
    let original = registry.store(for: id(1)) { Box(tag: "before-edit") }

    registry.invalidate(id(1))
    let rebuilt = registry.store(for: id(1)) { Box(tag: "after-edit") }

    #expect(rebuilt !== original)
    #expect(rebuilt.tag == "after-edit")
  }

  @Test func removeAllEmptiesTheRegistry() {
    // Sign-out and demo-mode switches: retained service data must not outlive
    // the session that fetched it.
    let registry = ServiceStoreRegistry()
    for n in 1...3 { _ = registry.store(for: id(n)) { Box(tag: "\(n)") } }

    registry.removeAll()

    #expect(registry.count == 0)
  }

  @Test func aStoredEntryOfADifferentTypeIsRebuiltRatherThanCrashing() {
    // Not reachable through the current add/edit flow — an edit keeps the id
    // and the kind together — but a type mismatch must degrade to a rebuild
    // rather than a force-cast trap if that ever stops being true.
    final class Other {}
    let registry = ServiceStoreRegistry()
    _ = registry.store(for: id(1)) { Other() }

    let box = registry.store(for: id(1)) { Box(tag: "rebuilt") }

    #expect(box.tag == "rebuilt")
  }
}
