import Foundation

/// Unraid's `NotificationImportance`, plus an `.unknown` escape hatch so a
/// server-side addition degrades instead of failing to decode — the same shape
/// `ContainerState` and `VMState` use.
public enum NotificationImportance: String, Hashable, Sendable, CaseIterable {
  case info = "INFO"
  case warning = "WARNING"
  case alert = "ALERT"
  case unknown

  public init(rawValue: String) {
    self = switch rawValue {
    case "INFO": .info
    case "WARNING": .warning
    case "ALERT": .alert
    default: .unknown
    }
  }

  /// The single place importance becomes user-facing copy. Read by the row's
  /// visible text *and* its accessibility label, so the two can never disagree —
  /// and so importance is never conveyed by colour alone.
  public var displayName: String {
    switch self {
    case .info: "Info"
    case .warning: "Warning"
    case .alert: "Alert"
    case .unknown: "Unknown"
    }
  }

  /// Sort weight, most severe first. `.unknown` sorts with `.info` rather than
  /// at either extreme: promoting an unrecognized importance to the top of the
  /// list would be a claim about severity Tower has no basis for, and burying it
  /// last would hide it.
  public var severityRank: Int {
    switch self {
    case .alert: 0
    case .warning: 1
    case .info, .unknown: 2
    }
  }
}

/// Which bucket a notification is in. Unraid calls this `type`; `kind` here
/// because `type` reads as "what sort of event" rather than "read or archived",
/// which is what it actually means.
public enum NotificationKind: String, Hashable, Sendable, CaseIterable {
  case unread = "UNREAD"
  case archive = "ARCHIVE"
  case unknown

  public init(rawValue: String) {
    self = switch rawValue {
    case "UNREAD": .unread
    case "ARCHIVE": .archive
    default: .unknown
    }
  }

  public var displayName: String {
    switch self {
    case .unread: "Unread"
    case .archive: "Archive"
    case .unknown: "Unknown"
    }
  }
}

/// One notification as Unraid's `Notification` reports it.
public struct ServerNotification: Identifiable, Equatable, Hashable, Sendable {
  public let id: String
  /// Non-null on the wire. In practice a generic banner ("Unraid Server Alert")
  /// — `subject` is the specific one ("UPS Alert"), which is why the row leads
  /// with subject and the title is secondary.
  public let title: String
  public let subject: String
  public let description: String
  public let importance: NotificationImportance
  public let kind: NotificationKind
  /// **A server-relative path**, not a URL — `"/Settings/UPSsettings"`. Carried
  /// raw: resolving it needs the server's base URL, which lives in `Server`, in
  /// the app layer. Passing this to `URL(string:)` yields a relative URL that
  /// opens nothing, which is the mistake this doc comment exists to prevent.
  public let linkPath: String?
  /// `nil` when the server sent no timestamp *or* sent one that didn't parse.
  ///
  /// The schema declares `timestamp` nullable, and it is a plain `String` rather
  /// than the `DateTime` scalar. Both cases collapse to `nil` deliberately: a
  /// notification's content is the payload and its timestamp is metadata, so a
  /// bad timestamp must never cost the notification — the same rule
  /// `ContainerLogLine` states for log lines, and the reason Tower keeps
  /// `DateTime` a `String` on the wire.
  public let timestamp: Date?

  public init(
    id: String, title: String, subject: String, description: String,
    importance: NotificationImportance, kind: NotificationKind,
    linkPath: String?, timestamp: Date?
  ) {
    self.id = id
    self.title = title
    self.subject = subject
    self.description = description
    self.importance = importance
    self.kind = kind
    self.linkPath = linkPath
    self.timestamp = timestamp
  }
}

/// One bucket's counts by importance, as `NotificationCounts` reports them.
public struct NotificationCounts: Equatable, Hashable, Sendable {
  public let info: Int
  public let warning: Int
  public let alert: Int
  public let total: Int

  public init(info: Int, warning: Int, alert: Int, total: Int) {
    self.info = info
    self.warning = warning
    self.alert = alert
    self.total = total
  }

  /// All four are non-null on the wire, so there is no nil-versus-zero question
  /// here — a zero is a real zero, unlike `ServiceCounts.vmsRunning`.
  public static let zero = NotificationCounts(info: 0, warning: 0, alert: 0, total: 0)
}

/// Both buckets' counts — what drives the bell's badge.
public struct NotificationOverview: Equatable, Hashable, Sendable {
  public let unread: NotificationCounts
  public let archive: NotificationCounts

  public init(unread: NotificationCounts, archive: NotificationCounts) {
    self.unread = unread
    self.archive = archive
  }

  public static let zero = NotificationOverview(unread: .zero, archive: .zero)

  /// What the badge shows, or `nil` when there is nothing to show.
  ///
  /// `nil` rather than `0` on purpose: a badge reading "0" is worse than no
  /// badge — it draws the eye to say nothing happened.
  public var badgeCount: Int? {
    unread.total > 0 ? unread.total : nil
  }

  /// Whether anything unread is a warning or an alert. The badge is a count, not
  /// a severity, so this is what a caller wanting to tint or prioritise reads —
  /// rather than inferring severity from the count, which says nothing about it.
  public var hasUnreadWarningsOrAlerts: Bool {
    unread.warning > 0 || unread.alert > 0
  }
}

/// One page of a bucket, as returned by `notifications.list(filter:)`.
///
/// `NotificationFilter` requires both `offset` and `limit`, and the response
/// carries no total — `NotificationOverview` is the only count — so a caller
/// paging through has to decide when to stop from the page size alone. That is
/// what `isLastPage` encodes, and why it is expressed as "fewer than asked for"
/// rather than compared against a total that isn't there.
public struct NotificationPage: Equatable, Sendable {
  public let notifications: [ServerNotification]
  /// The `limit` this page was requested with.
  public let requestedLimit: Int

  public init(notifications: [ServerNotification], requestedLimit: Int) {
    self.notifications = notifications
    self.requestedLimit = requestedLimit
  }

  /// A short page means the end. Not proof — a server could in principle return
  /// fewer than asked for mid-list — but it is the only signal this API offers,
  /// and the failure mode is a "load more" that returns nothing rather than
  /// missing data.
  public var isLastPage: Bool {
    notifications.count < requestedLimit
  }
}
