import Foundation
import Testing
import TowerCore
@testable import Tower

/// The demo dataset is what an App Store reviewer sees. These check the parts
/// that are easy to get quietly wrong.
@MainActor
struct DemoDataTests {
  @Test func theBootTimestampParsesWithTheSameFormatterTheAppUses() {
    // A hand-assembled `ISO8601FormatStyle` can produce a string
    // `Formatters.parseTimestamp` rejects, and the demo dashboard then shows
    // "Uptime — Unknown". The demo's timestamp has to parse with the formatter
    // the app reads it with.
    let parsed = Formatters.parseTimestamp(DemoData.bootTimestamp)

    #expect(parsed != nil, "the demo's boot timestamp doesn't parse: \(DemoData.bootTimestamp)")
    let uptime = Formatters.uptime(sinceTimestamp: DemoData.bootTimestamp)
    #expect(uptime != "Unknown")
    #expect(uptime.contains("d "), "uptime didn't read as a duration: \(uptime)")
  }

  @Test func theDemoDatasetHasAStoppedContainerAnUpdateAWarmDiskAndAWarning() {
    // The demo includes a stopped container, one with an update available, a
    // disk running warm, and an unread warning notification. A screen of
    // uniformly healthy rows teaches a reviewer nothing about what the app does.
    #expect(DemoData.containers.contains { $0.state == .exited })
    #expect(DemoData.containers.contains { $0.isUpdateAvailable == true })
    #expect(DemoData.array.disks.contains { ($0.temp ?? 0) >= 50 })
    #expect(DemoData.notifications.contains { $0.kind == .unread && $0.importance == .warning })
  }

  @Test func theDemoNeverNamesTheRealServer() {
    // Screenshots of Settings show the address and the last four characters of the
    // key. `192.0.2.x` is TEST-NET-1 (RFC 5737) — reserved for documentation and
    // guaranteed not to route.
    #expect(DemoData.server.url.absoluteString.contains("192.0.2."))
    #expect(DemoData.server.apiKey.contains("demo"))
  }

  @Test func everyContainerWithAWebUIPointsAtTheDocumentationAddress() {
    for container in DemoData.containers {
      guard let url = container.webUiURL else { continue }
      #expect(url.absoluteString.contains("192.0.2."), "a demo container links to \(url)")
    }
  }

  @Test func sharesOnTheSamePoolReportIdenticalFiguresLikeTheRealAPI() {
    // Unraid reports the pool's usage on every share in that pool, not the
    // share's own. Modelled rather than smoothed over: a demo where every share
    // showed a different plausible number would teach a reviewer — and a future
    // maintainer — the wrong thing about this API.
    let cachePool = Set(
      DemoData.shares.filter { $0.poolUsedKilobytes == 412_000_000 }.map(\.poolFreeKilobytes)
    )
    #expect(cachePool.count == 1)
    #expect(Set(DemoData.shares.map(\.poolUsedKilobytes)).count == 2, "expected exactly two pools")
  }

  @Test func notificationTimestampsAreRelativeSoTheyNeverAge() {
    // Fixed dates would read as "3 years ago" by the time anyone reviews this.
    for notification in DemoData.notifications {
      guard let timestamp = notification.timestamp else {
        Issue.record("a demo notification has no timestamp")
        continue
      }
      #expect(timestamp < Date())
      #expect(timestamp > Date(timeIntervalSinceNow: -60 * 60 * 24 * 30))
    }
  }

  // MARK: - The shared server

  @Test func stoppingAContainerChangesTheDashboardsRunningCount() async throws {
    // What makes the demo hold together rather than being six unrelated fixtures:
    // the repositories share one `DemoServer`, so a mutation in one tab is visible
    // in another. A reviewer poking at two tabs is exactly who notices.
    //
    // Its own instance, because these tests run in parallel: with a shared global
    // they interfere, and a count comes out right for a different test's timing.
    // That is also why `AppEnvironment.demo` builds a fresh server rather than
    // resetting a shared one.
    let server = DemoServer()
    let docker = DemoDockerRepository(server: server)
    let system = DemoSystemRepository(server: server)

    // `containersRunning` is optional, nil for a Docker service that is off.
    // The demo server always reports Docker, so a nil here is a failure.
    let before = try #require(try await system.dashboard().services.containersRunning)
    let running = try #require(try await docker.containers().first(where: \.isRunning))
    _ = try await docker.stop(id: running.id)

    let after = try await system.dashboard().services.containersRunning
    #expect(after == before - 1, "the dashboard didn't follow a Docker mutation")
  }

  @Test func archivingANotificationClearsItFromTheUnreadCount() async throws {
    let notifications = DemoNotificationRepository(server: DemoServer())

    let before = try await notifications.overview().unread.total
    let unread = try #require(
      try await notifications.page(kind: .unread, offset: 0, limit: 25).notifications.first
    )
    let after = try await notifications.archive(id: unread.id)

    #expect(after.unread.total == before - 1)
    #expect(after.archive.total > 0)
  }

  @Test func reEnteringTheDemoStartsFromTheSeedAgain() async throws {
    // A reviewer who stopped half the containers and came back should see the
    // intended dataset, not the wreckage of their last visit. `AppEnvironment
    // .demo` builds a fresh `DemoServer` each time, which is what this models —
    // there is no `reset()` to forget.
    let first = DemoDockerRepository(server: DemoServer())
    let running = try #require(try await first.containers().first(where: \.isRunning))
    _ = try await first.stop(id: running.id)
    let afterStop = try await first.containers().first { $0.id == running.id }
    #expect(afterStop?.isRunning == false)

    let second = DemoDockerRepository(server: DemoServer())

    #expect(try await second.containers().first { $0.id == running.id }?.isRunning == true)
  }
}
