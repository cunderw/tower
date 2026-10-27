import Foundation
import TowerCore

/// Keeps one top-level store per service instance alive across navigation, so
/// re-entering a service renders on the first frame instead of cold-loading.
///
/// **A retained store *is* the cache**, which is the whole point of the shape.
/// There is never a second copy of the data to fall out of step with the
/// store's own, so a grab or a delete cannot be masked by something stale, and
/// `LoadingStore.mutate` already renders stale-then-fresh without passing
/// through `.loading`.
///
/// **It also owns the stores' lifetime.** A store constructed inline in
/// `ArrServiceScreen`'s `@ViewBuilder`, held below as a plain `@Bindable var`,
/// would take its identity from the parent's body evaluation, and the parent
/// reads `servicesStore.instances` — an `@Observable` — so an unrelated change
/// there would rebuild the store and blank a populated library *mid-session*,
/// with no navigation involved. A cache layered on top would hide that while
/// the wasted request still happened.
///
/// In memory only, for the app session. Nothing is written to disk.
///
/// **Deliberately not `@Observable`.** `ArrServiceScreen` calls `store(for:)`
/// from its body, and every call writes `clock` and `entries`. Observed, those
/// writes invalidate every other live `ArrServiceScreen` that read the registry,
/// and on iPad the hub's detail column and a sidebar tab can both hold one: each
/// body re-run would invalidate the other, and the app would freeze until the
/// watchdog killed it. No view needs to watch the registry; the stores it hands
/// out are the observable part. So `invalidate(_:)` does not re-render an open
/// screen by itself. That is fine, because both callers in `ServicesStore` call
/// `reloadInstances()` next, and the hub and the sidebar re-resolve the
/// instance from the observable `instances`.
@MainActor
final class ServiceStoreRegistry {
  /// How many instances' stores are kept. Nobody opens nine media services in a
  /// session, and an unbounded registry in a long-lived app is a leak with a
  /// friendly name.
  private let capacity: Int

  private struct Entry {
    let store: AnyObject
    /// Monotonic touch ordinal. A counter rather than a `Date` because two
    /// touches in the same millisecond must still order, and rather than array
    /// reordering because that is O(n) on the hot path.
    var lastTouched: Int
  }

  private var entries: [ServiceInstance.ID: Entry] = [:]
  private var clock = 0

  init(capacity: Int = 8) {
    self.capacity = capacity
  }

  /// The store for this instance, building it on the first request and handing
  /// back the same one afterwards.
  ///
  /// Generic over the store so the registry never needs to know the concrete
  /// types; the caller does, and it is the one place that maps a repository to
  /// a screen.
  ///
  /// **The type is checked, not assumed.** A stored entry of the wrong type
  /// means the instance's kind changed under a reused id — not something the
  /// add/edit flow can currently produce, since an edit keeps the id and the
  /// kind together, but a `as?` that silently rebuilds is a cheaper failure
  /// than a crash if that ever stops being true.
  func store<Store: AnyObject>(
    for id: ServiceInstance.ID,
    make: () -> Store
  ) -> Store {
    clock += 1
    if let existing = entries[id]?.store as? Store {
      entries[id]?.lastTouched = clock
      return existing
    }
    let store = make()
    entries[id] = Entry(store: store, lastTouched: clock)
    evictIfNeeded()
    return store
  }

  /// Drops one instance's store — called when that instance is edited or
  /// deleted. A changed base URL or API key must not keep serving data fetched
  /// through the previous repository.
  func invalidate(_ id: ServiceInstance.ID) {
    entries[id] = nil
  }

  /// Drops everything — a demo-mode switch or a sign-out.
  func removeAll() {
    entries.removeAll()
  }

  /// Test seam: how many stores are currently retained.
  var count: Int { entries.count }

  /// Test seam: whether a specific instance's store is retained.
  func isRetaining(_ id: ServiceInstance.ID) -> Bool { entries[id] != nil }

  private func evictIfNeeded() {
    guard entries.count > capacity else { return }
    // Least recently *touched*, so a service the user keeps returning to
    // survives a sweep through several others.
    if let oldest = entries.min(by: { $0.value.lastTouched < $1.value.lastTouched })?.key {
      entries[oldest] = nil
    }
  }
}
