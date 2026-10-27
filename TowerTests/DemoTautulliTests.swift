import Foundation
import Testing
import TowerCore
import TowerData

@testable import Tower

/// Demo mode's Tautulli, including terminating a stream in demo mode.
@MainActor
struct DemoTautulliTests {
  private func makeTautulli() -> (DemoTautulliRepository, DemoTautulliServer) {
    let server = DemoTautulliServer()
    let instance = DemoServices.instances.first { $0.kind == .tautulli }!
    return (DemoTautulliRepository(instance: instance, server: server), server)
  }

  // MARK: - The dataset

  @Test func theDemoHasATranscodeAlongsideStreamsThatCostNothing() async throws {
    // The demo needs a transcode beside direct streams: the contrast the
    // activity screen exists for.
    let (tautulli, _) = makeTautulli()

    let activity = try await tautulli.activity()

    #expect(activity.sessions.count == 3)
    #expect(activity.transcodeCount == 1)
    #expect(activity.directPlayCount == 1)
    #expect(activity.directStreamCount == 1)
    #expect(activity.sessions.contains(where: { $0.isVideoTranscoding }))
    #expect(activity.sessions.contains(where: { $0.transcodeProgressPercent != nil }))
    // A paused stream and a remote one, so neither treatment is untested.
    #expect(activity.sessions.contains(where: { $0.state == .paused }))
    #expect(activity.sessions.contains(where: { $0.location != .lan }))
  }

  @Test func theHeaderCountsAgreeWithTheSessions() async throws {
    let (tautulli, _) = makeTautulli()

    let activity = try await tautulli.activity()

    #expect(activity.streamCount == activity.sessions.count)
    #expect(
      activity.totalBandwidthKbps == activity.sessions.reduce(0) { $0 + $1.bandwidthKbps })
    #expect(activity.lanBandwidthKbps + activity.wanBandwidthKbps
      == activity.totalBandwidthKbps)
  }

  // MARK: - Terminating a stream

  @Test func terminatingRemovesTheStreamInDemoMode() async throws {
    let (tautulli, _) = makeTautulli()
    let target = try #require(
      try await tautulli.activity().sessions.first(where: { $0.isTranscoding }))

    try await tautulli.terminate(sessionKey: target.sessionKey, message: "Stopped from Tower")

    let after = try await tautulli.activity()
    #expect(!after.sessions.contains(where: { $0.sessionKey == target.sessionKey }))
    #expect(after.streamCount == 2)
    // The counters are derived from the sessions, so the header cannot say
    // "1 transcoding" over a list with none.
    #expect(after.transcodeCount == 0)
    #expect(after.totalBandwidthKbps < 24_500)
  }

  @Test func aTerminatedStreamTurnsUpInHistoryAsStopped() async throws {
    let (tautulli, _) = makeTautulli()
    let before = try await tautulli.history(filter: .none).totalCount
    let target = try #require(try await tautulli.activity().sessions.first)

    try await tautulli.terminate(sessionKey: target.sessionKey, message: nil)

    let history = try await tautulli.history(filter: .none)
    #expect(history.totalCount == before + 1)
    let newest = try #require(history.records.first)
    #expect(newest.title == target.title)
    #expect(newest.watchStatus == .stopped)
  }

  @Test func terminatingAnUnknownSessionChangesNothing() async throws {
    let (tautulli, _) = makeTautulli()

    try await tautulli.terminate(sessionKey: "no-such-session", message: nil)

    #expect(try await tautulli.activity().sessions.count == 3)
  }

  // MARK: - History, users, libraries

  @Test func theDemoHistoryFiltersCompose() async throws {
    let (tautulli, _) = makeTautulli()

    let all = try await tautulli.history(filter: .none)
    let episodes = try await tautulli.history(
      filter: TautulliHistoryFilter(mediaType: "episode"))
    let caseysEpisodes = try await tautulli.history(
      filter: TautulliHistoryFilter(userID: 5, mediaType: "episode"))
    let searched = try await tautulli.history(
      filter: TautulliHistoryFilter(userID: 5, mediaType: "episode", search: "Low Tide"))

    #expect(all.records.count == 4)
    #expect(episodes.records.count == 2)
    #expect(caseysEpisodes.records.count == 2)
    #expect(searched.records.count == 1)
    // `filteredCount` narrows with the filter; `totalCount` never does, which
    // is what makes "1 of 4" honest.
    #expect(searched.filteredCount == 1)
    #expect(searched.totalCount == 4)
  }

  @Test func theHistorySpansEveryWatchStatus() async throws {
    let (tautulli, _) = makeTautulli()

    let records = try await tautulli.history(filter: .none).records

    #expect(records.contains(where: { $0.watchStatus == .watched }))
    #expect(records.contains(where: { $0.watchStatus == .partial }))
    #expect(records.contains(where: { $0.watchStatus == .stopped }))
  }

  @Test func theUsersIncludeOneWhoHasNeverWatchedAnything() async throws {
    let (tautulli, _) = makeTautulli()

    let users = try await tautulli.users()

    #expect(users.count == 4)
    // The case that proves the row says "Never seen" rather than 1970.
    #expect(users.contains(where: { $0.lastSeen == nil && $0.plays == 0 }))
    #expect(users.contains(where: { !$0.isActive }))
    #expect(users.contains(where: { $0.plays > 100 }))
  }

  @Test func everyoneStreamingIsAUser() {
    let users = Set(DemoTautulliFixtures.users.map(\.id))

    for session in DemoTautulliFixtures.sessions() {
      #expect(session.userID.map(users.contains) == true, "\(session.user) is not in users")
    }
  }

  @Test func eachUserAndLibraryWasLastActiveAtItsNewestPlay() throws {
    // Newest first, as Tautulli returns it.
    let history = DemoTautulliFixtures.history()

    for user in DemoTautulliFixtures.users where user.plays > 0 {
      let newest = try #require(history.first { $0.userID == user.id }, "\(user.name)")
      #expect(user.lastPlayed == newest.title, "\(user.name)")
      let seen = try #require(user.lastSeen, "\(user.name)")
      let played = try #require(newest.date)
      #expect(abs(seen.timeIntervalSince(played)) < 60, "\(user.name)")
    }

    let mediaType = ["movie": "movie", "show": "episode", "artist": "track"]
    for library in DemoTautulliFixtures.libraries {
      let kind = try #require(library.type.flatMap { mediaType[$0] }, "\(library.name)")
      let newest = try #require(history.first { $0.mediaType == kind }, "\(library.name)")
      let accessed = try #require(library.lastAccessed, "\(library.name)")
      let date = try #require(newest.date)
      #expect(abs(accessed.timeIntervalSince(date)) < 60, "\(library.name)")
    }
  }

  @Test func theLibrariesCoverTheThreeTieredTypes() async throws {
    let (tautulli, _) = makeTautulli()

    let libraries = try await tautulli.libraries()

    #expect(libraries.contains(where: { $0.typeDisplayName == "Movies" && $0.parentCount == nil }))
    #expect(libraries.contains(where: { $0.typeDisplayName == "TV Shows" && $0.childCount != nil }))
    #expect(libraries.contains(where: { $0.typeDisplayName == "Music" }))
  }

  // MARK: - Wiring

  @Test func theDemoEnvironmentServesTautulli() async throws {
    let environment = AppEnvironment.demo
    let instance = try #require(DemoServices.instances.first { $0.kind == .tautulli })

    #expect(environment.makeServiceRepository(instance) is DemoTautulliRepository)
  }

  @Test func everyDemoInstanceHasARepository() async throws {
    // A hub row that answers `nil` here would render the placeholder screen in
    // the App Store's own screenshots.
    let environment = AppEnvironment.demo

    for instance in DemoServices.instances {
      #expect(
        environment.makeServiceRepository(instance) != nil,
        "no demo repository for \(instance.kind)")
    }
  }
}
