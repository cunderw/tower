import Foundation

/// Unraid's `ContainerState` enum, plus an `.unknown` escape hatch so a
/// server-side addition degrades instead of failing to decode — mirrors
/// `ParityCheckState` in `Dashboard.swift`.
public enum ContainerState: String, Hashable, Sendable {
  case running = "RUNNING"
  case paused = "PAUSED"
  case exited = "EXITED"
  case unknown

  public init(rawValue: String) {
    self = switch rawValue {
    case "RUNNING": .running
    case "PAUSED": .paused
    case "EXITED": .exited
    default: .unknown
    }
  }

  /// The single place a `ContainerState` becomes user-facing copy — both
  /// `StateDot`'s accessibility label and `ContainerRow`'s visible text read
  /// this, so VoiceOver and sighted users always agree on the wording, and
  /// colour is never the only signal.
  public var displayName: String {
    switch self {
    case .running: "Running"
    case .paused: "Paused"
    case .exited: "Exited"
    case .unknown: "Unknown"
    }
  }
}

/// One published or exposed port on a container, as Unraid's `ContainerPort`
/// reports it.
public struct ContainerPort: Equatable, Hashable, Sendable {
  public let ip: String?
  public let privatePort: Int?
  public let publicPort: Int?
  /// `"TCP"` or `"UDP"` as the server reports it — display-only, so there's
  /// no `.unknown` escape hatch to maintain here the way `ContainerState`
  /// needs one.
  public let type: String

  public init(ip: String?, privatePort: Int?, publicPort: Int?, type: String) {
    self.ip = ip
    self.privatePort = privatePort
    self.publicPort = publicPort
    self.type = type
  }

  /// `"13378 → 80/TCP"` for a published port; just `"80/TCP"` when Docker
  /// only exposes the port internally (no `publicPort`); falls back further
  /// still if even `privatePort` is somehow missing, rather than fabricating
  /// either half.
  public var summary: String {
    switch (privatePort, publicPort) {
    case let (.some(priv), .some(pub)):
      return "\(pub) → \(priv)/\(type)"
    case let (.some(priv), .none):
      return "\(priv)/\(type)"
    case let (.none, .some(pub)):
      return "\(pub)/\(type)"
    case (.none, .none):
      return type
    }
  }
}

/// A Docker container as Unraid's `DockerContainer` reports it.
public struct Container: Identifiable, Equatable, Hashable, Sendable {
  public let id: String
  /// Arrives from the server with a leading slash (`["/code-server"]`) —
  /// `displayName` strips it. Never render this raw.
  public let names: [String]
  public let image: String
  public let state: ContainerState
  public let status: String
  public let autoStart: Bool
  /// **Nullable on purpose** — the schema declares `isUpdateAvailable` as
  /// nullable, and `nil` means "not determined", not "no update available".
  /// Collapsing this to `false` would render as "up to date", a claim we
  /// cannot make.
  public let isUpdateAvailable: Bool?
  public let isOrphaned: Bool
  public let webUiURL: URL?
  public let iconURL: URL?
  public let projectURL: URL?
  public let supportURL: URL?
  public let registryURL: URL?
  /// Path to the container's template file on disk, when one exists. `nil`
  /// for containers with no matching template — `isOrphaned` is the
  /// authoritative signal for that; this is display/debug metadata only.
  public let templatePath: String?
  public let networkMode: String?
  public let ports: [ContainerPort]

  public init(
    id: String, names: [String], image: String, state: ContainerState, status: String,
    autoStart: Bool, isUpdateAvailable: Bool?, isOrphaned: Bool,
    webUiURL: URL?, iconURL: URL?, projectURL: URL?, supportURL: URL?, registryURL: URL?,
    templatePath: String?, networkMode: String?, ports: [ContainerPort]
  ) {
    self.id = id; self.names = names; self.image = image; self.state = state
    self.status = status; self.autoStart = autoStart
    self.isUpdateAvailable = isUpdateAvailable; self.isOrphaned = isOrphaned
    self.webUiURL = webUiURL; self.iconURL = iconURL; self.projectURL = projectURL
    self.supportURL = supportURL; self.registryURL = registryURL
    self.templatePath = templatePath; self.networkMode = networkMode; self.ports = ports
  }

  /// The first name with its leading slash stripped, or `image` when Docker
  /// reports no name at all. Docker names always arrive with a leading `/`
  /// (`["/code-server"]`) — rendering that raw is the same class of mistake as
  /// rendering a boot timestamp as uptime.
  public var displayName: String {
    guard let first = names.first else { return image }
    return first.hasPrefix("/") ? String(first.dropFirst()) : first
  }

  public var isRunning: Bool { state == .running }
}

/// The subset of `Container` a Docker action mutation
/// (`start`/`stop`/`restart`/`pause`/`unpause`) returns — deliberately just
/// `id`, `state`, and `status`, matching each mutation's selection set (see
/// `graphql/operations/DockerMutations.graphql`). Docker state transitions
/// are asynchronous — a container that just returned `RUNNING` from `start`
/// may still report `EXITED` on the next poll for a moment — so this is
/// treated as the authoritative reading for its row until the next
/// successful `containers()` refresh, not fought against. See
/// `Container.applyingStateUpdate(_:)` and `DockerStore.perform(_:on:)`.
public struct ContainerStateUpdate: Identifiable, Equatable, Sendable {
  public let id: String
  public let state: ContainerState
  public let status: String

  public init(id: String, state: ContainerState, status: String) {
    self.id = id
    self.state = state
    self.status = status
  }
}

extension Container {
  /// Applies a mutation's `ContainerStateUpdate` to this container, keeping
  /// every other field (image, ports, web UI, etc.) exactly as last reported
  /// by `containers()`. The mutation's selection set only ever asked for
  /// `id`/`state`/`status`, so those are the only fields it can honestly
  /// claim to know — fabricating the rest from nothing would be worse than
  /// leaving them alone.
  public func applyingStateUpdate(_ update: ContainerStateUpdate) -> Container {
    Container(
      id: id, names: names, image: image, state: update.state, status: update.status,
      autoStart: autoStart, isUpdateAvailable: isUpdateAvailable, isOrphaned: isOrphaned,
      webUiURL: webUiURL, iconURL: iconURL, projectURL: projectURL, supportURL: supportURL,
      registryURL: registryURL, templatePath: templatePath, networkMode: networkMode, ports: ports
    )
  }
}

/// One line of a Docker container's log output, as `DockerContainerLogLine`
/// reports it.
///
/// `timestamp` is `Date?`, not `Date` — the schema declares the field
/// non-null, but the raw string it carries doesn't always parse cleanly
/// (`Formatters.parseTimestamp` already tolerates fractional seconds and a
/// bare `Z` suffix; anything else degrades to `nil` here rather than
/// throwing). This is deliberate: the message is the payload a user is
/// reading a log to see, the timestamp is decoration on top of it. A line
/// whose timestamp fails to parse must still render — never dropped because
/// its metadata, not its content, was bad.
public struct ContainerLogLine: Equatable, Hashable, Sendable {
  public let timestamp: Date?
  public let message: String

  public init(timestamp: Date?, message: String) {
    self.timestamp = timestamp
    self.message = message
  }
}

/// One `docker.logs` response, as `DockerContainerLogs` reports it — mirrors
/// `ContainerStateUpdate`'s "just the fields the selection set
/// actually asked for" shape rather than folding into `Container` itself,
/// since a container's log output isn't part of what `containers()` reports.
///
/// `cursor` is carried through as a raw, unparsed `DateTime` string (like
/// `Container.templatePath` is a raw passthrough) rather than a `Date`:
/// nothing here renders it, it only ever travels back into a future `since`
/// argument. It is **not** what `ContainerLogsStore.loadMore()` uses to page
/// in older history — Unraid's `since` is inclusive-*forward* (matching the
/// schema's own "continue streaming logs"
/// doc comment on `cursor`): re-requesting with `since` set to the oldest
/// loaded line's timestamp returns that same line again, not anything
/// earlier. Paging backward instead re-requests a larger `tail`, which is
/// the one lever this API actually offers for reaching further into
/// history. See `LiveDockerRepository.logs(id:tail:since:)`'s doc comment.
public struct ContainerLogs: Equatable, Sendable {
  public let containerId: String
  public let lines: [ContainerLogLine]
  public let cursor: String?

  public init(containerId: String, lines: [ContainerLogLine], cursor: String?) {
    self.containerId = containerId
    self.lines = lines
    self.cursor = cursor
  }
}
