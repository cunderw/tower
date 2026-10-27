import Foundation
import TowerCore
import TowerData

/// The six demo repository conformances.
///
/// Each is the same protocol the live one implements, so demo mode is a single
/// `AppEnvironment` assignment and **no feature branches on it** — no
/// `if isDemo` anywhere in a view or a store. That is the architectural point of
/// making repositories protocols in the first place.
///
/// They share one injected `DemoServer`, so the tabs agree with each other:
/// stopping a container drops the dashboard's running count, archiving a
/// notification clears the badge.
///
/// **Every method sleeps first.** Without it each screen would snap to loaded
/// instantly, and a reviewer would never see the loading states, the pull-to-
/// refresh, or the spinner a real LAN produces — the demo would be showing them
/// an app that doesn't behave like the one they'd install. It's short enough not
/// to feel broken.
private enum DemoLatency {
  /// A first load: long enough that the loading state is visible, short enough
  /// that nothing feels stuck.
  static let read = Duration.milliseconds(450)
  /// A mutation, which on a real box takes longer than a read — a `docker stop`
  /// has a SIGTERM grace period.
  static let write = Duration.milliseconds(700)

  static func read() async { try? await Task.sleep(for: read) }
  static func write() async { try? await Task.sleep(for: write) }
}

struct DemoSystemRepository: SystemRepositoryProtocol {
  let server: DemoServer

  func testConnection() async throws -> Bool {
    await DemoLatency.read()
    return true
  }

  func dashboard() async throws -> DashboardSnapshot {
    await DemoLatency.read()
    return server.dashboard()
  }
}

struct DemoDockerRepository: DockerRepositoryProtocol {
  let server: DemoServer

  func containers() async throws -> [Container] {
    await DemoLatency.read()
    return server.currentContainers()
  }

  func start(id: String) async throws -> ContainerStateUpdate {
    await DemoLatency.write()
    return server.updateContainer(id: id, state: .running, status: "Up less than a minute")
  }

  func stop(id: String) async throws -> ContainerStateUpdate {
    await DemoLatency.write()
    return server.updateContainer(
      id: id, state: .exited, status: "Exited (0) less than a minute ago"
    )
  }

  func restart(id: String) async throws -> ContainerStateUpdate {
    await DemoLatency.write()
    return server.updateContainer(id: id, state: .running, status: "Up less than a minute")
  }

  func pause(id: String) async throws -> ContainerStateUpdate {
    await DemoLatency.write()
    return server.updateContainer(id: id, state: .paused, status: "Paused")
  }

  func unpause(id: String) async throws -> ContainerStateUpdate {
    await DemoLatency.write()
    return server.updateContainer(id: id, state: .running, status: "Up less than a minute")
  }

  func logs(id: String, tail: Int?, since: String?) async throws -> ContainerLogs {
    await DemoLatency.read()
    let name = server.currentContainers().first { $0.id == id }?.displayName ?? "container"
    return ContainerLogs(
      containerId: id,
      lines: (1...min(tail ?? 40, 40)).map { index in
        ContainerLogLine(
          timestamp: Date(timeIntervalSinceNow: -Double(40 - index) * 30),
          message: "[\(name)] worker ready, handled \(index * 17) requests"
        )
      },
      cursor: nil
    )
  }
}

struct DemoVMRepository: VMRepositoryProtocol {
  let server: DemoServer

  func domains() async throws -> VMInventory {
    await DemoLatency.read()
    return VMInventory(domains: server.currentDomains())
  }

  func start(id: String) async throws { await apply(.running, to: id) }
  func stop(id: String) async throws { await apply(.shutoff, to: id) }
  func forceStop(id: String) async throws { await apply(.shutoff, to: id) }
  func pause(id: String) async throws { await apply(.paused, to: id) }
  func resume(id: String) async throws { await apply(.running, to: id) }
  func reboot(id: String) async throws { await apply(.running, to: id) }
  func reset(id: String) async throws { await apply(.running, to: id) }

  private func apply(_ state: VMState, to id: String) async {
    await DemoLatency.write()
    server.updateDomain(id: id, state: state)
  }
}

struct DemoShareRepository: ShareRepositoryProtocol {
  let server: DemoServer

  func shares() async throws -> [Share] {
    await DemoLatency.read()
    // Shares have no mutations, so this is the one dataset that doesn't need to
    // live in `DemoServer`.
    return DemoData.shares
  }
}

struct DemoNotificationRepository: NotificationRepositoryProtocol {
  let server: DemoServer

  func overview() async throws -> NotificationOverview {
    // Deliberately *not* delayed: this one runs on the shell's 30-second poll
    // behind whatever tab is showing, and a sleep here would make the badge lag
    // an action the user just took on screen.
    server.notificationOverview()
  }

  func page(kind: NotificationKind, offset: Int, limit: Int) async throws -> NotificationPage {
    await DemoLatency.read()
    let bucket = server.currentNotifications().filter { $0.kind == kind }
    guard offset < bucket.count else {
      return NotificationPage(notifications: [], requestedLimit: max(1, limit))
    }
    let end = min(bucket.count, offset + max(1, limit))
    return NotificationPage(
      notifications: Array(bucket[offset..<end]), requestedLimit: max(1, limit)
    )
  }

  func archive(id: String) async throws -> NotificationOverview {
    await DemoLatency.write()
    server.moveNotification(id: id, to: .archive)
    return server.notificationOverview()
  }

  func markUnread(id: String) async throws -> NotificationOverview {
    await DemoLatency.write()
    server.moveNotification(id: id, to: .unread)
    return server.notificationOverview()
  }

  func delete(id: String, kind: NotificationKind) async throws -> NotificationOverview {
    await DemoLatency.write()
    server.removeNotification(id: id)
    return server.notificationOverview()
  }

  func archiveAll() async throws -> NotificationOverview {
    await DemoLatency.write()
    server.archiveAllNotifications()
    return server.notificationOverview()
  }
}

struct DemoLogRepository: LogRepositoryProtocol {
  let server: DemoServer

  func logFiles() async throws -> [LogFile] {
    await DemoLatency.read()
    return DemoData.logFiles
  }

  func logFile(path: String, lines: Int?) async throws -> LogFileContents {
    await DemoLatency.read()
    return DemoData.logContents(path: path, lines: lines ?? 200)
  }
}
