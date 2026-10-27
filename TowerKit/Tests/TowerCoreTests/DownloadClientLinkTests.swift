import Foundation
import Testing

@testable import TowerCore

/// The rule that decides whether an *arr queue row links to a download client.
///
/// Worth its own suite because it is a **heuristic**: an *arr names its client
/// with a label the user chose inside that *arr, Tower knows instances named
/// here, and there is no shared identifier between them. Every case below is a
/// decision about what to do with that ambiguity, and the wrong answer sends
/// someone to another download's detail screen.
@Suite struct DownloadClientLinkTests {
  private func instance(
    _ kind: ServiceKind, _ name: String, id: String = UUID().uuidString
  ) -> ServiceInstance {
    ServiceInstance(
      id: UUID(uuidString: id) ?? UUID(),
      kind: kind, name: name, baseURL: URL(string: "http://192.0.2.1:6789")!,
      credentials: .usernamePassword(username: "u", password: "p"))
  }

  private let nzb = ServiceInstance(
    kind: .nzbget, name: "NZBGet", baseURL: URL(string: "http://192.0.2.1:6789")!,
    credentials: .usernamePassword(username: "u", password: "p"))
  private let radarr = ServiceInstance(
    kind: .radarr, name: "Radarr", baseURL: URL(string: "http://192.0.2.1:7878")!,
    credentials: .apiKey("k"))

  // MARK: - Matching

  @Test func usenetMatchesTheConfiguredNZBGetByName() {
    let link = DownloadClientLink.match(
      downloadProtocol: .usenet, downloadClient: "NZBGet", downloadID: "41",
      in: [radarr, nzb])

    #expect(link?.instance.id == nzb.id)
  }

  @Test func theDownloadIDIsLowerCased() {
    let link = DownloadClientLink.match(
      downloadProtocol: .usenet, downloadClient: "NZBGet", downloadID: "AB41", in: [nzb])

    #expect(link?.downloadID == "ab41")
  }

  @Test func theProtocolMatchIsCaseInsensitive() {
    let link = DownloadClientLink.match(
      downloadProtocol: ArrDownloadProtocol(apiValue: "Usenet"), downloadClient: "NZBGet",
      downloadID: "41", in: [nzb])

    #expect(link?.instance.id == nzb.id)
  }

  @Test func theNameMatchIsCaseAndWhitespaceInsensitive() {
    // The two names were typed by the same person into two different apps.
    let link = DownloadClientLink.match(
      downloadProtocol: .usenet, downloadClient: "  NZBGET ", downloadID: "41", in: [nzb])

    #expect(link?.instance.id == nzb.id)
  }

  @Test func aSingleConfiguredClientOfTheKindIsTakenEvenWithoutANameMatch() {
    // The *arr calls it "Main downloader" and Tower calls it "NZBGet".
    // There is nothing else it could be.
    let link = DownloadClientLink.match(
      downloadProtocol: .usenet, downloadClient: "Main downloader", downloadID: "41",
      in: [radarr, nzb])

    #expect(link?.instance.id == nzb.id)
  }

  @Test func aNamedMatchWinsOverTheOtherCandidates() {
    let fourK = instance(.nzbget, "nzb-4k")
    let link = DownloadClientLink.match(
      downloadProtocol: .usenet, downloadClient: "nzb-4k", downloadID: "41", in: [nzb, fourK])

    #expect(link?.instance.id == fourK.id)
  }

  // MARK: - When there must be no link

  @Test func twoCandidatesAndNoNameMatchProducesNoLink() {
    // Pointing at the wrong client would show someone else's download and
    // invite the user to delete it. No link is the safe answer.
    let fourK = instance(.nzbget, "nzb-4k")
    let link = DownloadClientLink.match(
      downloadProtocol: .usenet, downloadClient: "Some other nzb", downloadID: "41",
      in: [nzb, fourK])

    #expect(link == nil)
  }

  @Test func noConfiguredClientOfTheKindProducesNoLink() {
    #expect(
      DownloadClientLink.match(
        downloadProtocol: .usenet, downloadClient: "NZBGet", downloadID: "41",
        in: [radarr]) == nil)
    #expect(
      DownloadClientLink.match(
        downloadProtocol: .usenet, downloadClient: "NZBGet", downloadID: "41",
        in: []) == nil)
  }

  @Test func anItemWithNoDownloadIDProducesNoLink() {
    // Without an id there is nothing to point at, even when the client is
    // obvious.
    #expect(
      DownloadClientLink.match(
        downloadProtocol: .usenet, downloadClient: "NZBGet", downloadID: nil,
        in: [nzb]) == nil)
    #expect(
      DownloadClientLink.match(
        downloadProtocol: .usenet, downloadClient: "NZBGet", downloadID: "   ",
        in: [nzb]) == nil)
  }

  @Test func anUnknownProtocolProducesNoLink() {
    #expect(
      DownloadClientLink.match(
        downloadProtocol: .unknown, downloadClient: "NZBGet", downloadID: "41",
        in: [nzb]) == nil)
  }

  @Test func aProtocolTowerDoesNotNameProducesNoLink() {
    // Only usenet has a client in Tower. Any other value, even with an NZBGet
    // configured and named, must not link to it.
    #expect(
      DownloadClientLink.match(
        downloadProtocol: ArrDownloadProtocol(apiValue: "other"), downloadClient: "NZBGet",
        downloadID: "41", in: [nzb]) == nil)
  }
}

/// The protocol is the service's own string, and Tower names only usenet.
@Suite struct ArrDownloadProtocolTests {
  @Test func usenetIsRecognisedAndNamed() {
    let value = ArrDownloadProtocol(apiValue: "usenet")
    #expect(value == .usenet)
    #expect(value.isUsenet)
    #expect(value.displayName == "Usenet")
  }

  @Test func anyOtherValueIsKeptVerbatimAndShownAsNothing() {
    // Kept verbatim so a Prowlarr indexer edit sends back what it received.
    let value = ArrDownloadProtocol(apiValue: "other")
    #expect(value.apiValue == "other")
    #expect(!value.isUsenet)
    #expect(value.displayName == nil)
  }

  @Test func aMissingOrBlankValueIsUnknown() {
    #expect(ArrDownloadProtocol(apiValue: nil) == .unknown)
    #expect(ArrDownloadProtocol(apiValue: "  ") == .unknown)
    #expect(ArrDownloadProtocol.unknown.apiValue == nil)
    #expect(ArrDownloadProtocol.unknown.displayName == nil)
  }
}

/// The field the whole feature hangs on.
@Suite struct ArrQueueItemDownloadIDTests {
  @Test func anEmptyDownloadIDIsAbsentRatherThanEmpty() {
    // An empty string would satisfy `!= nil` and then match nothing, producing
    // a link that goes to a "not found" screen.
    let item = ArrQueueItem(
      id: 1, title: "x", mediaID: nil, sizeBytes: nil, sizeLeftBytes: nil, timeLeft: nil,
      estimatedCompletionTime: nil, status: .downloading, trackedStatus: .ok,
      trackedState: .downloading, errorMessage: nil, statusMessages: [],
      downloadProtocol: .usenet, downloadClient: "NZBGet", downloadID: "",
      indexer: nil, quality: nil)

    #expect(item.downloadID == nil)
  }

  @Test func theDownloadIDDefaultsToAbsent() {
    let item = ArrQueueItem(
      id: 1, title: "x", mediaID: nil, sizeBytes: nil, sizeLeftBytes: nil, timeLeft: nil,
      estimatedCompletionTime: nil, status: .downloading, trackedStatus: .ok,
      trackedState: .downloading, errorMessage: nil, statusMessages: [],
      downloadProtocol: .usenet, downloadClient: nil, indexer: nil, quality: nil)

    #expect(item.downloadID == nil)
  }
}
