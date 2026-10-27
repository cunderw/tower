import Foundation
import Testing
import TowerCore
@testable import TowerData

/// `ArrClientCore` end to end: each endpoint answered with a committed fixture
/// with invented values, asserted on the `TowerCore` values that come out.
///
/// Driven through the real `ServiceHTTPClient` and a stubbed `URLProtocol`
/// rather than by calling the DTOs' `domain` properties directly — that way the
/// path, the query, the decoding, and the mapping are all under test, and a
/// wrong API version or a missing query parameter shows up here rather than as
/// a 404 on someone's server.
private func fixture(_ name: String) throws -> Data {
  let url = try #require(
    Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures/Arr"),
    "missing fixture \(name)")
  return try Data(contentsOf: url)
}

private func makeCore(
  host: String, fixture name: String, apiPath: String = "api/v3"
) throws -> ArrClientCore {
  let body = try fixture(name)
  ServiceStubURLProtocol.stub(
    host: host, reply: ServiceStubURLProtocol.Reply(status: 200, body: body))
  return makeCore(host: host, apiPath: apiPath)
}

private func makeCore(host: String, apiPath: String = "api/v3") -> ArrClientCore {
  let instance = ServiceInstance(
    kind: .radarr, name: "Radarr", baseURL: URL(string: "http://\(host)")!,
    credentials: .apiKey("k"))
  return ArrClientCore(
    client: ServiceHTTPClient(
      instance: instance, sessionConfiguration: ServiceStubURLProtocol.configuration()),
    apiPath: apiPath)
}

private func lastRequest(_ host: String) throws -> URLRequest {
  try #require(ServiceStubURLProtocol.requests(host: host).last)
}

// MARK: - Queue

@Test func queueMapsARunningDownload() async throws {
  let host = "arr-queue.test"
  let core = try makeCore(host: host, fixture: "queue.json")

  let page = try await core.queue()

  #expect(page.page == 1)
  #expect(page.totalRecords == 3)
  let item = try #require(page.items.first)
  #expect(item.id == 41)
  #expect(item.title == "Example.Movie.2024.1080p.BluRay.x264-GROUP")
  #expect(item.mediaID == 812)
  #expect(item.sizeBytes == 24_696_061_952)
  #expect(item.sizeLeftBytes == 8_232_020_650)
  #expect(item.timeLeft == "00:12:34")
  #expect(item.status == .downloading)
  #expect(item.trackedState == .downloading)
  #expect(item.downloadProtocol == .usenet)
  #expect(item.downloadClient == "NZBGet")
  #expect(item.quality == "Bluray-1080p")
  #expect(item.progress.map { ($0 * 100).rounded() } == 67)
  #expect(!item.needsAttention)
}

@Test func queueSurfacesAStuckImportAsNeedingAttention() async throws {
  // The row this screen exists for: downloaded, and going nowhere.
  let host = "arr-queue-stuck.test"
  let core = try makeCore(host: host, fixture: "queue.json")

  let items = try await core.queue().items
  let stuck = try #require(items.first { $0.id == 42 })

  #expect(stuck.trackedStatus == .warning)
  #expect(stuck.trackedState == .importBlocked)
  #expect(stuck.statusMessages == ["No files found are eligible for import"])
  #expect(stuck.needsAttention)
  #expect(stuck.progress == 1)
}

@Test func anUnrecognisedQueueRowDegradesToUnknownRatherThanFailingThePage() async throws {
  // The third fixture row carries invented enum members and a null title —
  // what a future *arr release looks like from here. It must cost that row its
  // labels, not the other two rows their screen.
  let host = "arr-queue-future.test"
  let core = try makeCore(host: host, fixture: "queue.json")

  let page = try await core.queue()

  #expect(page.items.count == 3, "one unrecognised row must not drop the page")
  let odd = try #require(page.items.first { $0.id == 43 })
  #expect(odd.status == .unknown)
  #expect(odd.trackedStatus == .unknown)
  #expect(odd.trackedState == .unknown)
  // The protocol is carried verbatim rather than mapped, so an invented one
  // is simply a value Tower does not name.
  #expect(!odd.downloadProtocol.isUsenet)
  #expect(odd.downloadProtocol.displayName == nil)
  #expect(odd.displayTitle == "Untitled release")
  #expect(odd.mediaID == nil)
  #expect(odd.progress == nil, "a zero-byte item has no honest progress figure")
}

@Test func queueAsksForUnknownItemsToo() async throws {
  // The *arr default hides items it can't match to a library entry — which is
  // exactly the stuck download someone opens this screen to find.
  let host = "arr-queue-query.test"
  let core = try makeCore(host: host, fixture: "queue.json")

  _ = try await core.queue(page: 2, pageSize: 25)

  let query = try #require(lastRequest(host).url?.query())
  #expect(query.contains("page=2"))
  #expect(query.contains("pageSize=25"))
  #expect(query.contains("includeUnknownMovieItems=true"))
  #expect(query.contains("includeUnknownSeriesItems=true"))
  #expect(query.contains("includeUnknownArtistItems=true"))
}

@Test func removingAQueueItemPassesBothDecisionsThrough() async throws {
  let host = "arr-queue-remove.test"
  ServiceStubURLProtocol.stub(host: host, reply: .json("{}"))
  let core = makeCore(host: host)

  try await core.removeQueueItem(id: 41, removeFromClient: false, blocklist: true)

  let request = try lastRequest(host)
  #expect(request.httpMethod == "DELETE")
  #expect(request.url?.path() == "/api/v3/queue/41")
  let query = try #require(request.url?.query())
  #expect(query.contains("removeFromClient=false"))
  #expect(query.contains("blocklist=true"))
}

// MARK: - Calendar

@Test func theRadarrCalendarPrefersTheDigitalReleaseDate() async throws {
  // "When can I watch it" is the question the calendar answers, and for a
  // Radarr row that is the digital release, not the cinema date.
  let host = "arr-calendar-radarr.test"
  let core = try makeCore(host: host, fixture: "calendar-radarr.json")

  let entries = try await core.calendar(start: .distantPast, end: .distantFuture)

  #expect(entries.count == 2)
  let first = try #require(entries.first)
  #expect(first.title == "Example Movie")
  #expect(first.subtitle == "2024")
  #expect(first.isMonitored)
  #expect(!first.hasFile)
  #expect(first.date == ISO8601DateFormatter().date(from: "2024-09-03T00:00:00Z"))
}

@Test func theSonarrCalendarLeadsWithTheSeriesAndCodesTheEpisode() async throws {
  // Sonarr's calendar rows are episodes, so the headline is the series — the
  // opposite of Radarr's shape, and the reason this mapping is shared.
  let host = "arr-calendar-sonarr.test"
  let core = try makeCore(host: host, fixture: "calendar-sonarr.json")

  let entries = try await core.calendar(start: .distantPast, end: .distantFuture)
  let entry = try #require(entries.first)

  #expect(entry.title == "Example Series")
  #expect(entry.subtitle == "S02E07 · The One With The Pilot")
  #expect(entry.date == ISO8601DateFormatter().date(from: "2026-08-14T01:00:00Z"))
}

@Test func theCalendarIsRequestedAsPlainDates() async throws {
  let host = "arr-calendar-query.test"
  let core = try makeCore(host: host, fixture: "calendar-radarr.json")
  let start = try #require(ISO8601DateFormatter().date(from: "2026-08-13T22:00:00Z"))
  let end = try #require(ISO8601DateFormatter().date(from: "2026-08-20T22:00:00Z"))

  _ = try await core.calendar(start: start, end: end)

  let query = try #require(lastRequest(host).url?.query())
  #expect(query.contains("start=2026-08-13"))
  #expect(query.contains("end=2026-08-20"))
  // Unmonitored rows included: a calendar that silently hides them looks empty
  // for a library someone hasn't finished setting up.
  #expect(query.contains("unmonitored=true"))
}

// MARK: - History

@Test func historyMapsEachEventTypeIncludingTheServiceSpecificSpellings() async throws {
  // `movieFileDeleted` and `episodeFileDeleted` are the same event to a user;
  // absorbing that difference is what the shared layer is for.
  let host = "arr-history.test"
  let core = try makeCore(host: host, fixture: "history.json")

  let page = try await core.history()

  #expect(page.totalRecords == 214)
  #expect(!page.isLastPage)
  #expect(page.records.map(\.event) == [.grabbed, .downloadFailed, .fileDeleted, .unknown])
  let grabbed = try #require(page.records.first)
  #expect(grabbed.sourceTitle == "Example.Movie.2024.1080p.BluRay.x264-GROUP")
  #expect(grabbed.quality == "Bluray-1080p")
  #expect(grabbed.mediaID == 812)
  #expect(page.records[1].event.isFailure)
  // A record with no source title still reads as something.
  #expect(page.records[3].displayTitle == "Unknown")
}

@Test func historyIsRequestedNewestFirst() async throws {
  let host = "arr-history-query.test"
  let core = try makeCore(host: host, fixture: "history.json")

  _ = try await core.history(page: 3, pageSize: 10)

  let query = try #require(lastRequest(host).url?.query())
  #expect(query.contains("sortKey=date"))
  #expect(query.contains("sortDirection=descending"))
  #expect(query.contains("page=3"))
}

// MARK: - Health

@Test func healthIsSortedWorstFirstAndKeepsItsWikiLinks() async throws {
  let host = "arr-health.test"
  let core = try makeCore(host: host, fixture: "health.json")

  let checks = try await core.health()

  #expect(checks.map(\.severity) == [.error, .warning, .notice, .unknown])
  #expect(checks.first?.source == "IndexerStatusCheck")
  #expect(checks.first?.wikiURL?.host() == "wiki.servarr.com")
  // The last fixture row has an unrecognised type, no id, and a null message.
  let mystery = try #require(checks.last)
  #expect(mystery.severity == .unknown)
  #expect(!mystery.message.isEmpty, "a health row with no message still has to render")
  #expect(mystery.wikiURL == nil)
}

// MARK: - Disk space

@Test func diskSpaceMapsUsageAndSurvivesAZeroSizedMount() async throws {
  let host = "arr-disk.test"
  let core = try makeCore(host: host, fixture: "diskspace.json")

  let disks = try await core.diskSpace()

  #expect(disks.count == 3)
  let data = try #require(disks.first)
  #expect(data.path == "/data")
  #expect(data.label == "data")
  #expect(data.usedBytes == 12_000_138_625_024 - 3_221_225_472_000)
  #expect(data.usedFraction.map { ($0 * 100).rounded() } == 73)
  // An empty label is nil, not an empty string that renders as a gap.
  #expect(disks[1].label == nil)
  // And a zero-sized mount has no fraction rather than a full bar or a crash.
  #expect(disks[2].usedFraction == nil)
}

// MARK: - System status and commands

@Test func systemStatusMapsTheFieldsTheMoreScreenShows() async throws {
  let host = "arr-status.test"
  let core = try makeCore(host: host, fixture: "system-status.json")

  let status = try await core.systemStatus()

  #expect(status.appName == "Radarr")
  #expect(status.version == "5.14.0.9383")
  #expect(status.osName == "ubuntu")
  #expect(status.isDocker)
  #expect(status.startTime == ISO8601DateFormatter().date(from: "2026-01-01T00:00:00Z"))
}

@Test func commandsPreferTheReadableName() async throws {
  let host = "arr-commands.test"
  let core = try makeCore(host: host, fixture: "commands.json")

  let commands = try await core.commands()

  #expect(commands.map(\.name) == ["Rss Sync", "Refresh Movie"])
  #expect(commands.map(\.status) == [.started, .completed])
  #expect(commands[0].status.isFinished == false)
  #expect(commands[1].status.isFinished)
}

@Test func runningACommandPostsItsNameAndParameters() async throws {
  let host = "arr-command-post.test"
  ServiceStubURLProtocol.stub(
    host: host,
    reply: .json(#"{"id":5502,"name":"RefreshMovie","commandName":"Refresh Movie","status":"queued"}"#))
  let core = makeCore(host: host)

  let command = try await core.runCommand("RefreshMovie", parameters: ["movieId": .int(812)])

  let request = try lastRequest(host)
  #expect(request.httpMethod == "POST")
  #expect(request.url?.path() == "/api/v3/command")
  let body = try #require(request.recordedBody)
  let parsed = try JSONSerialization.jsonObject(with: body) as? [String: Any]
  let json = try #require(parsed)
  #expect(json["name"] as? String == "RefreshMovie")
  #expect(json["movieId"] as? Int == 812)
  #expect(command.status == .queued)
}

// MARK: - Pickers

@Test func qualityProfilesRootFoldersAndTagsAllTolerateAMissingLabel() async throws {
  // Every one of these is a picker row, and a picker with a blank row is a
  // picker a user can't use.
  let profilesHost = "arr-profiles.test"
  let foldersHost = "arr-folders.test"
  let tagsHost = "arr-tags.test"

  let profiles = try await makeCore(host: profilesHost, fixture: "qualityprofiles.json")
    .qualityProfiles()
  let folders = try await makeCore(host: foldersHost, fixture: "rootfolders.json").rootFolders()
  let tags = try await makeCore(host: tagsHost, fixture: "tags.json").tags()

  #expect(profiles.map(\.name) == ["Any", "HD-1080p", "Profile 6"])
  #expect(folders.map(\.path) == ["/data/media/movies", "/data/media/movies-4k"])
  #expect(folders[0].freeBytes == 3_221_225_472_000)
  #expect(folders[1].isAccessible == false)
  #expect(folders[1].freeBytes == nil)
  #expect(tags.map(\.label) == ["4k", "kids", "Tag 3"])
}

// MARK: - API version

@Test func theApiVersionIsWhateverTheServiceWasBuiltWith() async throws {
  // Prowlarr and Lidarr are v1. A hard-coded v3 here would 404 with a message
  // that reads like a wrong address.
  let host = "arr-v1.test"
  let core = try makeCore(host: host, fixture: "health.json", apiPath: "api/v1")

  _ = try await core.health()

  let request = try lastRequest(host)
  #expect(request.url?.path() == "/api/v1/health")
}

// MARK: - Health wiki links

@Suite struct HealthWikiLinkTests {
  private func check(wikiUrl: String?) throws -> ArrHealthCheck {
    let json = wikiUrl.map { #"{"id":1,"source":"S","type":"warning","message":"m","wikiUrl":"\#($0)"}"# }
      ?? #"{"id":1,"source":"S","type":"warning","message":"m"}"#
    return try JSONDecoder().decode(HealthDTO.self, from: Data(json.utf8)).domain
  }

  @Test func aSchemelessAddressBecomesNoLinkRatherThanADeadOne() throws {
    // The bug: `URL(string:)` accepts this and returns a relative URL with no
    // scheme. `Link` renders it, the tap does nothing, and nothing says why.
    #expect(URL(string: "wiki.servarr.com/radarr/system") != nil, "precondition: URL accepts it")
    #expect(try check(wikiUrl: "wiki.servarr.com/radarr/system").wikiURL == nil)
  }

  @Test func arealWikiURLSurvives() throws {
    let url = try #require(
      try check(wikiUrl: "https://wiki.servarr.com/radarr/system#indexers-are-unavailable").wikiURL)
    #expect(url.scheme == "https")
    #expect(url.fragment() == "indexers-are-unavailable")
  }

  @Test func anAbsentOrEmptyWikiURLIsStillNil() throws {
    #expect(try check(wikiUrl: nil).wikiURL == nil)
    #expect(try check(wikiUrl: "").wikiURL == nil)
  }

  @Test func aNonWebSchemeIsRefused() throws {
    // A remote service must not be able to put a `tel:` behind "Read more".
    #expect(try check(wikiUrl: "tel:+15551234567").wikiURL == nil)
    #expect(try check(wikiUrl: "file:///etc/passwd").wikiURL == nil)
  }
}

// MARK: - Unopenable URLs are dropped at every boundary

@Suite struct OpenableURLBoundaryTests {
  /// The canonical bad value: `URL(string:)` accepts it and returns a
  /// scheme-less relative URL that `Link` and `AsyncImage` both ignore in
  /// silence.
  private let schemeless = "images.example.invalid/poster.jpg"

  @Test func theHelperItselfRefusesWhatCannotBeOpened() {
    #expect(URL(string: schemeless) != nil, "precondition: URL accepts it")
    #expect(OpenableURL.from(schemeless) == nil)
    #expect(OpenableURL.from("//images.example.invalid/p.jpg") == nil, "protocol-relative")
    #expect(OpenableURL.from("https:") == nil, "scheme with no host")
    #expect(OpenableURL.from("  ") == nil)
    #expect(OpenableURL.from(nil) == nil)
    #expect(OpenableURL.from("HTTPS://Example.invalid/x") != nil, "scheme match is case-insensitive")
    #expect(OpenableURL.from(" https://example.invalid/x ") != nil, "surrounding whitespace")
  }

  @Test func radarrCoversDropASchemelessRemoteURL() throws {
    let json = #"{"id":1,"images":[{"coverType":"poster","remoteUrl":"\#(schemeless)"}]}"#
    let dto = try JSONDecoder().decode(MovieDTO.self, from: Data(json.utf8))
    #expect(dto.domain.posterURL == nil)
  }

  @Test func radarrCoversKeepAnAbsoluteRemoteURL() throws {
    let json = #"{"id":1,"images":[{"coverType":"poster","remoteUrl":"https://img.invalid/p.jpg"}]}"#
    let dto = try JSONDecoder().decode(MovieDTO.self, from: Data(json.utf8))
    #expect(dto.domain.posterURL?.absoluteString == "https://img.invalid/p.jpg")
  }

  @Test func sonarrCoversFollowTheSameRule() throws {
    let bad = #"{"id":1,"images":[{"coverType":"poster","remoteUrl":"\#(schemeless)"}]}"#
    let good = #"{"id":1,"images":[{"coverType":"poster","remoteUrl":"https://img.invalid/p.jpg"}]}"#
    #expect(try JSONDecoder().decode(SeriesDTO.self, from: Data(bad.utf8)).domain.posterURL == nil)
    #expect(
      try JSONDecoder().decode(SeriesDTO.self, from: Data(good.utf8)).domain.posterURL != nil)
  }

  @Test func lidarrCoversFollowTheSameRule() throws {
    let bad = #"{"id":1,"images":[{"coverType":"poster","remoteUrl":"\#(schemeless)"}]}"#
    let good = #"{"id":1,"images":[{"coverType":"poster","remoteUrl":"https://img.invalid/p.jpg"}]}"#
    #expect(
      try JSONDecoder().decode(LidarrArtistDTO.self, from: Data(bad.utf8)).domain.posterURL == nil)
    #expect(
      try JSONDecoder().decode(LidarrArtistDTO.self, from: Data(good.utf8)).domain.posterURL != nil)
  }
}
