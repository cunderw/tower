import Foundation
import Security
import TowerCore

public protocol ServerStoring: Sendable {
  func save(_ server: Server) throws
  func load() throws -> Server?
  func clear() throws
}

public enum KeychainError: Error, Equatable {
  case unexpectedStatus(OSStatus)
}

/// Stores the connection record in the keychain.
///
/// `accessGroup` exists so a widget extension could share this item. Tower has
/// no widget, and the app passes no group, so the item lives in the app's own
/// keychain. Adding a group later means moving every existing user's entry,
/// the same as `ServiceDirectory.keychain`.
public struct KeychainServerStore: ServerStoring {
  private let service: String
  private let account = "server"
  private let accessGroup: String?

  public init(service: String = "com.cunderw.tower", accessGroup: String? = nil) {
    self.service = service
    self.accessGroup = accessGroup
  }

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

  /// Stores `server`, replacing any credential already held.
  ///
  /// **`errSecDuplicateItem` from `SecItemAdd` is handled, not thrown.** The
  /// check-then-act shape below — `SecItemCopyMatching`, then add or
  /// update — is two non-atomic calls, so two concurrent saves can both observe
  /// `errSecItemNotFound`, both call `SecItemAdd`, and the loser gets
  /// `errSecDuplicateItem`. Surfacing that as an opaque `.unexpectedStatus(-25299)`
  /// would tell a user their credential failed to save when the item is in fact
  /// there.
  ///
  /// Today's UI cannot reach it — `ConnectView`'s submit button is disabled while
  /// `state.isLoading`, so a double-tap can't start two saves — but that guard is
  /// incidental to the *UI*, not to this store. A widget refresh, an App Intent,
  /// or a future settings-screen edit reintroduces it, and this is the one place
  /// that can be sure.
  ///
  /// Retrying as an update rather than looping: the duplicate means the item now
  /// exists, so the correct next action is exactly what the `errSecSuccess` branch
  /// does. That converges in one step and cannot spin.
  public func save(_ server: Server) throws {
    let data = try JSONEncoder().encode(server)
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
        // Something else added it between the lookup and here. The item exists,
        // so finish the job rather than reporting a failure for a save that can
        // still succeed.
        try update(with: data)
      default:
        throw KeychainError.unexpectedStatus(addStatus)
      }
    default:
      throw KeychainError.unexpectedStatus(status)
    }
  }

  /// The update half of `save`, shared by the found branch and the
  /// duplicate-recovery branch.
  private func update(with data: Data) throws {
    let update = [kSecValueData as String: data]
    let updateStatus = SecItemUpdate(baseQuery as CFDictionary, update as CFDictionary)
    guard updateStatus == errSecSuccess else {
      throw KeychainError.unexpectedStatus(updateStatus)
    }
  }

  public func load() throws -> Server? {
    var query = baseQuery
    query[kSecReturnData as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitOne

    var item: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &item)
    switch status {
    case errSecSuccess:
      guard let data = item as? Data else { return nil }
      return try JSONDecoder().decode(Server.self, from: data)
    case errSecItemNotFound:
      return nil
    default:
      throw KeychainError.unexpectedStatus(status)
    }
  }

  public func clear() throws {
    let status = SecItemDelete(baseQuery as CFDictionary)
    guard status == errSecSuccess || status == errSecItemNotFound else {
      throw KeychainError.unexpectedStatus(status)
    }
  }
}

/// Test double. Demo mode also uses it.
public final class InMemoryServerStore: ServerStoring, @unchecked Sendable {
  private let lock = NSLock()
  private var stored: Server?

  public init(stored: Server? = nil) {
    self.stored = stored
  }

  public func save(_ server: Server) throws {
    lock.withLock { stored = server }
  }

  public func load() throws -> Server? {
    lock.withLock { stored }
  }

  public func clear() throws {
    lock.withLock { stored = nil }
  }
}
