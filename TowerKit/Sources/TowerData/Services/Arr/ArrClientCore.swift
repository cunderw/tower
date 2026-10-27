import Foundation
import TowerCore

/// The *arr v3 surface Radarr and Sonarr share — and that Lidarr and Prowlarr
/// reuse at their own API version.
///
/// Queue, calendar, history, health, disk space, system status, commands,
/// quality profiles, root folders, and tags are the same endpoints with the
/// same shapes across Radarr, Sonarr and Lidarr. Only the media types differ,
/// and those live in each service's own client. Prowlarr shares health, system
/// status and commands.
///
/// **The API version is a parameter, not a constant.** Radarr and Sonarr are
/// `api/v3`; Prowlarr and Lidarr are `api/v1`. Getting that wrong produces a
/// 404 whose message looks like a wrong address, so it is set once here per
/// service rather than spelled into every call site.
public struct ArrClientCore: Sendable {
  private let client: ServiceHTTPClient
  private let apiPath: String

  public init(client: ServiceHTTPClient, apiPath: String = "api/v3") {
    self.client = client
    self.apiPath = apiPath
  }

  private func path(_ endpoint: String) -> String { "\(apiPath)/\(endpoint)" }

  // MARK: - Queue

  /// One page of the download queue.
  ///
  /// `includeUnknownItems` is on because the *arr default hides items it can't
  /// match to a library entry — which is precisely the stuck download a user
  /// opens this screen to find.
  public func queue(
    page: Int = 1,
    pageSize: Int = 50,
    includeUnknownItems: Bool = true
  ) async throws -> ArrQueuePage {
    let dto: QueuePageDTO = try await client.send(
      path("queue"),
      query: [
        URLQueryItem(name: "page", value: String(page)),
        URLQueryItem(name: "pageSize", value: String(pageSize)),
        URLQueryItem(name: "includeUnknownMovieItems", value: String(includeUnknownItems)),
        URLQueryItem(name: "includeUnknownSeriesItems", value: String(includeUnknownItems)),
        URLQueryItem(name: "includeUnknownArtistItems", value: String(includeUnknownItems)),
      ],
      as: QueuePageDTO.self)
    return dto.domain
  }

  /// Removes a queue item.
  ///
  /// Both flags are the user's decision and neither has a safe default worth
  /// hiding: `removeFromClient` deletes the download itself, and `blocklist`
  /// stops the same release being grabbed again five minutes later — which is
  /// the entire point of removing a stuck one.
  public func removeQueueItem(
    id: Int, removeFromClient: Bool = true, blocklist: Bool = false
  ) async throws {
    try await client.send(
      path("queue/\(id)"),
      method: .delete,
      query: [
        URLQueryItem(name: "removeFromClient", value: String(removeFromClient)),
        URLQueryItem(name: "blocklist", value: String(blocklist)),
      ])
  }

  // MARK: - Calendar

  public func calendar(start: Date, end: Date) async throws -> [ArrCalendarEntry] {
    let dtos: [CalendarEntryDTO] = try await client.send(
      path("calendar"),
      query: [
        URLQueryItem(name: "start", value: Self.dayFormatter.string(from: start)),
        URLQueryItem(name: "end", value: Self.dayFormatter.string(from: end)),
        URLQueryItem(name: "unmonitored", value: "true"),
      ],
      as: [CalendarEntryDTO].self)
    return dtos.map(\.domain)
  }

  // MARK: - History

  public func history(page: Int = 1, pageSize: Int = 50) async throws -> ArrHistoryPage {
    let dto: HistoryPageDTO = try await client.send(
      path("history"),
      query: [
        URLQueryItem(name: "page", value: String(page)),
        URLQueryItem(name: "pageSize", value: String(pageSize)),
        URLQueryItem(name: "sortKey", value: "date"),
        URLQueryItem(name: "sortDirection", value: "descending"),
      ],
      as: HistoryPageDTO.self)
    return dto.domain
  }

  // MARK: - System

  public func health() async throws -> [ArrHealthCheck] {
    let dtos: [HealthDTO] = try await client.send(path("health"), as: [HealthDTO].self)
    // Worst first: the More screen's job is to surface the error, not to
    // preserve the order the server happened to check things in.
    return dtos.map(\.domain).sorted { $0.severity < $1.severity }
  }

  public func diskSpace() async throws -> [ArrDiskSpace] {
    let dtos: [DiskSpaceDTO] = try await client.send(path("diskspace"), as: [DiskSpaceDTO].self)
    return dtos.map(\.domain)
  }

  public func systemStatus() async throws -> ArrSystemStatus {
    try await client.send(path("system/status"), as: SystemStatusDTO.self).domain
  }

  /// Commands currently queued or running.
  public func commands() async throws -> [ArrCommand] {
    let dtos: [CommandDTO] = try await client.send(path("command"), as: [CommandDTO].self)
    return dtos.map(\.domain)
  }

  /// Starts a background command by name (`RssSync`, `RefreshMovie`, …) and
  /// returns it, so a caller can follow its status.
  @discardableResult
  public func runCommand(
    _ name: String, parameters: [String: CommandParameter] = [:]
  ) async throws -> ArrCommand {
    var body: [String: CommandParameter] = ["name": .string(name)]
    for (key, value) in parameters {
      body[key] = value
    }
    return try await client.send(
      path("command"), method: .post, body: body, as: CommandDTO.self
    ).domain
  }

  // MARK: - Pickers

  public func qualityProfiles() async throws -> [ArrQualityProfile] {
    let dtos: [QualityProfileDTO] = try await client.send(
      path("qualityprofile"), as: [QualityProfileDTO].self)
    return dtos.map(\.domain)
  }

  public func rootFolders() async throws -> [ArrRootFolder] {
    let dtos: [RootFolderDTO] = try await client.send(
      path("rootfolder"), as: [RootFolderDTO].self)
    return dtos.map(\.domain)
  }

  public func tags() async throws -> [ArrTag] {
    let dtos: [TagDTO] = try await client.send(path("tag"), as: [TagDTO].self)
    return dtos.map(\.domain)
  }

  /// The *arr calendar endpoint takes plain dates, not timestamps.
  private static let dayFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter
  }()
}

/// The shared *arr surface, as a seam.
///
/// Every *arr repository can answer these, and the live ones do it by
/// delegating to `ArrClientCore`. It exists as a protocol so a demo or test
/// conformance can answer them **without** an `ArrClientCore` — which is backed
/// by a real `URLSession` and would otherwise sit on a 30-second timeout
/// against an address that doesn't route. That is not hypothetical: without
/// this seam, the add-service sheet's pickers sit on exactly that timeout.
public protocol ArrPickerSource: Sendable {
  func qualityProfiles() async throws -> [ArrQualityProfile]
  func rootFolders() async throws -> [ArrRootFolder]
  func tags() async throws -> [ArrTag]

  // The shell's shared sections: queue, calendar, history, and the More
  // screen, all through the same seam.
  func queue() async throws -> ArrQueuePage
  func removeQueueItem(id: Int, removeFromClient: Bool, blocklist: Bool) async throws
  func calendar(start: Date, end: Date) async throws -> [ArrCalendarEntry]
  func history(page: Int) async throws -> ArrHistoryPage
  func health() async throws -> [ArrHealthCheck]
  func diskSpace() async throws -> [ArrDiskSpace]
  func systemStatus() async throws -> ArrSystemStatus
  @discardableResult
  func runCommand(_ name: String) async throws -> ArrCommand
}

/// A command body value. The endpoint takes a name plus arbitrary
/// command-specific fields — `movieId`, `seriesId`, and the plural
/// `movieIds`/`episodeIds` arrays — and this is the smallest thing that encodes
/// all of them without an `Any`.
public enum CommandParameter: Encodable, Sendable {
  case string(String)
  case int(Int)
  case ints([Int])

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    switch self {
    case .string(let value): try container.encode(value)
    case .int(let value): try container.encode(value)
    case .ints(let values): try container.encode(values)
    }
  }
}
