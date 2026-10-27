import Foundation

// NZBGet's domain types. Plain `TowerCore`, like every other service —
// **nothing here says JSON-RPC**: the transport is a `TowerData` detail and a
// view that could tell would be a layering leak.
//
// Same tolerance rule as the rest: every enum has an `.unknown` case and every
// nullable field is optional.

/// NZBGet's queue priority, which is an open integer scale with five named
/// stops. Kept as named cases because those are what its own UI offers, with
/// the raw value preserved so an unusual number set elsewhere survives a round
/// trip instead of being snapped to Normal.
public enum NZBPriority: Sendable, Hashable {
  case veryLow
  case low
  case normal
  case high
  case veryHigh
  case force
  /// A value NZBGet accepts but doesn't name.
  case custom(Int)

  public init(rawValue: Int) {
    switch rawValue {
    case -100: self = .veryLow
    case -50: self = .low
    case 0: self = .normal
    case 50: self = .high
    case 100: self = .veryHigh
    case 900: self = .force
    default: self = .custom(rawValue)
    }
  }

  public var rawValue: Int {
    switch self {
    case .veryLow: -100
    case .low: -50
    case .normal: 0
    case .high: 50
    case .veryHigh: 100
    case .force: 900
    case .custom(let value): value
    }
  }

  public var displayName: String {
    switch self {
    case .veryLow: "Very low"
    case .low: "Low"
    case .normal: "Normal"
    case .high: "High"
    case .veryHigh: "Very high"
    case .force: "Force"
    case .custom(let value): "Priority \(value)"
    }
  }

  /// The stops offered in a picker. `custom` is deliberately absent — it exists
  /// to *preserve* a value, not to let one be invented.
  public static let selectable: [NZBPriority] = [.veryLow, .low, .normal, .high, .veryHigh, .force]
}

/// What NZBGet is doing with a queue group.
public enum NZBGroupStatus: String, Sendable, Hashable {
  case queued = "QUEUED"
  case paused = "PAUSED"
  case downloading = "DOWNLOADING"
  case fetching = "FETCHING"
  case postQueued = "PP_QUEUED"
  case loadingPars = "LOADING_PARS"
  case verifyingSources = "VERIFYING_SOURCES"
  case repairing = "REPAIRING"
  case verifyingRepaired = "VERIFYING_REPAIRED"
  case renaming = "RENAMING"
  case unpacking = "UNPACKING"
  case moving = "MOVING"
  case executingScript = "EXECUTING_SCRIPT"
  case postFinished = "PP_FINISHED"
  case unknown

  public init(apiValue: String?) {
    self = NZBGroupStatus(rawValue: apiValue ?? "") ?? .unknown
  }

  public var isPaused: Bool { self == .paused }

  /// Everything after the bytes have arrived — par2, unpack, scripts. Worth
  /// distinguishing because a group in this phase has no download speed and
  /// showing "0 B/s" next to it reads as stalled rather than as busy.
  public var isPostProcessing: Bool {
    switch self {
    case .postQueued, .loadingPars, .verifyingSources, .repairing, .verifyingRepaired,
      .renaming, .unpacking, .moving, .executingScript, .postFinished:
      true
    default:
      false
    }
  }

  public var displayName: String {
    switch self {
    case .queued: "Queued"
    case .paused: "Paused"
    case .downloading: "Downloading"
    case .fetching: "Fetching"
    case .postQueued: "Waiting to process"
    case .loadingPars: "Loading PARs"
    case .verifyingSources: "Verifying"
    case .repairing: "Repairing"
    case .verifyingRepaired: "Verifying repair"
    case .renaming: "Renaming"
    case .unpacking: "Unpacking"
    case .moving: "Moving"
    case .executingScript: "Running script"
    case .postFinished: "Processing done"
    case .unknown: "Unknown"
    }
  }
}

/// One entry in NZBGet's download queue.
public struct NZBGroup: Sendable, Hashable, Identifiable {
  public let id: Int
  public let name: String
  public let status: NZBGroupStatus
  public let category: String?
  public let sizeBytes: Int64
  public let remainingBytes: Int64
  public let downloadedBytes: Int64
  public let priority: NZBPriority
  /// NZBGet reports health as an integer per mille (1000 = 100%). Converted to
  /// a fraction here so the UI never has to know that.
  public let health: Double?
  public let activeDownloads: Int
  /// Estimated seconds remaining, derived from the server's current rate —
  /// NZBGet does not send a per-group ETA.
  public var estimatedSecondsRemaining: TimeInterval?

  public var progress: Double {
    guard sizeBytes > 0 else { return 0 }
    return Double(sizeBytes - remainingBytes) / Double(sizeBytes)
  }

  public init(
    id: Int, name: String, status: NZBGroupStatus, category: String?, sizeBytes: Int64,
    remainingBytes: Int64, downloadedBytes: Int64, priority: NZBPriority, health: Double?,
    activeDownloads: Int, estimatedSecondsRemaining: TimeInterval? = nil
  ) {
    self.id = id
    self.name = name
    self.status = status
    self.category = category
    self.sizeBytes = sizeBytes
    self.remainingBytes = remainingBytes
    self.downloadedBytes = downloadedBytes
    self.priority = priority
    self.health = health
    self.activeDownloads = activeDownloads
    self.estimatedSecondsRemaining = estimatedSecondsRemaining
  }
}

/// A finished item.
public struct NZBHistoryItem: Sendable, Hashable, Identifiable {
  public let id: Int
  public let name: String
  /// NZBGet's own compound status, e.g. `SUCCESS/ALL` or `FAILURE/PAR`. Kept
  /// verbatim alongside the boolean, because "which part failed" is the thing
  /// worth reading and any rewording loses it.
  public let status: String
  public let isSuccess: Bool
  public let category: String?
  public let sizeBytes: Int64
  public let completedAt: Date?
  public let downloadSeconds: TimeInterval?

  public init(
    id: Int, name: String, status: String, isSuccess: Bool, category: String?, sizeBytes: Int64,
    completedAt: Date?, downloadSeconds: TimeInterval?
  ) {
    self.id = id
    self.name = name
    self.status = status
    self.isSuccess = isSuccess
    self.category = category
    self.sizeBytes = sizeBytes
    self.completedAt = completedAt
    self.downloadSeconds = downloadSeconds
  }
}

/// The server-wide figures.
public struct NZBServerStatus: Sendable, Hashable {
  public let downloadRateBytesPerSecond: Int64
  public let remainingBytes: Int64
  public let downloadedBytes: Int64
  public let freeDiskSpaceBytes: Int64
  public let isDownloadPaused: Bool
  /// Global rate cap in bytes/second; `nil` when unlimited.
  public let speedLimitBytesPerSecond: Int64?
  public let uptime: TimeInterval?
  public let postJobCount: Int
  public let version: String?

  public init(
    downloadRateBytesPerSecond: Int64, remainingBytes: Int64, downloadedBytes: Int64,
    freeDiskSpaceBytes: Int64, isDownloadPaused: Bool, speedLimitBytesPerSecond: Int64?,
    uptime: TimeInterval?, postJobCount: Int, version: String?
  ) {
    self.downloadRateBytesPerSecond = downloadRateBytesPerSecond
    self.remainingBytes = remainingBytes
    self.downloadedBytes = downloadedBytes
    self.freeDiskSpaceBytes = freeDiskSpaceBytes
    self.isDownloadPaused = isDownloadPaused
    self.speedLimitBytesPerSecond = speedLimitBytesPerSecond
    self.uptime = uptime
    self.postJobCount = postJobCount
    self.version = version
  }
}
