import Foundation
import Observation
import TowerCore
import TowerData

/// The Services hub's store: the configured instances, and each one's health.
///
/// **Not a `LoadingStore`.** The other tabs load one remote list and live in
/// `Loadable`; this one reads its list *locally* from the keychain — which is
/// synchronous and effectively never fails — and then fans out N independent
/// remote checks whose failures belong to individual rows, not to the screen. A
/// single `Loadable` would have to pick one of those N outcomes to represent the
/// whole list, which is exactly what the hub must not do: one dead Radarr can't
/// be allowed to blank the four services that are up.
@MainActor
@Observable
final class ServicesStore {
  /// Every configured instance, hub order — including disabled ones, which the
  /// hub hides but instance management needs to show.
  private(set) var instances: [ServiceInstance] = []
  /// Per-instance health, filled in as each check answers rather than in one
  /// batch at the end.
  private(set) var statuses: [UUID: ServiceStatus] = [:]
  /// A keychain read that failed. Distinct from a service being unreachable:
  /// this one means Tower can't tell what is configured at all.
  private(set) var directoryError: AppError?
  private(set) var isCheckingStatuses = false

  private let directory: any ServiceDirectoryStoring
  private let checker: any ServiceStatusChecking
  private let assist: DockerServiceAssist?
  /// Told when an instance changes, so a retained store built on the previous
  /// address or key is dropped.
  ///
  /// **Centralised on the two mutating paths rather than left to call sites.**
  /// `adopt` has four callers and `delete` two; asking each to remember would
  /// make a forgotten one a silent bug — a service edited to a new URL still
  /// showing the old server's library.
  ///
  /// Optional so tests and previews can build a store without one.
  private let serviceStores: ServiceStoreRegistry?

  init(
    directory: any ServiceDirectoryStoring,
    checker: any ServiceStatusChecking,
    assist: DockerServiceAssist? = nil,
    serviceStores: ServiceStoreRegistry? = nil
  ) {
    self.directory = directory
    self.checker = checker
    self.assist = assist
    self.serviceStores = serviceStores
  }

  /// A form store for adding a service, built from the same directory and
  /// checker this hub reads — so a Test in the sheet is the identical call the
  /// row will make, and a Save lands where `reloadInstances()` looks.
  func makeServiceFormStore() -> ServiceFormStore {
    ServiceFormStore(directory: directory, checker: checker, assist: assist)
  }

  /// The same form, opened on an existing instance.
  func makeEditStore(for instance: ServiceInstance) -> ServiceFormStore {
    ServiceFormStore(directory: directory, checker: checker, assist: assist, editing: instance)
  }

  /// Turns an instance off (keeps its configuration, hides it from the hub) or
  /// back on. A disabled instance is never checked — `refreshStatuses()` only
  /// walks `enabledInstances` — so its stale status is dropped here rather than
  /// left to reappear the moment it is re-enabled.
  func setEnabled(_ isEnabled: Bool, for instance: ServiceInstance) async {
    var updated = instance
    updated.isEnabled = isEnabled
    do {
      let saved = try directory.save(updated)
      reloadInstances()
      if isEnabled {
        statuses[saved.id] = await checker.status(for: saved)
      } else {
        statuses[saved.id] = nil
      }
    } catch {
      directoryError = AppError.wrapping(error)
    }
  }

  /// Removes the keychain record. Callers put a confirmation in front of this;
  /// there is no undo, because the credential is gone with it.
  func delete(_ instance: ServiceInstance) {
    do {
      try directory.delete(id: instance.id)
      serviceStores?.invalidate(instance.id)
      reloadInstances()
    } catch {
      directoryError = AppError.wrapping(error)
    }
  }

  /// Reorders the rows a list is showing, and persists the result.
  ///
  /// Takes the ids being displayed rather than a category, because the hub
  /// shows only enabled instances while Settings shows all of them — and either
  /// way, a move must leave every row *not* in that list exactly where it is,
  /// including the disabled instances the hub is hiding, which still hold
  /// positions in the global order.
  func move(_ ids: [UUID], from offsets: IndexSet, to destination: Int) {
    var moved = ids
    moved.move(fromOffsets: offsets, toOffset: destination)
    let affected = Set(ids)
    var replacement = moved.makeIterator()
    let reordered = instances.map { instance -> UUID in
      guard affected.contains(instance.id) else { return instance.id }
      return replacement.next() ?? instance.id
    }
    do {
      try directory.reorder(to: reordered)
      reloadInstances()
    } catch {
      directoryError = AppError.wrapping(error)
    }
  }

  /// Called after the add sheet saves: the new row appears immediately and with
  /// its own status rather than a blank line, and nothing else is re-checked.
  func adopt(_ instance: ServiceInstance) async {
    // Before anything reads it. An **edit** arrives here too — the form saves
    // in place under the same id — so a changed base URL or API key must drop
    // the store holding the old server's data. An add is a miss either way.
    serviceStores?.invalidate(instance.id)
    reloadInstances()
    guard instance.isEnabled else { return }
    let checker = self.checker
    statuses[instance.id] = await checker.status(for: instance)
  }

  /// Instances the hub shows. Disabled ones keep their configuration and their
  /// place in the order, but are not listed and are never checked — a disabled
  /// service is one the user has told us not to talk to.
  var enabledInstances: [ServiceInstance] {
    instances.filter(\.isEnabled)
  }

  /// Enabled instances grouped into the four categories, in category
  /// order, with empty categories omitted.
  var groups: [ServiceGroup] {
    ServiceCategory.allCases.compactMap { category in
      let members = enabledInstances.filter { $0.kind.category == category }
      return members.isEmpty ? nil : ServiceGroup(category: category, instances: members)
    }
  }

  var isEmpty: Bool { enabledInstances.isEmpty }

  func status(for instance: ServiceInstance) -> ServiceStatus? {
    statuses[instance.id]
  }

  func instance(id: UUID) -> ServiceInstance? {
    instances.first { $0.id == id }
  }

  /// Re-reads the directory and checks everything. Safe to call on every
  /// appearance: the read is local, and the checks are what cost anything.
  func load() async {
    reloadInstances()
    await refreshStatuses()
  }

  /// The keychain half on its own — for after an add, edit, or delete, which
  /// change the list without needing every other row re-checked.
  func reloadInstances() {
    do {
      instances = try directory.instances()
      directoryError = nil
      // Drop statuses for instances that are gone, so a deleted-then-re-added
      // service can't inherit the badge of the one it replaced.
      let live = Set(instances.map(\.id))
      statuses = statuses.filter { live.contains($0.key) }
    } catch {
      directoryError = AppError.wrapping(error)
    }
  }

  /// Checks every enabled instance concurrently, publishing each result the
  /// moment it lands.
  ///
  /// Deliberately not `checker.statuses(for:)`, which answers once all of them
  /// have: on a hub with a service that is down, that would hold every healthy
  /// row at "Checking…" for the full timeout of the slowest one.
  func refreshStatuses() async {
    let targets = enabledInstances
    guard !targets.isEmpty else { return }
    isCheckingStatuses = true
    defer { isCheckingStatuses = false }

    let checker = self.checker
    await withTaskGroup(of: (UUID, ServiceStatus).self) { group in
      for instance in targets {
        group.addTask { (instance.id, await checker.status(for: instance)) }
      }
      for await (id, status) in group {
        statuses[id] = status
      }
    }
  }
}

/// One category's worth of hub rows.
struct ServiceGroup: Identifiable, Equatable {
  let category: ServiceCategory
  let instances: [ServiceInstance]

  var id: ServiceCategory { category }
}
