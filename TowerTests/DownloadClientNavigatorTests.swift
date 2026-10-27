import Foundation
import Testing
import TowerCore
import TowerData

@testable import Tower

/// The navigator's extra rule on top of `DownloadClientLink`'s matching: a
/// match only becomes a link if Tower can actually open it.
@MainActor
@Suite
struct DownloadClientNavigatorTests {
  private let nzb = ServiceInstance(
    kind: .nzbget, name: "NZBGet", baseURL: URL(string: "http://192.0.2.1:6789")!,
    credentials: .usernamePassword(username: "u", password: "p"))

  private func item(
    downloadClient: String? = "NZBGet", downloadID: String? = "AB41",
    downloadProtocol: ArrDownloadProtocol = .usenet
  ) -> ArrQueueItem {
    ArrQueueItem(
      id: 1, title: "Example", mediaID: nil, sizeBytes: 100, sizeLeftBytes: 50, timeLeft: nil,
      estimatedCompletionTime: nil, status: .downloading, trackedStatus: .ok,
      trackedState: .downloading, errorMessage: nil, statusMessages: [],
      downloadProtocol: downloadProtocol, downloadClient: downloadClient,
      downloadID: downloadID, indexer: nil, quality: nil)
  }

  @Test func aMatchWithABuildableRepositoryLinks() {
    let navigator = DownloadClientNavigator(
      instances: [nzb],
      makeRepository: { instance in LiveNZBGetRepository(instance: instance) })

    let link = navigator.link(for: item())

    #expect(link?.instance.id == nzb.id)
    #expect(link?.downloadID == "ab41")
  }

  @Test func aConfiguredClientTowerHasNoRepositoryForDoesNotLink() {
    // An instance can be configured while Tower has no client for its kind.
    // A link there would dead-end.
    let navigator = DownloadClientNavigator(
      instances: [nzb], makeRepository: { _ in nil })

    #expect(navigator.link(for: item()) == nil)
  }

  @Test func aRowWithNothingToMatchDoesNotLink() {
    let navigator = DownloadClientNavigator(
      instances: [nzb],
      makeRepository: { instance in LiveNZBGetRepository(instance: instance) })

    #expect(navigator.link(for: item(downloadID: nil)) == nil)
    #expect(navigator.link(for: item(downloadProtocol: .unknown)) == nil)
    // A protocol Tower has no client for never links, even to a named NZBGet.
    #expect(
      navigator.link(for: item(downloadProtocol: ArrDownloadProtocol(apiValue: "other"))) == nil)
  }

  @Test func noConfiguredClientsMeansNoLinks() {
    let navigator = DownloadClientNavigator(
      instances: [],
      makeRepository: { instance in LiveNZBGetRepository(instance: instance) })

    #expect(navigator.link(for: item()) == nil)
  }

  @Test func everyDemoQueueLinkResolvesToTheDemoNZBGet() async throws {
    // Demo mode configures an NZBGet, so a row that links must land on it, and
    // at least one row has to link or a reviewer never sees the feature.
    let environment = AppEnvironment.demo
    let navigator = DownloadClientNavigator(
      instances: DemoServices.instances, makeRepository: environment.makeServiceRepository)

    let radarrInstance = try #require(DemoServices.instances.first { $0.kind == .radarr })
    let radarr = try #require(
      environment.makeServiceRepository(radarrInstance) as? any RadarrRepositoryProtocol)
    let links = try await radarr.queue().items.compactMap { navigator.link(for: $0) }

    #expect(!links.isEmpty, "no demo queue row links to a download client")
    #expect(links.allSatisfy { $0.instance.kind == .nzbget })
  }
}
