import Foundation
import Testing
import TowerCore
@testable import TowerData

private func makeInstance(
  _ kind: ServiceKind = .radarr,
  _ name: String = "Radarr",
  credentials: ServiceCredentials = .apiKey("abc")
) -> ServiceInstance {
  ServiceInstance(
    kind: kind,
    name: name,
    baseURL: URL(string: "http://192.0.2.10:7878")!,
    credentials: credentials
  )
}

/// Byte-level storage double. The directory's CRUD and ordering logic is the
/// part worth testing; the keychain is exercised only for its bytes, which
/// `swift test` cannot reach without an entitled host app.
private final class FakeRecordStorage: ServiceRecordStorage, @unchecked Sendable {
  private let lock = NSLock()
  private var data: Data?
  private(set) var writeCount = 0

  func read() throws -> Data? { lock.withLock { data } }
  func write(_ newValue: Data) throws {
    lock.withLock {
      data = newValue
      writeCount += 1
    }
  }
  func delete() throws { lock.withLock { data = nil } }
}

@Test func anEmptyDirectoryHasNoInstances() throws {
  #expect(try ServiceDirectory.inMemory().instances().isEmpty)
}

@Test func savedInstancesRoundTripThroughStorage() throws {
  // Two directories over one storage stand in for an app relaunch: nothing is
  // cached in the directory, so the second one sees only what was persisted.
  let storage = FakeRecordStorage()
  let instance = makeInstance()
  try ServiceDirectory(storage: storage).save(instance)
  #expect(try ServiceDirectory(storage: storage).instances() == [instance])
}

@Test func twoInstancesOfTheSameKindCoexist() throws {
  let directory = ServiceDirectory.inMemory()
  let hd = try directory.save(makeInstance(.radarr, "Radarr", credentials: .apiKey("hd")))
  let uhd = try directory.save(makeInstance(.radarr, "Radarr 4K", credentials: .apiKey("uhd")))

  let stored = try directory.instances()
  #expect(stored.count == 2)
  #expect(stored.map(\.id) == [hd.id, uhd.id])
  #expect(stored.map(\.name) == ["Radarr", "Radarr 4K"])
  #expect(stored.map(\.credentials) == [.apiKey("hd"), .apiKey("uhd")])
}

@Test func savingAnExistingIdUpdatesRatherThanDuplicating() throws {
  let directory = ServiceDirectory.inMemory()
  var instance = try directory.save(makeInstance())
  instance.name = "Renamed"
  instance.credentials = .apiKey("rotated")
  try directory.save(instance)

  let stored = try directory.instances()
  #expect(stored.count == 1)
  #expect(stored.first?.name == "Renamed")
  #expect(stored.first?.credentials == .apiKey("rotated"))
}

@Test func newInstancesAppendInSaveOrder() throws {
  let directory = ServiceDirectory.inMemory()
  for name in ["one", "two", "three"] {
    try directory.save(makeInstance(.sonarr, name))
  }
  #expect(try directory.instances().map(\.sortOrder) == [0, 1, 2])
  #expect(try directory.instances().map(\.name) == ["one", "two", "three"])
}

@Test func theDirectoryOwnsSortOrderOnInsert() throws {
  // A caller-supplied sortOrder is ignored on insert: ordering is the
  // directory's to assign, changed only through `reorder(to:)`. Otherwise two
  // add-service flows could both hand in 0 and the list order would depend on
  // decode order.
  let directory = ServiceDirectory.inMemory()
  var jumped = makeInstance(.lidarr, "Lidarr")
  jumped.sortOrder = 99
  #expect(try directory.save(jumped).sortOrder == 0)
}

@Test func updatingAnInstancePreservesItsPlaceInTheList() throws {
  let directory = ServiceDirectory.inMemory()
  try directory.save(makeInstance(.radarr, "first"))
  var second = try directory.save(makeInstance(.sonarr, "second"))
  second.name = "renamed"
  second.sortOrder = 0  // ignored — reorder(to:) is the only way to move a row
  try directory.save(second)
  #expect(try directory.instances().map(\.name) == ["first", "renamed"])
}

@Test func reorderRewritesSortOrderToTheGivenSequence() throws {
  let directory = ServiceDirectory.inMemory()
  let a = try directory.save(makeInstance(.radarr, "a"))
  let b = try directory.save(makeInstance(.sonarr, "b"))
  let c = try directory.save(makeInstance(.lidarr, "c"))

  try directory.reorder(to: [c.id, a.id, b.id])
  #expect(try directory.instances().map(\.name) == ["c", "a", "b"])
  #expect(try directory.instances().map(\.sortOrder) == [0, 1, 2])
}

@Test func reorderKeepsInstancesTheCallerOmitted() throws {
  // A stale reorder (a row added on another device between load and drop)
  // must not delete the instances it did not mention.
  let directory = ServiceDirectory.inMemory()
  let a = try directory.save(makeInstance(.radarr, "a"))
  let b = try directory.save(makeInstance(.sonarr, "b"))
  try directory.save(makeInstance(.lidarr, "c"))

  try directory.reorder(to: [b.id, a.id])
  #expect(try directory.instances().map(\.name) == ["b", "a", "c"])
}

@Test func reorderIgnoresUnknownIds() throws {
  let directory = ServiceDirectory.inMemory()
  let a = try directory.save(makeInstance(.radarr, "a"))
  try directory.reorder(to: [UUID(), a.id])
  #expect(try directory.instances().map(\.name) == ["a"])
}

@Test func deleteRemovesOnlyTheNamedInstance() throws {
  let directory = ServiceDirectory.inMemory()
  let a = try directory.save(makeInstance(.radarr, "a"))
  try directory.save(makeInstance(.sonarr, "b"))
  try directory.delete(id: a.id)
  #expect(try directory.instances().map(\.name) == ["b"])
}

@Test func deletingCompactsTheRemainingOrder() throws {
  // Leaving a gap would make the next insert collide with an existing
  // sortOrder, so the list order would stop being total.
  let directory = ServiceDirectory.inMemory()
  let a = try directory.save(makeInstance(.radarr, "a"))
  try directory.save(makeInstance(.sonarr, "b"))
  try directory.delete(id: a.id)
  let added = try directory.save(makeInstance(.lidarr, "c"))
  #expect(try directory.instances().map(\.sortOrder) == [0, 1])
  #expect(added.sortOrder == 1)
}

@Test func deletingAnUnknownIdIsNotAnError() throws {
  let directory = ServiceDirectory.inMemory()
  try directory.save(makeInstance())
  try directory.delete(id: UUID())
  #expect(try directory.instances().count == 1)
}

@Test func deletingIsNotAWriteWhenNothingMatched() throws {
  let storage = FakeRecordStorage()
  let directory = ServiceDirectory(storage: storage)
  try directory.save(makeInstance())
  try directory.delete(id: UUID())
  #expect(storage.writeCount == 1)
}

@Test func clearRemovesEveryInstance() throws {
  let directory = ServiceDirectory.inMemory()
  try directory.save(makeInstance(.radarr, "a"))
  try directory.save(makeInstance(.sonarr, "b"))
  try directory.clear()
  #expect(try directory.instances().isEmpty)
}

@Test func aCorruptRecordSurfacesAsAnError() throws {
  // Better to report than to silently return an empty list, which would look
  // to the user exactly like their services had been deleted.
  let storage = FakeRecordStorage()
  try storage.write(Data("not json".utf8))
  #expect(throws: (any Error).self) { try ServiceDirectory(storage: storage).instances() }
}

/// Writes `instances` as the directory would, then rewrites the `kind` of the
/// records at `retired` to a value this build has no case for. That is the
/// shape a service removed in a later version leaves in the keychain.
private func storageWithRetiredKind(
  _ instances: [ServiceInstance], retired: Set<Int>
) throws -> FakeRecordStorage {
  let storage = FakeRecordStorage()
  let seeded = ServiceDirectory(storage: storage)
  for instance in instances { try seeded.save(instance) }
  let data = try #require(try storage.read())
  var records = try #require(
    try JSONSerialization.jsonObject(with: data) as? [[String: Any]])
  for index in retired { records[index]["kind"] = "retiredservice" }
  try storage.write(try JSONSerialization.data(withJSONObject: records))
  return storage
}

@Test func aRecordOfARemovedKindIsDroppedAndTheRestLoad() throws {
  // An upgrade from a version that supported a service this one removed must
  // not lose the whole list, and must not crash on launch.
  let radarr = makeInstance(.radarr, "Radarr")
  let retired = makeInstance(
    .nzbget, "Gone", credentials: .usernamePassword(username: "u", password: "p"))
  let sonarr = makeInstance(.sonarr, "Sonarr")
  let storage = try storageWithRetiredKind([radarr, retired, sonarr], retired: [1])

  let loaded = try ServiceDirectory(storage: storage).instances()

  #expect(loaded.map(\.id) == [radarr.id, sonarr.id])
  // The gap the dropped record left is closed, so the next insert, which
  // takes `count` as its position, cannot tie with Sonarr.
  #expect(loaded.map(\.sortOrder) == [0, 1])
}

@Test func theNextWriteLeavesTheRemovedKindOut() throws {
  let radarr = makeInstance(.radarr, "Radarr")
  let retired = makeInstance(
    .nzbget, "Gone", credentials: .usernamePassword(username: "u", password: "p"))
  let storage = try storageWithRetiredKind([retired, radarr], retired: [0])
  let directory = ServiceDirectory(storage: storage)

  let added = try directory.save(makeInstance(.sonarr, "Sonarr"))

  let data = try #require(try storage.read())
  let records = try #require(
    try JSONSerialization.jsonObject(with: data) as? [[String: Any]])
  #expect(records.count == 2)
  #expect(!records.contains { $0["kind"] as? String == "retiredservice" })
  #expect(try directory.instances().map(\.id) == [radarr.id, added.id])
  #expect(added.sortOrder == 1)
}

@Test func aMalformedRecordOfAKnownKindStillSurfacesAsAnError() throws {
  // Only an unknown kind is dropped. A broken record of a kind this build
  // supports is a fault, and hiding it would look like a deleted service.
  let storage = FakeRecordStorage()
  try storage.write(Data(#"[{"kind":"radarr","name":"Radarr"}]"#.utf8))
  #expect(throws: (any Error).self) { try ServiceDirectory(storage: storage).instances() }
}
