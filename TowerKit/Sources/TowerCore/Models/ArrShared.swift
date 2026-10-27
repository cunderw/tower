import Foundation

// The domain types the *arr services share. Radarr and Sonarr forge them;
// Lidarr and Prowlarr reuse them. Everything here is plain `TowerCore` — the
// DTOs that produce it stay inside `TowerData`, as with the Apollo types.
//
// **Every field that the API declares nullable is optional here, and every
// enum has an `.unknown` case.** The custom-scalar rule applied to
// REST: a field Tower doesn't recognise degrades that row, never the screen.
// These services ship new enum members between minor versions, and a strict
// decode would turn "Sonarr added a queue status" into "the queue tab is
// broken".

// MARK: - Queue

public enum ArrQueueStatus: String, Sendable, Hashable, CaseIterable {
  case queued, paused, downloading, completed, failed, warning, delay
  case downloadClientUnavailable
  case fallback
  case unknown

  public init(apiValue: String?) {
    self = ArrQueueStatus(rawValue: apiValue ?? "") ?? .unknown
  }

  public var displayName: String {
    switch self {
    case .queued: "Queued"
    case .paused: "Paused"
    case .downloading: "Downloading"
    case .completed: "Completed"
    case .failed: "Failed"
    case .warning: "Warning"
    case .delay: "Delayed"
    case .downloadClientUnavailable: "Client unavailable"
    case .fallback: "Falling back"
    case .unknown: "Unknown"
    }
  }
}

/// What the *arr thinks of an item it is tracking — distinct from the download
/// client's own status. `warning`/`error` here are what "stuck in the queue"
/// actually looks like.
public enum ArrTrackedDownloadStatus: String, Sendable, Hashable {
  case ok, warning, error, unknown

  public init(apiValue: String?) {
    self = ArrTrackedDownloadStatus(rawValue: apiValue ?? "") ?? .unknown
  }
}

public enum ArrTrackedDownloadState: String, Sendable, Hashable {
  case downloading, importBlocked, importPending, importing, imported
  case failedPending, failed, ignored, unknown

  public init(apiValue: String?) {
    self = ArrTrackedDownloadState(rawValue: apiValue ?? "") ?? .unknown
  }

  public var displayName: String {
    switch self {
    case .downloading: "Downloading"
    case .importBlocked: "Import blocked"
    case .importPending: "Waiting to import"
    case .importing: "Importing"
    case .imported: "Imported"
    case .failedPending: "Failing"
    case .failed: "Failed"
    case .ignored: "Ignored"
    case .unknown: "Unknown"
    }
  }
}

/// A release's, queue item's or indexer's download protocol, as the service
/// reports it.
///
/// Kept as the service's own string rather than an enum of every protocol.
/// Tower acts on one value only: usenet, which points a queue row at NZBGet.
/// Any other value is carried as-is, so an indexer edit sends back exactly what
/// Prowlarr sent, and it is shown as nothing.
public struct ArrDownloadProtocol: Sendable, Hashable {
  /// The service's value, verbatim. `nil` when the service sent none.
  public let apiValue: String?

  public init(apiValue: String?) {
    let trimmed = apiValue?.trimmingCharacters(in: .whitespacesAndNewlines)
    self.apiValue = trimmed?.isEmpty == false ? trimmed : nil
  }

  public static let usenet = ArrDownloadProtocol(apiValue: "usenet")
  /// The service sent no protocol.
  public static let unknown = ArrDownloadProtocol(apiValue: nil)

  public var isUsenet: Bool {
    apiValue?.caseInsensitiveCompare("usenet") == .orderedSame
  }

  /// A label for the one protocol Tower names, and `nil` for every other.
  public var displayName: String? { isUsenet ? "Usenet" : nil }
}

/// One item in an *arr's download queue.
public struct ArrQueueItem: Identifiable, Equatable, Sendable {
  public let id: Int
  /// The release title. Optional in the API, and a queue row with no title is
  /// still a row the user may want to remove.
  public let title: String?
  /// The media this belongs to (`movieId` in Radarr, `seriesId` in Sonarr), so
  /// a row can link back to its library entry.
  public let mediaID: Int?
  /// Sonarr only; `nil` on Radarr.
  public let episodeID: Int?
  public let sizeBytes: Int64?
  public let sizeLeftBytes: Int64?
  /// The API's own `timeleft` string (`"00:12:34"`), which is what the *arr UI
  /// shows. Kept as text rather than parsed: it is a display value, and the
  /// services are inconsistent about the format.
  public let timeLeft: String?
  public let estimatedCompletionTime: Date?
  public let status: ArrQueueStatus
  public let trackedStatus: ArrTrackedDownloadStatus
  public let trackedState: ArrTrackedDownloadState
  public let errorMessage: String?
  /// Per-item warnings the *arr attached — "no files found are eligible for
  /// import", and the like.
  public let statusMessages: [String]
  public let downloadProtocol: ArrDownloadProtocol
  public let downloadClient: String?
  /// The download client's own id for this item, such as an NZB id for
  /// NZBGet. It is what lets a queue row point at the same item in the
  /// client's own screen.
  public let downloadID: String?
  public let indexer: String?
  public let quality: String?

  public init(
    id: Int, title: String?, mediaID: Int?, episodeID: Int? = nil,
    sizeBytes: Int64?, sizeLeftBytes: Int64?, timeLeft: String?,
    estimatedCompletionTime: Date?, status: ArrQueueStatus,
    trackedStatus: ArrTrackedDownloadStatus, trackedState: ArrTrackedDownloadState,
    errorMessage: String?, statusMessages: [String], downloadProtocol: ArrDownloadProtocol,
    downloadClient: String?, downloadID: String? = nil, indexer: String?, quality: String?
  ) {
    self.id = id
    self.title = title
    self.mediaID = mediaID
    self.episodeID = episodeID
    self.sizeBytes = sizeBytes
    self.sizeLeftBytes = sizeLeftBytes
    self.timeLeft = timeLeft
    self.estimatedCompletionTime = estimatedCompletionTime
    self.status = status
    self.trackedStatus = trackedStatus
    self.trackedState = trackedState
    self.errorMessage = errorMessage
    self.statusMessages = statusMessages
    self.downloadProtocol = downloadProtocol
    self.downloadClient = downloadClient
    self.downloadID = downloadID.flatMap { $0.isEmpty ? nil : $0 }
    self.indexer = indexer
    self.quality = quality
  }

  public var displayTitle: String { title ?? "Untitled release" }

  /// 0…1, or `nil` when the sizes don't support a figure. Computed rather than
  /// stored because the API sends bytes, and a progress bar built from a
  /// percentage the server rounded disagrees with the sizes shown beside it.
  public var progress: Double? {
    guard let sizeBytes, sizeBytes > 0, let sizeLeftBytes else { return nil }
    return max(0, min(1, Double(sizeBytes - sizeLeftBytes) / Double(sizeBytes)))
  }

  /// Whether this row needs the user's attention — stuck, failed, or blocked
  /// from importing. The queue screen's whole reason to exist.
  public var needsAttention: Bool {
    trackedStatus == .warning || trackedStatus == .error
      || status == .failed || status == .warning
      || trackedState == .importBlocked || trackedState == .failed
  }
}

/// A page of queue items, with the paging figures the API reports.
public struct ArrQueuePage: Equatable, Sendable {
  public let items: [ArrQueueItem]
  public let page: Int
  public let pageSize: Int
  public let totalRecords: Int

  public init(items: [ArrQueueItem], page: Int, pageSize: Int, totalRecords: Int) {
    self.items = items
    self.page = page
    self.pageSize = pageSize
    self.totalRecords = totalRecords
  }

  public var isLastPage: Bool { page * pageSize >= totalRecords }
}

// MARK: - Calendar

/// One upcoming (or recent) release. Deliberately service-agnostic: a Radarr
/// movie, a Sonarr episode, and a Lidarr album all reduce to a titled thing
/// with a date, a monitored flag, and whether the file is already on disk.
public struct ArrCalendarEntry: Identifiable, Equatable, Sendable {
  public let id: Int
  public let title: String
  /// Season/episode for Sonarr, year for Radarr — whatever the row's second
  /// line should read.
  public let subtitle: String?
  public let date: Date?
  public let isMonitored: Bool
  public let hasFile: Bool

  public init(
    id: Int, title: String, subtitle: String?, date: Date?, isMonitored: Bool, hasFile: Bool
  ) {
    self.id = id
    self.title = title
    self.subtitle = subtitle
    self.date = date
    self.isMonitored = isMonitored
    self.hasFile = hasFile
  }
}

// MARK: - History

public enum ArrHistoryEvent: String, Sendable, Hashable {
  case grabbed
  case downloadFolderImported
  case downloadFailed
  case fileDeleted
  case fileRenamed
  case downloadIgnored
  case unknown

  /// Radarr and Sonarr spell the same events differently
  /// (`movieFileDeleted` vs `episodeFileDeleted`), which is exactly the sort of
  /// difference the shared layer exists to absorb.
  public init(apiValue: String?) {
    switch apiValue {
    case "grabbed": self = .grabbed
    case "downloadFolderImported", "movieFolderImported", "seriesFolderImported":
      self = .downloadFolderImported
    case "downloadFailed": self = .downloadFailed
    case "movieFileDeleted", "episodeFileDeleted", "trackFileDeleted", "bookFileDeleted":
      self = .fileDeleted
    case "movieFileRenamed", "episodeFileRenamed", "trackFileRenamed":
      self = .fileRenamed
    case "downloadIgnored": self = .downloadIgnored
    default: self = .unknown
    }
  }

  public var displayName: String {
    switch self {
    case .grabbed: "Grabbed"
    case .downloadFolderImported: "Imported"
    case .downloadFailed: "Download failed"
    case .fileDeleted: "File deleted"
    case .fileRenamed: "File renamed"
    case .downloadIgnored: "Ignored"
    case .unknown: "Unknown"
    }
  }

  public var isFailure: Bool { self == .downloadFailed }
}

public struct ArrHistoryRecord: Identifiable, Equatable, Sendable {
  public let id: Int
  public let event: ArrHistoryEvent
  public let sourceTitle: String?
  public let mediaID: Int?
  public let date: Date?
  public let quality: String?

  public init(
    id: Int, event: ArrHistoryEvent, sourceTitle: String?, mediaID: Int?,
    date: Date?, quality: String?
  ) {
    self.id = id
    self.event = event
    self.sourceTitle = sourceTitle
    self.mediaID = mediaID
    self.date = date
    self.quality = quality
  }

  public var displayTitle: String { sourceTitle ?? event.displayName }
}

public struct ArrHistoryPage: Equatable, Sendable {
  public let records: [ArrHistoryRecord]
  public let page: Int
  public let pageSize: Int
  public let totalRecords: Int

  public init(records: [ArrHistoryRecord], page: Int, pageSize: Int, totalRecords: Int) {
    self.records = records
    self.page = page
    self.pageSize = pageSize
    self.totalRecords = totalRecords
  }

  public var isLastPage: Bool { page * pageSize >= totalRecords }
}

// MARK: - System

public enum ArrHealthSeverity: String, Sendable, Hashable, Comparable {
  case notice, warning, error, unknown

  public init(apiValue: String?) {
    // The API capitalises inconsistently across services and versions.
    self = ArrHealthSeverity(rawValue: (apiValue ?? "").lowercased()) ?? .unknown
  }

  /// Worst first, which is the order the More screen lists them in.
  private var rank: Int {
    switch self {
    case .error: 0
    case .warning: 1
    case .notice: 2
    case .unknown: 3
    }
  }

  public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rank < rhs.rank }
}

public struct ArrHealthCheck: Identifiable, Equatable, Sendable {
  public let id: Int
  public let source: String?
  public let severity: ArrHealthSeverity
  public let message: String
  public let wikiURL: URL?

  public init(id: Int, source: String?, severity: ArrHealthSeverity, message: String, wikiURL: URL?) {
    self.id = id
    self.source = source
    self.severity = severity
    self.message = message
    self.wikiURL = wikiURL
  }
}

public struct ArrDiskSpace: Identifiable, Equatable, Sendable {
  public let path: String
  public let label: String?
  public let freeBytes: Int64
  public let totalBytes: Int64

  public var id: String { path }

  public init(path: String, label: String?, freeBytes: Int64, totalBytes: Int64) {
    self.path = path
    self.label = label
    self.freeBytes = freeBytes
    self.totalBytes = totalBytes
  }

  public var usedBytes: Int64 { max(0, totalBytes - freeBytes) }

  /// 0…1, or `nil` for a total of zero — which the API does report for some
  /// mounts, and which would otherwise divide by zero or draw a full bar.
  public var usedFraction: Double? {
    guard totalBytes > 0 else { return nil }
    return max(0, min(1, Double(usedBytes) / Double(totalBytes)))
  }
}

public struct ArrSystemStatus: Equatable, Sendable {
  public let appName: String?
  public let instanceName: String?
  public let version: String?
  public let osName: String?
  public let osVersion: String?
  public let isDocker: Bool
  public let startTime: Date?

  public init(
    appName: String?, instanceName: String?, version: String?,
    osName: String?, osVersion: String?, isDocker: Bool, startTime: Date?
  ) {
    self.appName = appName
    self.instanceName = instanceName
    self.version = version
    self.osName = osName
    self.osVersion = osVersion
    self.isDocker = isDocker
    self.startTime = startTime
  }
}

public enum ArrCommandStatus: String, Sendable, Hashable {
  case queued, started, completed, failed, aborted, cancelled, orphaned, unknown

  public init(apiValue: String?) {
    self = ArrCommandStatus(rawValue: apiValue ?? "") ?? .unknown
  }

  public var isFinished: Bool {
    switch self {
    case .queued, .started, .unknown: false
    case .completed, .failed, .aborted, .cancelled, .orphaned: true
    }
  }
}

/// A queued or running background command (RSS sync, refresh, search).
public struct ArrCommand: Identifiable, Equatable, Sendable {
  public let id: Int
  public let name: String
  public let status: ArrCommandStatus
  public let message: String?
  public let started: Date?
  public let ended: Date?

  public init(
    id: Int, name: String, status: ArrCommandStatus, message: String?,
    started: Date?, ended: Date?
  ) {
    self.id = id
    self.name = name
    self.status = status
    self.message = message
    self.started = started
    self.ended = ended
  }
}

// MARK: - Pickers

public struct ArrQualityProfile: Identifiable, Equatable, Sendable, Hashable {
  public let id: Int
  public let name: String

  public init(id: Int, name: String) {
    self.id = id
    self.name = name
  }
}

public struct ArrRootFolder: Identifiable, Equatable, Sendable, Hashable {
  public let id: Int
  public let path: String
  public let isAccessible: Bool
  public let freeBytes: Int64?

  public init(id: Int, path: String, isAccessible: Bool, freeBytes: Int64?) {
    self.id = id
    self.path = path
    self.isAccessible = isAccessible
    self.freeBytes = freeBytes
  }
}

public struct ArrTag: Identifiable, Equatable, Sendable, Hashable {
  public let id: Int
  public let label: String

  public init(id: Int, label: String) {
    self.id = id
    self.label = label
  }
}

// MARK: - Releases

/// One release from an interactive search, as every *arr reports them.
///
/// Shared rather than per-service: the columns a user picks a release by —
/// quality, size, indexer, and why it was rejected — are identical
/// across Radarr, Sonarr, and Lidarr, and one release screen serves all three.
public struct ArrRelease: Identifiable, Equatable, Sendable {
  /// The indexer's own guid. Releases have no server-side id until grabbed,
  /// and two indexers can offer the same title.
  public let id: String
  public let title: String
  public let indexer: String?
  public let indexerID: Int?
  public let quality: String?
  public let sizeBytes: Int64
  public let downloadProtocol: ArrDownloadProtocol
  public let publishDate: Date?
  public let ageHours: Double?
  /// Radarr/Sonarr have already decided whether they'd take this release.
  public let isApproved: Bool
  /// Why not, when they wouldn't. Shown verbatim: these are the service's own
  /// words and the reason a user overrides or moves on.
  public let rejections: [String]

  public init(
    id: String, title: String, indexer: String?, indexerID: Int?, quality: String?,
    sizeBytes: Int64, downloadProtocol: ArrDownloadProtocol,
    publishDate: Date?, ageHours: Double?, isApproved: Bool, rejections: [String]
  ) {
    self.id = id
    self.title = title
    self.indexer = indexer
    self.indexerID = indexerID
    self.quality = quality
    self.sizeBytes = sizeBytes
    self.downloadProtocol = downloadProtocol
    self.publishDate = publishDate
    self.ageHours = ageHours
    self.isApproved = isApproved
    self.rejections = rejections
  }
}

/// What a detail screen's File section can honestly say.
///
/// `hasFile` and the file details arrive from the service *independently* —
/// Sonarr omits `episodeFile` from `api/v3/episode` unless the request asks for
/// it — so the two can disagree, and a screen that reads "no details" as "no
/// file" ends up printing "No file on disk." directly under "On disk: Yes".
/// Deriving every state from both inputs leaves that contradiction no
/// way to render, whatever a future service decides to omit.
public enum ArrFileSection: Equatable, Sendable {
  /// The details arrived — render them.
  case details
  /// The service says a file exists but sent no details for it.
  case onDiskWithoutDetails
  /// No file, and the item is out, so a search can succeed.
  case missing
  /// No file, and it isn't out yet, so a search can only fail.
  case notYetAvailable

  /// Whether this state asserts a file is on the array. The status label reads
  /// "Downloaded" for exactly these two, so the label and the file section
  /// always agree.
  public var claimsAFileExists: Bool {
    switch self {
    case .details, .onDiskWithoutDetails: true
    case .missing, .notYetAvailable: false
    }
  }

  /// One rule for both screens — details, then the flag, then whether the item
  /// is out — written once so Radarr and Sonarr cannot drift apart.
  static func resolve(hasFile: Bool, hasDetails: Bool, isOut: Bool) -> ArrFileSection {
    if hasDetails { return .details }
    if hasFile { return .onDiskWithoutDetails }
    return isOut ? .missing : .notYetAvailable
  }
}
