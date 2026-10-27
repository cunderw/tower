import Foundation
import Testing
import TowerCore
import TowerData
@testable import Tower

/// Instance lifecycle: disable, delete, reorder, and edit-in-place.
@MainActor
@Suite
struct ServicesStoreTests {
  private func instance(
    _ kind: ServiceKind, _ name: String, enabled: Bool = true
  ) -> ServiceInstance {
    ServiceInstance(
      kind: kind, name: name, baseURL: URL(string: "http://192.0.2.1")!,
      credentials: .apiKey("k"), isEnabled: enabled)
  }

  private func makeStore(
    _ seed: [ServiceInstance] = [],
    status: ServiceStatus = .reachable(version: nil)
  ) -> (ServicesStore, ServiceDirectory) {
    let directory = ServiceDirectory.inMemory(seed)
    let store = ServicesStore(directory: directory, checker: StaticServiceStatusChecker(status))
    store.reloadInstances()
    return (store, directory)
  }

  // MARK: - Disable

  @Test func disablingHidesAnInstanceFromTheHubButKeepsTheRecord() async {
    let (store, directory) = makeStore([instance(.radarr, "Radarr")])
    let radarr = store.instances[0]

    await store.setEnabled(false, for: radarr)

    #expect(store.enabledInstances.isEmpty, "a disabled service must not be listed on the hub")
    #expect(store.instances.count == 1, "disable is not delete — the record stays")
    #expect(try! directory.instances().first?.isEnabled == false)
  }

  @Test func aDisabledInstanceIsNeverChecked() async {
    // "Never fetched" is the half of disable a user can't see, and the half
    // that matters for a service that is deliberately off.
    let (store, _) = makeStore([instance(.radarr, "Radarr")])
    await store.setEnabled(false, for: store.instances[0])

    await store.refreshStatuses()

    #expect(store.statuses.isEmpty)
  }

  @Test func reEnablingRestoresTheInstanceIntact() async {
    let (store, _) = makeStore([
      instance(.radarr, "Radarr 4K"),
      instance(.sonarr, "Sonarr"),
    ])
    let radarr = store.instances[0]
    await store.setEnabled(false, for: radarr)

    await store.setEnabled(true, for: store.instances.first { $0.id == radarr.id }!)

    let restored = store.instances.first { $0.id == radarr.id }
    #expect(restored == radarr, "re-enabling must give back exactly the record that was disabled")
    #expect(store.enabledInstances.count == 2)
    #expect(store.statuses[radarr.id] != nil, "a re-enabled service is checked again")
  }

  @Test func disablingLeavesTheOtherInstancesAlone() async {
    let (store, _) = makeStore([instance(.radarr, "Radarr"), instance(.sonarr, "Sonarr")])
    await store.load()

    await store.setEnabled(false, for: store.instances[0])

    #expect(store.enabledInstances.map(\.name) == ["Sonarr"])
    #expect(store.statuses[store.instances[1].id] != nil)
  }

  // MARK: - Delete

  @Test func deleteRemovesTheRecordFromTheDirectory() {
    let (store, directory) = makeStore([instance(.radarr, "Radarr"), instance(.sonarr, "Sonarr")])

    store.delete(store.instances[0])

    #expect(store.instances.map(\.name) == ["Sonarr"])
    #expect(try! directory.instances().map(\.name) == ["Sonarr"])
  }

  @Test func deletingDropsTheDeletedInstancesStatus() async {
    // Otherwise a re-added service inherits the badge of the one it replaced.
    let (store, _) = makeStore([instance(.radarr, "Radarr")])
    await store.load()
    let radarr = store.instances[0]

    store.delete(radarr)

    #expect(store.statuses[radarr.id] == nil)
  }

  // MARK: - Reorder

  @Test func reorderPersistsToTheDirectory() {
    let (store, directory) = makeStore([
      instance(.radarr, "a"), instance(.sonarr, "b"), instance(.lidarr, "c"),
    ])

    store.move(store.instances.map(\.id), from: IndexSet(integer: 2), to: 0)

    #expect(store.instances.map(\.name) == ["c", "a", "b"])
    // The directory, not just the store: the order has to persist across a
    // relaunch, and the directory is what a relaunch reads.
    #expect(try! directory.instances().map(\.name) == ["c", "a", "b"])
  }

  @Test func movingWithinACategoryLeavesEveryOtherRowWhereItWas() {
    // The hub is grouped, so a move inside one section must not disturb the
    // sections around it — including any hidden disabled rows between them.
    let (store, _) = makeStore([
      instance(.radarr, "radarr"),
      instance(.sonarr, "sonarr"),
      instance(.prowlarr, "prowlarr", enabled: false),
      instance(.nzbget, "nzb"),
      instance(.lidarr, "lidarr"),
    ])
    let mediaGroup = store.groups.first { $0.category == .mediaManagement }!
    #expect(mediaGroup.instances.map(\.name) == ["radarr", "sonarr", "lidarr"])

    store.move(mediaGroup.instances.map(\.id), from: IndexSet(integer: 2), to: 0)

    #expect(
      store.instances.map(\.name) == ["lidarr", "radarr", "prowlarr", "nzb", "sonarr"],
      "only the moved category's rows may change position")
    #expect(
      store.groups.first { $0.category == .mediaManagement }?.instances.map(\.name)
        == ["lidarr", "radarr", "sonarr"])
  }

  // MARK: - Edit

  @Test func editingUpdatesTheRecordInPlaceRatherThanAddingASecond() {
    let (store, directory) = makeStore([instance(.radarr, "Radarr")])
    let original = store.instances[0]

    let form = store.makeEditStore(for: original)
    form.name = "Radarr 4K"
    form.save()
    store.reloadInstances()

    #expect(store.instances.count == 1)
    #expect(store.instances[0].id == original.id)
    #expect(try! directory.instances().map(\.name) == ["Radarr 4K"])
  }

  @Test func theEditFormOpensOnTheExistingValues() {
    let existing = ServiceInstance(
      kind: .nzbget, name: "NZBGet",
      baseURL: URL(string: "http://192.0.2.1:6789")!,
      credentials: .usernamePassword(username: "admin", password: "hunter2"),
      customHeaders: ["CF-Access-Client-Id": "id"])
    let (store, _) = makeStore([existing])

    let form = store.makeEditStore(for: store.instances[0])

    #expect(form.isEditing)
    #expect(form.kind == .nzbget)
    #expect(form.name == "NZBGet")
    #expect(form.urlText == "http://192.0.2.1:6789")
    #expect(form.username == "admin")
    #expect(form.password == "hunter2")
    #expect(form.customHeaders.map(\.field) == ["CF-Access-Client-Id"])
  }

  @Test func editingADisabledInstanceDoesNotSilentlyReEnableIt() {
    let (store, _) = makeStore([instance(.radarr, "Radarr", enabled: false)])

    let form = store.makeEditStore(for: store.instances[0])
    form.name = "Renamed"
    let saved = form.save()

    #expect(saved?.isEnabled == false)
  }
}
