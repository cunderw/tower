import Foundation
import Testing
import TowerCore

@testable import TowerData

/// `LiveTautulliRepository` end to end.
///
/// Every fixture here is deliberately **mixed-type**: the same field arrives
/// as a number in one row and a numeric string in the next, because that is
/// what Tautulli does across versions and even within one payload. A test
/// suite built from tidy JSON would prove nothing about the only decoding risk
/// this service actually has.
private func fixture(_ name: String) throws -> Data {
  let url = try #require(
    Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures/Tautulli"),
    "missing fixture \(name)")
  return try Data(contentsOf: url)
}

private func makeRepository(host: String) -> LiveTautulliRepository {
  let instance = ServiceInstance(
    kind: .tautulli, name: "Tautulli", baseURL: URL(string: "http://\(host)")!,
    credentials: .apiKey("secret-key"))
  return LiveTautulliRepository(
    instance: instance,
    client: ServiceHTTPClient(
      instance: instance, sessionConfiguration: ServiceStubURLProtocol.configuration()))
}

private func stub(host: String, _ body: Data) {
  ServiceStubURLProtocol.stub(host: host, reply: .init(status: 200, body: body))
}

private func requests(_ host: String) -> [URLRequest] {
  ServiceStubURLProtocol.requests(host: host)
}

private func query(_ request: URLRequest) -> [String: String] {
  let components = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)
  return Dictionary(
    (components?.queryItems ?? []).map { ($0.name, $0.value ?? "") },
    uniquingKeysWith: { first, _ in first })
}

// MARK: - Activity

@Suite struct TautulliActivityTests {
  @Test func theHeaderCountsAndBandwidthDecodeFromMixedTypes() async throws {
    let host = "tt-activity.invalid"
    stub(host: host, try fixture("activity.json"))

    let activity = try await makeRepository(host: host).activity()

    #expect(activity.streamCount == 3)
    #expect(activity.directPlayCount == 1)
    #expect(activity.directStreamCount == 1)
    #expect(activity.transcodeCount == 1)
    #expect(activity.totalBandwidthKbps == 24_500)
    #expect(activity.lanBandwidthKbps == 20_000)
    #expect(activity.wanBandwidthKbps == 4_500)
    #expect(activity.sessions.count == 3)
  }

  @Test func aDirectPlayStreamMapsWithItsEpisodeContext() async throws {
    let host = "tt-direct.invalid"
    stub(host: host, try fixture("activity.json"))

    let session = try #require(
      try await makeRepository(host: host).activity().sessions
        .first(where: { $0.sessionKey == "312" }))

    #expect(session.user == "Casey")
    #expect(session.title == "Northern Lights - The Missing Signal")
    // The show's name is already in the title, so the context line is the
    // episode number alone rather than a repeat.
    #expect(session.subtitle == "S02E11")
    #expect(session.state == .playing)
    #expect(session.decision == .directPlay)
    #expect(session.isTranscoding == false)
    #expect(session.location == .lan)
    #expect(session.isSecure)
    #expect(session.bandwidthKbps == 20_000)
    #expect(session.progressPercent == 37)
    #expect(session.durationMilliseconds == 3_720_000)
    // A direct play has no transcode to report progress for; 0 would render
    // as a transcode stuck at the start.
    #expect(session.transcodeProgressPercent == nil)
  }

  @Test func aTranscodingStreamMapsItsDecisionAndRelayedLocation() async throws {
    let host = "tt-transcode.invalid"
    stub(host: host, try fixture("activity.json"))

    let session = try #require(
      try await makeRepository(host: host).activity().sessions
        .first(where: { $0.sessionKey == "313" }))

    #expect(session.decision == .transcode)
    #expect(session.videoDecision == .transcode)
    // Plex says `copy` where its own UI says "direct stream".
    #expect(session.audioDecision == .directStream)
    #expect(session.isTranscoding)
    #expect(session.isVideoTranscoding)
    #expect(session.transcodeProgressPercent == 12)
    // `relayed` wins over `location`: a relayed stream is capped at 2 Mbps
    // and looks like a bad transcode if it is reported as plain remote.
    #expect(session.location == .relayed)
    #expect(session.isSecure == false)
    // An empty `friendly_name` falls back to the username, not to "".
    #expect(session.user == "guest")
    #expect(session.subtitle == nil)
  }

  @Test func anAudioOnlyCopyCountsAsDirectStreamAndSurvivesJunkNumbers() async throws {
    let host = "tt-copy.invalid"
    stub(host: host, try fixture("activity.json"))

    let session = try #require(
      try await makeRepository(host: host).activity().sessions
        .first(where: { $0.sessionKey == "314" }))

    #expect(session.decision == .directStream)
    #expect(session.state == .paused)
    // "n/a" and "" are Tautulli's ways of saying nothing, and neither is a
    // decoding failure for the whole payload.
    #expect(session.progressPercent == 0)
    #expect(session.viewOffsetMilliseconds == 0)
    #expect(session.durationMilliseconds == 240_000)
    #expect(session.isTranscoding == false)
  }

  @Test func anIdleServerIsEmptyRatherThanAnError() async throws {
    let host = "tt-idle.invalid"
    stub(
      host: host,
      Data(#"{"response":{"result":"success","message":null,"data":null}}"#.utf8))

    let activity = try await makeRepository(host: host).activity()

    #expect(activity == .empty)
  }

  @Test func theApiKeyTravelsAsAQueryParameterNotAHeader() async throws {
    let host = "tt-auth.invalid"
    stub(host: host, try fixture("activity.json"))

    _ = try await makeRepository(host: host).activity()

    let request = try #require(requests(host).first)
    #expect(query(request)["apikey"] == "secret-key")
    #expect(query(request)["cmd"] == "get_activity")
    // Tautulli ignores the header form, so sending it too would be a second
    // copy of the key on the wire for no benefit.
    #expect(request.value(forHTTPHeaderField: "X-Api-Key") == nil)
  }
}

// MARK: - The 200-for-everything trap

@Suite struct TautulliEnvelopeTests {
  @Test func aRejectedKeyIsUnauthorizedDespiteTheHttp200() async throws {
    let host = "tt-badkey.invalid"
    stub(host: host, try fixture("bad-key.json"))

    // The status code says success; only the envelope disagrees.
    await #expect(throws: AppError.unauthorized) {
      try await makeRepository(host: host).activity()
    }
  }

  @Test func anotherRefusalKeepsTautullisOwnWording() async throws {
    let host = "tt-refused.invalid"
    stub(
      host: host,
      Data(#"{"response":{"result":"error","message":"Invalid cmd","data":null}}"#.utf8))

    await #expect(throws: AppError.unknown("Invalid cmd")) {
      try await makeRepository(host: host).activity()
    }
  }

  @Test func aRefusalWithNoMessageStillReadsAsARefusal() async throws {
    let host = "tt-silent.invalid"
    stub(host: host, Data(#"{"response":{"result":"error","data":null}}"#.utf8))

    await #expect(throws: AppError.unknown("Tautulli refused the request.")) {
      try await makeRepository(host: host).activity()
    }
  }
}

// MARK: - Terminate

@Suite struct TautulliTerminateTests {
  @Test func terminatingSendsTheSessionKeyAndMessage() async throws {
    let host = "tt-terminate.invalid"
    stub(host: host, try fixture("terminate-success.json"))

    try await makeRepository(host: host).terminate(
      sessionKey: "313", message: "Stopped from Tower")

    let request = try #require(requests(host).first)
    let query = query(request)
    #expect(query["cmd"] == "terminate_session")
    #expect(query["session_key"] == "313")
    #expect(query["message"] == "Stopped from Tower")
  }

  @Test func aTerminateWithoutAMessageOmitsTheParameter() async throws {
    let host = "tt-terminate-quiet.invalid"
    stub(host: host, try fixture("terminate-success.json"))

    try await makeRepository(host: host).terminate(sessionKey: "313", message: nil)

    #expect(query(try #require(requests(host).first))["message"] == nil)
  }

  @Test func aFailedTerminateThrowsRatherThanReportingSuccess() async throws {
    let host = "tt-terminate-fail.invalid"
    stub(
      host: host,
      Data(#"{"response":{"result":"error","message":"Session not found","data":null}}"#.utf8))

    await #expect(throws: AppError.unknown("Session not found")) {
      try await makeRepository(host: host).terminate(sessionKey: "999", message: nil)
    }
  }
}

// MARK: - History

@Suite struct TautulliHistoryTests {
  @Test func historyRowsMapWithTheirTotals() async throws {
    let host = "tt-history.invalid"
    stub(host: host, try fixture("history.json"))

    let page = try await makeRepository(host: host).history(filter: .none)

    #expect(page.records.count == 2)
    #expect(page.filteredCount == 2)
    // The unfiltered total is what makes "2 of 1,204" honest.
    #expect(page.totalCount == 1_204)

    let episode = try #require(page.records.first)
    #expect(episode.id == 88_031)
    #expect(episode.user == "Casey")
    #expect(episode.subtitle == "S02E12")
    #expect(episode.watchStatus == .watched)
    #expect(episode.percentComplete == 100)
    #expect(episode.playDurationSeconds == 3_702)
    #expect(episode.decision == .directPlay)
    #expect(episode.date == Date(timeIntervalSince1970: 1_755_043_200))
  }

  @Test func aHalfWatchedRowIsPartialNotWatched() async throws {
    let host = "tt-history-partial.invalid"
    stub(host: host, try fixture("history.json"))

    let record = try #require(
      try await makeRepository(host: host).history(filter: .none).records.last)

    // `watched_status` is a fraction, not a flag — 0.5 is Tautulli saying
    // "started but under the threshold".
    #expect(record.watchStatus == .partial)
    #expect(record.percentComplete == 62)
    #expect(record.user == "guest")
  }

  @Test func theFilterIsSentToTautulliRatherThanAppliedLocally() async throws {
    let host = "tt-history-filter.invalid"
    stub(host: host, try fixture("history.json"))

    _ = try await makeRepository(host: host).history(
      filter: TautulliHistoryFilter(userID: 5, mediaType: "episode", search: "  lights  "),
      start: 50, length: 25)

    let query = query(try #require(requests(host).first))
    #expect(query["cmd"] == "get_history")
    #expect(query["user_id"] == "5")
    #expect(query["media_type"] == "episode")
    #expect(query["search"] == "lights")
    #expect(query["start"] == "50")
    #expect(query["length"] == "25")
    #expect(query["order_column"] == "date")
    #expect(query["order_dir"] == "desc")
  }

  @Test func anEmptyFilterSendsNoFilterParameters() async throws {
    let host = "tt-history-nofilter.invalid"
    stub(host: host, try fixture("history.json"))

    _ = try await makeRepository(host: host).history(
      filter: TautulliHistoryFilter(search: "   "))

    let query = query(try #require(requests(host).first))
    #expect(query["user_id"] == nil)
    #expect(query["media_type"] == nil)
    // Whitespace is not a search — sending it would filter everything out.
    #expect(query["search"] == nil)
  }
}

// MARK: - Users and libraries

@Suite struct TautulliUsersAndLibrariesTests {
  @Test func usersMapWithTheirPerUserStats() async throws {
    let host = "tt-users.invalid"
    stub(host: host, try fixture("users.json"))

    let users = try await makeRepository(host: host).users()

    #expect(users.count == 2)
    let casey = try #require(users.first)
    #expect(casey.id == 5)
    #expect(casey.name == "Casey")
    #expect(casey.plays == 412)
    #expect(casey.totalTimeSeconds == 1_480_000)
    #expect(casey.lastSeen == Date(timeIntervalSince1970: 1_755_043_200))
    #expect(casey.lastPlayed == "Northern Lights - Aftermath")
    #expect(casey.isActive)

    let guest = try #require(users.last)
    // Never-seen users have a null `last_seen`, which is not 1970.
    #expect(guest.lastSeen == nil)
    #expect(guest.lastPlayed == nil)
    #expect(guest.name == "guest")
    #expect(guest.isActive == false)
    #expect(guest.thumbnailPath == "/users/7.png")
  }

  @Test func theUsersCallAsksForTheTableFormWithItsStats() async throws {
    let host = "tt-users-query.invalid"
    stub(host: host, try fixture("users.json"))

    _ = try await makeRepository(host: host).users()

    // `get_users` exists and returns no play counts, so the command matters.
    #expect(query(try #require(requests(host).first))["cmd"] == "get_users_table")
  }

  @Test func librariesMapIncludingTheirTieredCounts() async throws {
    let host = "tt-libraries.invalid"
    stub(host: host, try fixture("libraries.json"))

    let libraries = try await makeRepository(host: host).libraries()

    #expect(libraries.count == 3)

    let movies = try #require(libraries.first(where: { $0.id == 1 }))
    #expect(movies.name == "Movies")
    #expect(movies.typeDisplayName == "Movies")
    #expect(movies.count == 500)
    // A film library has no middle tier, and 0 would be a wrong answer.
    #expect(movies.parentCount == nil)
    #expect(movies.childCount == nil)
    #expect(movies.plays == 1_200)

    let shows = try #require(libraries.first(where: { $0.id == 2 }))
    #expect(shows.typeDisplayName == "TV Shows")
    #expect(shows.count == 100)
    #expect(shows.parentCount == 400)
    #expect(shows.childCount == 6_000)
    #expect(shows.thumbnailPath == nil)

    let music = try #require(libraries.first(where: { $0.id == 3 }))
    #expect(music.typeDisplayName == "Music")
    #expect(music.lastAccessed == nil)
  }

  @Test func theLibrariesCallAsksForTheTableForm() async throws {
    let host = "tt-libraries-query.invalid"
    stub(host: host, try fixture("libraries.json"))

    _ = try await makeRepository(host: host).libraries()

    #expect(query(try #require(requests(host).first))["cmd"] == "get_libraries_table")
  }
}
