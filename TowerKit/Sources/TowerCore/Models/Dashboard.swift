import Foundation

/// Unraid's `ParityCheckStatus` enum, plus an `.unknown` escape hatch so a
/// server-side addition degrades instead of failing to decode.
public enum ParityCheckState: String, Equatable, Sendable {
  case neverRun = "NEVER_RUN"
  case running = "RUNNING"
  case paused = "PAUSED"
  case completed = "COMPLETED"
  case cancelled = "CANCELLED"
  case failed = "FAILED"
  case unknown

  public init(rawValue: String) {
    self = switch rawValue {
    case "NEVER_RUN": .neverRun
    case "RUNNING": .running
    case "PAUSED": .paused
    case "COMPLETED": .completed
    case "CANCELLED": .cancelled
    case "FAILED": .failed
    default: .unknown
    }
  }
}

public struct ParityStatus: Equatable, Sendable {
  public let state: ParityCheckState
  /// 0-100 as the server reports it; `progressFraction` converts for gauges.
  public let progressPercent: Int?
  public let errors: Int?
  /// Free-form MB/s string as sent (Unraid sends `"0"` when idle).
  public let speed: String?
  /// ISO-8601 timestamp of the last completed check.
  public let lastRunTimestamp: String?
  public let durationSeconds: Int?
  public let correcting: Bool

  public init(
    state: ParityCheckState, progressPercent: Int?, errors: Int?,
    speed: String?, lastRunTimestamp: String?, durationSeconds: Int?, correcting: Bool
  ) {
    self.state = state
    self.progressPercent = progressPercent
    self.errors = errors
    self.speed = speed
    self.lastRunTimestamp = lastRunTimestamp
    self.durationSeconds = durationSeconds
    self.correcting = correcting
  }

  /// Whether a check is in flight. Derived from `state` alone: the boolean
  /// `running`/`paused` fields arrive as null on an idle server, so treating
  /// them as the source of truth would make `nil` indistinguishable from
  /// `false` and read as "not running" even mid-check on a server that
  /// omits them.
  public var isActive: Bool { state == .running || state == .paused }

  public var progressFraction: Double? {
    guard let progressPercent else { return nil }
    return min(1, max(0, Double(progressPercent) / 100))
  }
}

/// One `ParityCheckMutations` action. Start also takes a correct-or-check-only
/// choice, which the store passes alongside it; see `DashboardStore.perform`.
public enum ParityAction: Hashable, Sendable, CaseIterable {
  case start, pause, resume, cancel

  /// The verb as it appears on a button. "Cancel Check", not "Cancel": the
  /// confirmation dialog has a dismiss button of its own, and two buttons
  /// labelled "Cancel" that do opposite things is a trap.
  public var title: String {
    switch self {
    case .start: "Start Check"
    case .pause: "Pause"
    case .resume: "Resume"
    case .cancel: "Cancel Check"
    }
  }

  /// A stable slug for accessibility identifiers, `parity.action.cancel`. Not
  /// derived from `title`, so a copy change cannot repoint a UI test.
  public var identifier: String {
    switch self {
    case .start: "start"
    case .pause: "pause"
    case .resume: "resume"
    case .cancel: "cancel"
    }
  }
}

extension ParityStatus {
  /// The actions that apply to this check right now, in display order.
  ///
  /// - Start: only when no check is in flight, the array is started, and the
  ///   array has a parity disk. Unraid refuses a check on a stopped array, and
  ///   an array with no parity disk has nothing to check.
  /// - Pause and Cancel: a running check.
  /// - Resume and Cancel: a paused check.
  /// - Nothing for `.unknown`: a state Tower cannot read gets no button that
  ///   assumes one.
  public func availableActions(arrayStarted: Bool, hasParityDisks: Bool) -> [ParityAction] {
    switch state {
    case .running: [.pause, .cancel]
    case .paused: [.resume, .cancel]
    case .neverRun, .completed, .cancelled, .failed:
      arrayStarted && hasParityDisks ? [.start] : []
    case .unknown: []
    }
  }
}

extension DashboardSnapshot {
  /// `ParityStatus.availableActions` for this snapshot's array.
  public var availableParityActions: [ParityAction] {
    parity.availableActions(arrayStarted: array.isStarted, hasParityDisks: !array.parities.isEmpty)
  }
}

/// One row of `Query.parityHistory`: a past check.
public struct ParityCheckRecord: Equatable, Sendable, Identifiable {
  /// The row's position in the sorted history. The server sends no ID, and two
  /// rows can share every field.
  public let id: Int
  /// `nil` when the server's timestamp does not parse, or is the Unix epoch:
  /// Unraid writes 1970-01-01 for a history line it could not date.
  public let date: Date?
  public let durationSeconds: Int?
  /// Free-form, as sent ("133.1 MB/s"). See `speedText`.
  public let speed: String?
  public let state: ParityCheckState
  /// `nil` when the server could not report a count. Unraid nulls a NaN.
  public let errors: Int?

  public init(id: Int, date: Date?, durationSeconds: Int?, speed: String?, state: ParityCheckState, errors: Int?) {
    self.id = id
    self.date = date
    self.durationSeconds = durationSeconds
    self.speed = speed
    self.state = state
    self.errors = errors
  }

  /// The speed to show, or `nil` when the server sent no real reading. Unraid
  /// writes "Unavailable" for a check that never measured one, "nan B/s" for a
  /// zero-length check, and "0" while idle.
  public var speedText: String? {
    guard let speed = speed?.trimmingCharacters(in: .whitespaces), !speed.isEmpty, speed != "0",
          speed.caseInsensitiveCompare("Unavailable") != .orderedSame,
          !speed.lowercased().hasPrefix("nan")
    else { return nil }
    return speed
  }
}

extension ParityCheckState {
  /// The state as a history row or the status line shows it.
  public var displayName: String {
    switch self {
    case .neverRun: "Never run"
    case .running: "Running"
    case .paused: "Paused"
    case .completed: "Completed"
    case .cancelled: "Cancelled"
    case .failed: "Failed"
    case .unknown: "Unknown"
    }
  }
}

public struct ServiceCounts: Equatable, Sendable {
  /// `nil` means Docker reporting is unavailable — the Docker service is
  /// disabled or stopped, and its counts query failed — not "zero containers".
  /// `Docker.containers` is non-null in the schema, so the server cannot say
  /// this with a null list the way it does for VMs: its resolver throws
  /// ("Docker socket unavailable.") and the dashboard's separate counts query
  /// fails instead. A healthy server with no containers reports `0`/`0`; only
  /// a failed reading reports `nil`/`nil`. See `containersSummary`.
  public let containersRunning: Int?
  public let containersTotal: Int?
  /// `nil` means VM reporting is unavailable — libvirt stopped, errored, or
  /// otherwise not returning `vms.domains` — not "zero VMs configured". The
  /// server reports that as a null `domains` (a nullable list in the schema,
  /// `[VmDomain!]`) alongside an error, and the dashboard's VM counts query
  /// treats either as unavailable. A healthy server with no VMs defined
  /// reports `0`/`0`; only an actually-missing reading reports `nil`/`nil`.
  /// See `vmsSummary`.
  public let vmsRunning: Int?
  public let vmsTotal: Int?
  public let sharesTotal: Int

  public init(
    containersRunning: Int?, containersTotal: Int?,
    vmsRunning: Int?, vmsTotal: Int?,
    sharesTotal: Int
  ) {
    self.containersRunning = containersRunning
    self.containersTotal = containersTotal
    self.vmsRunning = vmsRunning
    self.vmsTotal = vmsTotal
    self.sharesTotal = sharesTotal
  }

  /// "Unavailable" rather than "0 of 0 running" when the counts are nil, for
  /// the reason `vmsSummary` gives.
  public var containersSummary: String {
    guard let containersRunning, let containersTotal else { return "Unavailable" }
    return "\(containersRunning) of \(containersTotal) running"
  }

  /// "Unavailable" rather than "0 of 0 running" when `vmsRunning`/`vmsTotal`
  /// are nil — the latter is exactly what a healthy, VM-less server also
  /// reports, so collapsing "not reported" into it would fabricate a reading.
  public var vmsSummary: String {
    guard let vmsRunning, let vmsTotal else { return "Unavailable" }
    return "\(vmsRunning) of \(vmsTotal) running"
  }

  public var sharesSummary: String { Formatters.count(sharesTotal, "share") }
}

/// Everything one dashboard refresh needs: a core query that must succeed, plus
/// the Docker and VM counts, fetched separately so a disabled service reads as
/// unavailable instead of failing the whole dashboard.
public struct DashboardSnapshot: Equatable, Sendable {
  public let array: ArrayStatus
  public let parity: ParityStatus
  public let services: ServiceCounts

  public init(array: ArrayStatus, parity: ParityStatus, services: ServiceCounts) {
    self.array = array
    self.parity = parity
    self.services = services
  }
}
