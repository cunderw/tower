import Foundation
import TowerCore

/// The in-memory Unraid server demo mode talks to.
///
/// **One box behind all six repositories**, not six independent fixtures.
/// That is what makes the demo hold together: stopping a container in the Docker
/// tab drops the dashboard's "6 of 8 running" to 5, archiving a notification
/// clears the bell's badge, and starting a VM changes the services row. Six
/// independent datasets would each be internally plausible and collectively
/// incoherent — and a reviewer poking at two tabs is exactly who would notice.
///
/// Why this is not `Fake*Repository` from `UITestSupport.swift`, which already
/// mutates in memory:
///
/// 1. **Those are `#if DEBUG`, deliberately.** They're reached through
///    `--uitest-seed-dashboard`, a launch argument that skips authentication
///    entirely; shipping that in a Release build would let anyone able to pass
///    launch arguments bypass the connect screen. Demo mode has to ship.
/// 2. **Their data is tuned to make failure paths reachable** — a container whose
///    every action fails, a VM that refuses everything, a notification that can't
///    be archived. Correct for tests, wrong for the first thing an App Store
///    reviewer sees.
///
/// `@unchecked Sendable` with an `NSLock`, matching `InMemoryServerStore` and the
/// UI-test fakes: the repository protocols require `Sendable` and carry no actor
/// isolation.
///
/// **Injected, not a singleton.** `AppEnvironment.demo` builds one and hands it to
/// all six repositories, so entering demo mode is inherently a fresh server — no
/// `reset()` to remember to call, and no global for concurrent tests to trip over
/// each other on: demo tests sharing one instance read each other's counts.
final class DemoServer: @unchecked Sendable {
  private let lock = NSLock()
  private var containers: [Container]
  private var domains: [VMDomain]
  private var notifications: [ServerNotification]
  private var parity: ParityStatus
  private var parityHistory: [ParityCheckRecord]

  init() {
    containers = DemoData.containers
    domains = DemoData.domains
    notifications = DemoData.notifications
    parity = DemoData.parity
    parityHistory = DemoData.parityHistory
  }

  // MARK: - Reads

  func currentContainers() -> [Container] {
    lock.withLock { containers }
  }

  func currentDomains() -> [VMDomain] {
    lock.withLock { domains }
  }

  func currentNotifications() -> [ServerNotification] {
    lock.withLock { notifications }
  }

  func currentParityHistory() -> [ParityCheckRecord] {
    lock.withLock { parityHistory }
  }

  /// The dashboard's snapshot, recomputed from live state so the services card
  /// agrees with what the other tabs show.
  func dashboard() -> DashboardSnapshot {
    lock.withLock {
      DashboardSnapshot(
        array: DemoData.array,
        parity: parity,
        services: ServiceCounts(
          containersRunning: containers.filter(\.isRunning).count,
          containersTotal: containers.count,
          vmsRunning: domains.filter { $0.state.activity == .running }.count,
          vmsTotal: domains.count,
          sharesTotal: DemoData.shares.count
        )
      )
    }
  }

  func notificationOverview() -> NotificationOverview {
    lock.withLock {
      NotificationOverview(
        unread: Self.counts(notifications.filter { $0.kind == .unread }),
        archive: Self.counts(notifications.filter { $0.kind == .archive })
      )
    }
  }

  // MARK: - Mutations

  /// Applies a container state change, exactly as `DockerMutations` would report
  /// it back.
  func updateContainer(id: String, state: ContainerState, status: String) -> ContainerStateUpdate {
    lock.withLock {
      containers = containers.map { container in
        guard container.id == id else { return container }
        return container.applyingStateUpdate(
          ContainerStateUpdate(id: id, state: state, status: status)
        )
      }
    }
    return ContainerStateUpdate(id: id, state: state, status: status)
  }

  /// Recreates a container from its latest image, as `updateContainer` does:
  /// the recreated container has a new ID and no update to report. `nil` for
  /// an ID the demo does not have.
  func recreateWithLatestImage(id: String) -> Container? {
    lock.withLock {
      guard let index = containers.firstIndex(where: { $0.id == id }) else { return nil }
      let old = containers[index]
      let recreated = Container(
        id: "\(old.id)-updated", names: old.names, image: old.image, state: old.state,
        status: old.isRunning ? "Up less than a minute" : old.status, autoStart: old.autoStart,
        isUpdateAvailable: false, isOrphaned: old.isOrphaned, webUiURL: old.webUiURL,
        iconURL: old.iconURL, projectURL: old.projectURL, supportURL: old.supportURL,
        registryURL: old.registryURL, templatePath: old.templatePath,
        networkMode: old.networkMode, ports: old.ports
      )
      containers[index] = recreated
      return recreated
    }
  }

  func updateDomain(id: String, state: VMState) {
    lock.withLock {
      domains = domains.map { domain in
        domain.id == id ? VMDomain(id: domain.id, name: domain.name, state: state) : domain
      }
    }
  }

  func moveNotification(id: String, to kind: NotificationKind) {
    lock.withLock {
      notifications = notifications.map { notification in
        guard notification.id == id else { return notification }
        return notification.movedTo(kind)
      }
    }
  }

  /// A new check from 0%, as Unraid reports one the moment it starts.
  func startParityCheck(correct: Bool) {
    lock.withLock {
      parity = ParityStatus(
        state: .running, progressPercent: 0, errors: 0, speed: nil,
        lastRunTimestamp: nil, durationSeconds: nil, correcting: correct
      )
    }
  }

  /// Pause or resume: the same check, in another state.
  func setParityState(_ state: ParityCheckState) {
    lock.withLock {
      parity = ParityStatus(
        state: state, progressPercent: parity.progressPercent, errors: parity.errors,
        speed: parity.speed, lastRunTimestamp: parity.lastRunTimestamp,
        durationSeconds: parity.durationSeconds, correcting: parity.correcting
      )
    }
  }

  /// Ends the check and records it in the history, as Unraid does.
  func cancelParityCheck() {
    lock.withLock {
      let now = Date()
      let durationSeconds = 9 * 60 * 60
      parity = ParityStatus(
        state: .cancelled, progressPercent: nil, errors: parity.errors, speed: nil,
        lastRunTimestamp: now.formatted(Date.ISO8601FormatStyle(includingFractionalSeconds: true)),
        durationSeconds: durationSeconds, correcting: false
      )
      let cancelled = ParityCheckRecord(
        id: 0, date: now, durationSeconds: durationSeconds, speed: "150 MB/s",
        state: .cancelled, errors: parity.errors
      )
      parityHistory = ([cancelled] + parityHistory).enumerated().map { index, record in
        ParityCheckRecord(
          id: index, date: record.date, durationSeconds: record.durationSeconds,
          speed: record.speed, state: record.state, errors: record.errors
        )
      }
    }
  }

  func removeNotification(id: String) {
    lock.withLock { notifications.removeAll { $0.id == id } }
  }

  func archiveAllNotifications() {
    lock.withLock {
      notifications = notifications.map { $0.kind == .unread ? $0.movedTo(.archive) : $0 }
    }
  }

  private static func counts(_ bucket: [ServerNotification]) -> NotificationCounts {
    NotificationCounts(
      info: bucket.filter { $0.importance == .info }.count,
      warning: bucket.filter { $0.importance == .warning }.count,
      alert: bucket.filter { $0.importance == .alert }.count,
      total: bucket.count
    )
  }
}

extension ServerNotification {
  /// Same notification, different bucket.
  fileprivate func movedTo(_ kind: NotificationKind) -> ServerNotification {
    ServerNotification(
      id: id, title: title, subject: subject, description: description,
      importance: importance, kind: kind, linkPath: linkPath, timestamp: timestamp
    )
  }
}
