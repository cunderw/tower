import Foundation
import Testing
import TowerCore
import TowerData

@testable import Tower

/// Demo mode's NZBGet and its mutations, including the NZBGet actions and the
/// queue → client link checked in demo mode.
@MainActor
struct DemoDownloadClientsTests {
  private func makeNZBGet() -> (DemoNZBGetRepository, DemoNZBServer) {
    let server = DemoNZBServer()
    let instance = DemoServices.instances.first { $0.kind == .nzbget }!
    return (DemoNZBGetRepository(instance: instance, server: server), server)
  }

  // MARK: - The dataset

  @Test func theNZBQueueAndHistoryShowBothOutcomes() async throws {
    let (nzbget, _) = makeNZBGet()

    let queue = try await nzbget.queue()
    let history = try await nzbget.history()

    #expect(queue.count >= 3)
    // The post-processing row is the one with no download speed that reads as
    // stalled unless the UI distinguishes it.
    #expect(queue.contains { $0.status.isPostProcessing })
    #expect(queue.contains { $0.status.isPaused })
    #expect(history.contains { $0.isSuccess })
    #expect(history.contains { !$0.isSuccess }, "no failure to demo Retry against")
  }

  // MARK: - NZBGet actions in demo mode

  @Test func retryingHistoryReEnqueuesTheItemInDemoMode() async throws {
    let (nzbget, _) = makeNZBGet()
    let failed = try #require(try await nzbget.history().first { !$0.isSuccess })
    let queueBefore = try await nzbget.queue().count

    try await nzbget.retryHistory(ids: [failed.id])

    let queue = try await nzbget.queue()
    #expect(queue.count == queueBefore + 1, "the retried item never reached the queue")
    #expect(queue.contains { $0.name == failed.name })
    #expect(
      try await nzbget.history().contains { $0.id == failed.id } == false,
      "the history entry survived the retry")
  }

  @Test func priorityReordersTheDemoQueue() async throws {
    // NZBGet orders its queue by priority, so the demo has to reorder too or
    // changing a priority shows nothing.
    let (nzbget, _) = makeNZBGet()
    let queue = try await nzbget.queue()
    let last = try #require(queue.last)

    try await nzbget.setPriority(.force, ids: [last.id])

    let reordered = try await nzbget.queue()
    #expect(reordered.first?.id == last.id, "the queue did not reorder")
    #expect(reordered.first?.priority == .force)
  }

  @Test func theNZBSpeedLimitAndGlobalPauseStick() async throws {
    let (nzbget, _) = makeNZBGet()

    try await nzbget.setSpeedLimit(bytesPerSecond: 5_242_880)
    #expect(try await nzbget.status().speedLimitBytesPerSecond == 5_242_880)

    try await nzbget.pauseAll()
    let paused = try await nzbget.status()
    #expect(paused.isDownloadPaused)
    // Derived, so pausing the server visibly drops the rate.
    #expect(paused.downloadRateBytesPerSecond == 0)

    try await nzbget.resumeAll()
    #expect(try await nzbget.status().isDownloadPaused == false)
  }

  // MARK: - The queue → client link in demo mode

  @Test func theUsenetQueueRowLinksToTheDemoNZBGet() async throws {
    let environment = AppEnvironment.demo
    let navigator = DownloadClientNavigator(
      instances: DemoServices.instances, makeRepository: environment.makeServiceRepository)

    let sonarrInstance = try #require(DemoServices.instances.first { $0.kind == .sonarr })
    let sonarr = try #require(
      environment.makeServiceRepository(sonarrInstance) as? any SonarrRepositoryProtocol)
    // The row seeded with the shared NZB id. The other demo rows carry no
    // client id, so they link nowhere.
    let usenetRow = try #require(
      try await sonarr.queue().items.first {
        $0.downloadID == String(DemoDownloadIDs.northernLightsNZB)
      })
    #expect(usenetRow.downloadProtocol == .usenet)

    let link = try #require(navigator.link(for: usenetRow))
    #expect(link.instance.kind == .nzbget)

    // The row is blocked at import, so its download has finished and sits in
    // NZBGet's history rather than its queue.
    let nzbget = try #require(
      environment.makeServiceRepository(link.instance) as? any NZBGetRepositoryProtocol)
    let finished = try #require(
      try await nzbget.history().first { String($0.id) == link.downloadID },
      "the queue row linked to an NZB the demo client doesn't have")
    #expect(finished.isSuccess)
    #expect(
      try await nzbget.queue().contains { String($0.id) == link.downloadID } == false,
      "an import-blocked row links a download that is still downloading")
  }

  // MARK: - Isolation

  @Test func reEnteringTheDemoStartsFromTheSeedAgain() async throws {
    // A reviewer who paused everything and came back sees the intended stack.
    let (first, _) = makeNZBGet()
    try await first.pauseAll()
    #expect(try await first.status().isDownloadPaused)

    let (second, _) = makeNZBGet()
    #expect(try await second.status().isDownloadPaused == false)
  }
}
