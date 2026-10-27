import Foundation

/// One of the eight media-stack services Tower manages.
///
/// The raw values are the keychain record's on-disk representation, so they are
/// stable identifiers rather than display strings — renaming a case is free,
/// changing a raw value strands stored instances.
public enum ServiceKind: String, CaseIterable, Codable, Sendable, Hashable {
  case bazarr
  case lidarr
  case overseerr
  case prowlarr
  case radarr
  case sonarr
  case nzbget
  case tautulli

  public var displayName: String {
    switch self {
    case .bazarr: "Bazarr"
    case .lidarr: "Lidarr"
    case .overseerr: "Overseerr"
    case .prowlarr: "Prowlarr"
    case .radarr: "Radarr"
    case .sonarr: "Sonarr"
    case .nzbget: "NZBGet"
    case .tautulli: "Tautulli"
    }
  }

  /// The hub's grouping: the section the service's row appears under.
  public var category: ServiceCategory {
    switch self {
    case .bazarr, .lidarr, .radarr, .sonarr: .mediaManagement
    case .overseerr, .prowlarr: .requestsAndIndexers
    case .nzbget: .downloads
    case .tautulli: .monitoring
    }
  }
}

/// Which credentials a service takes.
///
/// A domain fact, not a transport one: it decides which fields the add- and
/// edit-service forms show, so that no form can ever offer a field the service
/// has no use for. `ServiceAuthStyle` in `TowerData` is the separate question of
/// how those credentials go on the wire.
public enum ServiceCredentialStyle: Equatable, Sendable {
  case apiKey
  case usernamePassword
}

extension ServiceKind {
  public var credentialStyle: ServiceCredentialStyle {
    switch self {
    case .radarr, .sonarr, .lidarr, .prowlarr, .bazarr, .overseerr, .tautulli: .apiKey
    case .nzbget: .usernamePassword
    }
  }
}

/// How the hub groups configured instances. `allCases` order is display order.
public enum ServiceCategory: String, CaseIterable, Codable, Sendable, Hashable {
  case mediaManagement
  case requestsAndIndexers
  case downloads
  case monitoring

  public var displayName: String {
    switch self {
    case .mediaManagement: "Media management"
    case .requestsAndIndexers: "Requests & indexers"
    case .downloads: "Downloads"
    case .monitoring: "Monitoring"
    }
  }
}

/// What a service accepts to authenticate.
///
/// An enum rather than a pair of optional fields: the *arrs, Overseerr, and
/// Tautulli take an API key, while NZBGet takes a username and password,
/// and no service takes both. Optional fields would let an instance
/// exist with neither, or with a half-filled login, and push that impossible
/// state into every client.
public enum ServiceCredentials: Equatable, Hashable, Sendable, Codable {
  case apiKey(String)
  case usernamePassword(username: String, password: String)

  private enum CodingKeys: String, CodingKey {
    case type, key, username, password
  }

  private enum Tag: String, Codable {
    case apiKey, usernamePassword
  }

  /// Hand-written rather than synthesized: this is a persisted format, and the
  /// synthesized enum coding (`{"apiKey":{"_0":…}}`) is both compiler-owned and
  /// unreadable in a keychain dump.
  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    switch try container.decode(Tag.self, forKey: .type) {
    case .apiKey:
      self = .apiKey(try container.decode(String.self, forKey: .key))
    case .usernamePassword:
      self = .usernamePassword(
        username: try container.decode(String.self, forKey: .username),
        password: try container.decode(String.self, forKey: .password)
      )
    }
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    switch self {
    case .apiKey(let key):
      try container.encode(Tag.apiKey, forKey: .type)
      try container.encode(key, forKey: .key)
    case .usernamePassword(let username, let password):
      try container.encode(Tag.usernamePassword, forKey: .type)
      try container.encode(username, forKey: .username)
      try container.encode(password, forKey: .password)
    }
  }
}

/// A single configured service — one Radarr, one NZBGet, one of two
/// Sonarrs. Multi-instance is a data-model property from day one, so nothing
/// downstream ever assumes a kind maps to exactly one server.
public struct ServiceInstance: Identifiable, Equatable, Hashable, Sendable, Codable {
  public let id: UUID
  public var kind: ServiceKind
  /// User-facing label, e.g. "Radarr 4K". Not required to be unique.
  public var name: String
  public var baseURL: URL
  public var credentials: ServiceCredentials
  /// Extra headers sent on every request — reverse-proxy auth and the like.
  public var customHeaders: [String: String]
  /// A disabled instance keeps its configuration but is hidden from the hub.
  public var isEnabled: Bool
  /// Position in the hub list. Assigned by `ServiceDirectory`, not by callers.
  public var sortOrder: Int

  public init(
    id: UUID = UUID(),
    kind: ServiceKind,
    name: String,
    baseURL: URL,
    credentials: ServiceCredentials,
    customHeaders: [String: String] = [:],
    isEnabled: Bool = true,
    sortOrder: Int = 0
  ) {
    self.id = id
    self.kind = kind
    self.name = name
    self.baseURL = baseURL
    self.credentials = credentials
    self.customHeaders = customHeaders
    self.isEnabled = isEnabled
    self.sortOrder = sortOrder
  }

  /// Decoding tolerates a missing `customHeaders` or `isEnabled`, so a record
  /// written before either existed still loads. A throwing decode here would
  /// take out the user's entire service list, not one field.
  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      id: try container.decode(UUID.self, forKey: .id),
      kind: try container.decode(ServiceKind.self, forKey: .kind),
      name: try container.decode(String.self, forKey: .name),
      baseURL: try container.decode(URL.self, forKey: .baseURL),
      credentials: try container.decode(ServiceCredentials.self, forKey: .credentials),
      customHeaders: try container.decodeIfPresent(
        [String: String].self, forKey: .customHeaders) ?? [:],
      isEnabled: try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true,
      sortOrder: try container.decode(Int.self, forKey: .sortOrder)
    )
  }
}
