import Foundation
import Security
import TowerCore

/// The instance list plus its CRUD, as `AppEnvironment` hands it around.
public protocol ServiceDirectoryStoring: Sendable {
  /// Configured instances, in hub order.
  func instances() throws -> [ServiceInstance]
  /// Inserts a new instance or replaces an existing one with the same `id`.
  /// Returns the stored value, whose `sortOrder` is the directory's, not the
  /// caller's.
  @discardableResult
  func save(_ instance: ServiceInstance) throws -> ServiceInstance
  func delete(id: UUID) throws
  /// Rewrites hub order to `ids`. Instances not named keep their relative order
  /// after the ones that are; unknown ids are ignored.
  func reorder(to ids: [UUID]) throws
  func clear() throws
}

/// Byte-level storage for the directory's single record.
///
/// Splitting this out is what makes the CRUD and ordering logic below testable:
/// `swift test` has no entitled host app, so a real keychain round-trip is out
/// of reach, but everything that decides *what* gets written is in
/// `ServiceDirectory` and runs against `InMemoryRecordStorage`.
public protocol ServiceRecordStorage: Sendable {
  func read() throws -> Data?
  func write(_ data: Data) throws
  func delete() throws
}

/// Instance records, persisted in the keychain.
///
/// One keychain item holds the whole list rather than an item per instance: a
/// save is then a single atomic write, so a reorder or a delete can't half-apply
/// and leave the list with a gap or a duplicate position.
public struct ServiceDirectory: ServiceDirectoryStoring {
  private let storage: any ServiceRecordStorage

  public init(storage: any ServiceRecordStorage) {
    self.storage = storage
  }

  /// The live directory. `accessGroup` mirrors `KeychainServerStore`'s: the app
  /// passes none, so this record lives in the app's own keychain beside the
  /// Unraid `Server` record, and adding a group means moving both together.
  public static func keychain(
    service: String = "com.cunderw.tower",
    accessGroup: String? = nil
  ) -> ServiceDirectory {
    ServiceDirectory(
      storage: KeychainRecordStorage(
        service: service, account: "services", accessGroup: accessGroup))
  }

  /// Test double, and demo mode's directory — nothing reaches the keychain.
  public static func inMemory(_ instances: [ServiceInstance] = []) -> ServiceDirectory {
    let directory = ServiceDirectory(storage: InMemoryRecordStorage())
    for instance in instances {
      // `InMemoryRecordStorage` has no failure mode and a `ServiceInstance`
      // always encodes, so seeding cannot throw — swallowing here keeps the
      // demo/test call sites from carrying a `try` for an impossible error.
      _ = try? directory.save(instance)
    }
    return directory
  }

  public func instances() throws -> [ServiceInstance] {
    guard let data = try storage.read() else { return [] }
    let records = try JSONDecoder().decode([StoredInstance].self, from: data)
    let stored = records.compactMap(\.instance)
    // Sorting by id after sortOrder only matters for a record hand-edited into
    // a tie; it keeps the order total so the hub can't reshuffle between reads.
    let sorted = stored.sorted {
      ($0.sortOrder, $0.id.uuidString) < ($1.sortOrder, $1.id.uuidString)
    }
    // A dropped record leaves a gap, and the next insert takes `count` as its
    // position, so renumber rather than let it collide with a survivor.
    return stored.count == records.count ? sorted : compacted(sorted)
  }

  /// One element of the stored list.
  ///
  /// A record whose `kind` this build no longer knows (a service an earlier
  /// version supported and this one removed) decodes as `nil` and is dropped,
  /// rather than failing the decode of the whole list. The next write then
  /// leaves it out. Any other malformed record still throws: silently losing a
  /// service this build does support would hide a real fault.
  private struct StoredInstance: Decodable {
    let instance: ServiceInstance?

    private enum CodingKeys: String, CodingKey { case kind }

    init(from decoder: any Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      let rawKind = try container.decode(String.self, forKey: .kind)
      guard ServiceKind(rawValue: rawKind) != nil else {
        instance = nil
        return
      }
      instance = try ServiceInstance(from: decoder)
    }
  }

  @discardableResult
  public func save(_ instance: ServiceInstance) throws -> ServiceInstance {
    var stored = try instances()
    var toStore = instance
    if let existing = stored.firstIndex(where: { $0.id == instance.id }) {
      // Ordering belongs to the directory: an edit sheet round-tripping a stale
      // sortOrder must not silently move the row.
      toStore.sortOrder = stored[existing].sortOrder
      stored[existing] = toStore
    } else {
      toStore.sortOrder = stored.count
      stored.append(toStore)
    }
    try write(stored)
    return toStore
  }

  public func delete(id: UUID) throws {
    let stored = try instances()
    let remaining = stored.filter { $0.id != id }
    guard remaining.count != stored.count else { return }
    try write(compacted(remaining))
  }

  public func reorder(to ids: [UUID]) throws {
    let stored = try instances()
    let byID = Dictionary(uniqueKeysWithValues: stored.map { ($0.id, $0) })
    var ordered = ids.compactMap { byID[$0] }
    let placed = Set(ordered.map(\.id))
    ordered.append(contentsOf: stored.filter { !placed.contains($0.id) })
    try write(compacted(ordered))
  }

  public func clear() throws {
    try storage.delete()
  }

  /// Renumbers to 0..<count, so a delete leaves no gap for the next insert —
  /// which takes `count` as its position — to collide with.
  private func compacted(_ instances: [ServiceInstance]) -> [ServiceInstance] {
    instances.enumerated().map { index, instance in
      var renumbered = instance
      renumbered.sortOrder = index
      return renumbered
    }
  }

  private func write(_ instances: [ServiceInstance]) throws {
    try storage.write(try JSONEncoder().encode(instances))
  }
}

/// Keychain-backed `ServiceRecordStorage`, in the same generic-password shape as
/// `KeychainServerStore` — including its duplicate-item recovery, which the
/// check-then-act pair below can hit whenever two saves race.
struct KeychainRecordStorage: ServiceRecordStorage {
  let service: String
  let account: String
  let accessGroup: String?

  private var baseQuery: [String: Any] {
    var query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
    ]
    if let accessGroup {
      query[kSecAttrAccessGroup as String] = accessGroup
    }
    return query
  }

  func read() throws -> Data? {
    var query = baseQuery
    query[kSecReturnData as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitOne

    var item: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &item)
    switch status {
    case errSecSuccess:
      return item as? Data
    case errSecItemNotFound:
      return nil
    default:
      throw KeychainError.unexpectedStatus(status)
    }
  }

  func write(_ data: Data) throws {
    let status = SecItemCopyMatching(baseQuery as CFDictionary, nil)
    switch status {
    case errSecSuccess:
      try update(with: data)
    case errSecItemNotFound:
      var query = baseQuery
      query[kSecValueData as String] = data
      query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
      let addStatus = SecItemAdd(query as CFDictionary, nil)
      switch addStatus {
      case errSecSuccess:
        return
      case errSecDuplicateItem:
        // The item appeared between the lookup and the add. It exists now, so
        // finish the write rather than reporting a failure for a save that can
        // still succeed.
        try update(with: data)
      default:
        throw KeychainError.unexpectedStatus(addStatus)
      }
    default:
      throw KeychainError.unexpectedStatus(status)
    }
  }

  private func update(with data: Data) throws {
    let attributes = [kSecValueData as String: data]
    let status = SecItemUpdate(baseQuery as CFDictionary, attributes as CFDictionary)
    guard status == errSecSuccess else {
      throw KeychainError.unexpectedStatus(status)
    }
  }

  func delete() throws {
    let status = SecItemDelete(baseQuery as CFDictionary)
    guard status == errSecSuccess || status == errSecItemNotFound else {
      throw KeychainError.unexpectedStatus(status)
    }
  }
}

/// Non-persistent storage for tests and demo mode.
final class InMemoryRecordStorage: ServiceRecordStorage, @unchecked Sendable {
  private let lock = NSLock()
  private var data: Data?

  init(data: Data? = nil) {
    self.data = data
  }

  func read() throws -> Data? { lock.withLock { data } }
  func write(_ newValue: Data) throws { lock.withLock { data = newValue } }
  func delete() throws { lock.withLock { data = nil } }
}
