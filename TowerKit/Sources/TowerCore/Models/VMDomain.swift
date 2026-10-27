import Foundation

/// Unraid's `VmState` enum — libvirt's own eight domain states — plus an
/// `.unknown` escape hatch so a server-side addition degrades instead of
/// failing to decode. Mirrors `ContainerState` in `Container.swift`.
public enum VMState: String, Hashable, Sendable {
  case nostate = "NOSTATE"
  case running = "RUNNING"
  case idle = "IDLE"
  case paused = "PAUSED"
  case shutdown = "SHUTDOWN"
  case shutoff = "SHUTOFF"
  case crashed = "CRASHED"
  case pmSuspended = "PMSUSPENDED"
  case unknown

  public init(rawValue: String) {
    self = switch rawValue {
    case "NOSTATE": .nostate
    case "RUNNING": .running
    case "IDLE": .idle
    case "PAUSED": .paused
    case "SHUTDOWN": .shutdown
    case "SHUTOFF": .shutoff
    case "CRASHED": .crashed
    case "PMSUSPENDED": .pmSuspended
    default: .unknown
    }
  }

  /// The single place a `VMState` becomes user-facing copy — the state dot's
  /// accessibility label, the row's visible text, and the detail screen's
  /// State row all read this, so VoiceOver and sighted users always agree on
  /// the wording (the rule `ContainerState.displayName` established).
  ///
  /// Three of these deliberately do not echo libvirt's own vocabulary:
  /// `SHUTOFF` reads "Stopped" (libvirt's "shut off" is not how anyone
  /// describes a VM that isn't running), `PMSUSPENDED` reads "Suspended"
  /// (its raw name is an implementation detail — power-management suspend),
  /// and `NOSTATE` reads "Unknown" because that is literally what libvirt
  /// means by it: the domain exists but reported no state. `SHUTDOWN` keeps
  /// its distinction from `SHUTOFF` — it means *shutting down*, still on,
  /// which is exactly why the two must not collapse into one word.
  public var displayName: String {
    switch self {
    case .nostate: "Unknown"
    case .running: "Running"
    case .idle: "Idle"
    case .paused: "Paused"
    case .shutdown: "Shutting Down"
    case .shutoff: "Stopped"
    case .crashed: "Crashed"
    case .pmSuspended: "Suspended"
    case .unknown: "Unknown"
    }
  }

  /// Which actions a VM in this state can legitimately be offered.
  ///
  /// This is an enum rather than three independent `isRunning`/`isPaused`
  /// /`isStopped` booleans, for one reason: there is a
  /// fourth bucket, and booleans hide it. `SHUTDOWN`, `NOSTATE`, and
  /// `.unknown` are neither up nor off, and a UI written against three
  /// booleans falls through to "not running, so offer Start" for all three —
  /// which for a VM mid-shutdown is an action libvirt will reject, and for a
  /// state Tower doesn't recognize is a guess. Switching over this makes that
  /// case something a reader has to answer, not something they can forget.
  public var activity: VMActivity {
    switch self {
    case .running, .idle: .running
    case .paused, .pmSuspended: .paused
    case .shutoff, .crashed: .stopped
    case .shutdown, .nostate, .unknown: .indeterminate
    }
  }
}

/// The four ways a VM's state can be *acted on*, as opposed to the nine ways
/// it can be *reported* (`VMState`). See `VMState.activity`.
public enum VMActivity: Equatable, Sendable {
  /// Up and executing — `RUNNING`, `IDLE`. Can be stopped, paused, rebooted,
  /// reset.
  case running
  /// Up but not executing — `PAUSED`, `PMSUSPENDED`. Can be resumed or
  /// stopped, but never *started*: libvirt rejects `start` on a domain that
  /// is already up, the same trap `ContainerRow.canStop` documents for
  /// paused Docker containers.
  case paused
  /// Genuinely off — `SHUTOFF`, `CRASHED`. Can only be started.
  case stopped
  /// Neither up nor off (`SHUTDOWN`, mid-shutdown) or unclassifiable
  /// (`NOSTATE`, `.unknown`). Force Stop is the only action that makes sense
  /// here, and if the server disagrees, that refusal surfaces (see
  /// `AppError.actionRefused`) rather than being hidden behind an action
  /// Tower guessed at.
  case indeterminate
}

/// A libvirt domain as Unraid's `VmDomain` reports it — `id`, an optional
/// `name`, and a state. That is the whole type; there is no vCPU count,
/// memory figure, disk list, or uptime in the schema to map.
public struct VMDomain: Identifiable, Equatable, Hashable, Sendable {
  public let id: String
  /// **Nullable in the schema**, and not normalised away here — see
  /// `displayName` for what the UI renders instead.
  public let name: String?
  public let state: VMState

  public init(id: String, name: String?, state: VMState) {
    self.id = id
    self.name = name
    self.state = state
  }

  /// `name` when the server reported one, otherwise the UUID half of `id`.
  ///
  /// A VM with no name still has to be listed, titled, and tappable, so an
  /// empty title is not an acceptable output — the same reason
  /// `Container.displayName` falls back to `image`. Unraid's `id` is
  /// `<server-hash>:<uuid>`; the hash is identical for every entity on the
  /// box and carries no information for a human, so the fallback keeps only
  /// the UUID. An empty string is treated exactly like a nil name: the
  /// repository already maps `""` to `nil` at the boundary, and this guard
  /// covers hand-built values (fixtures, previews) that skip that path.
  public var displayName: String {
    if let name, !name.isEmpty { return name }
    let uuid = id.split(separator: ":").last.map(String.init) ?? ""
    return uuid.isEmpty ? id : uuid
  }
}

/// One `vms` response.
///
/// Exists purely to carry the nil-versus-empty distinction that a bare
/// `[VMDomain]` would erase: `domains` is a **nullable** list in the schema
/// (`domains: [VmDomain!]`), unlike `docker.containers`, and `nil` means VM
/// reporting is unavailable — libvirt stopped, errored, or otherwise not
/// answering — **not** "zero VMs defined". A healthy server with no VMs
/// reports `[]`.
///
/// `ServiceCounts.vmsRunning` already carries this same distinction on the
/// dashboard. Telling a user whose VM manager is off that they have no VMs is
/// a claim about their server that Tower cannot make.
public struct VMInventory: Equatable, Sendable {
  public let domains: [VMDomain]?

  public init(domains: [VMDomain]?) {
    self.domains = domains
  }

  /// Whether the server declined to report VMs at all, as opposed to
  /// reporting none. `VMListView` renders a different `ContentUnavailableView`
  /// for each.
  public var isUnavailable: Bool { domains == nil }
}
