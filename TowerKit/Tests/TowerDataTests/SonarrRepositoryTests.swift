import Foundation
import Testing
import TowerCore
@testable import TowerData

/// `LiveSonarrRepository` against committed fixtures and a stubbed transport.
/// Mutations assert the request that would go out; nothing here touches a real
/// Sonarr.
private func sonarrFixture(_ name: String) throws -> Data {
  let url = try #require(
    Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures/Arr"),
    "missing fixture \(name)")
  return try Data(contentsOf: url)
}

private func makeSonarr(host: String) -> LiveSonarrRepository {
  let instance = ServiceInstance(
    kind: .sonarr, name: "Sonarr", baseURL: URL(string: "http://\(host)")!,
    credentials: .apiKey("k"))
  return LiveSonarrRepository(
    instance: instance, sessionConfiguration: ServiceStubURLProtocol.configuration())
}

private func makeSonarr(host: String, fixture name: String) throws -> LiveSonarrRepository {
  let body = try sonarrFixture(name)
  ServiceStubURLProtocol.stub(
    host: host, reply: ServiceStubURLProtocol.Reply(status: 200, body: body))
  return makeSonarr(host: host)
}

private func makeSonarr(host: String, routes: [String: Data]) -> LiveSonarrRepository {
  ServiceStubURLProtocol.stub(host: host) { request in
    let path = request.url?.path() ?? ""
    let body = routes.first { path.hasSuffix($0.key) }?.value ?? Data("{}".utf8)
    return .reply(ServiceStubURLProtocol.Reply(status: 200, body: body))
  }
  return makeSonarr(host: host)
}

private func sonarrRequests(_ host: String) -> [URLRequest] {
  ServiceStubURLProtocol.requests(host: host)
}

private func sonarrJSONBody(_ request: URLRequest) throws -> [String: Any] {
  let body = try #require(request.recordedBody)
  let parsed = try JSONSerialization.jsonObject(with: body) as? [String: Any]
  return try #require(parsed)
}

// MARK: - Library

@Test func seriesMapTheFieldsTheLibraryRowShows() async throws {
  let host = "sonarr-series.test"
  let repository = try makeSonarr(host: host, fixture: "sonarr-series.json")

  let series = try await repository.series()

  #expect(series.map(\.title) == ["Another Series", "Example Series"])
  let example = try #require(series.first { $0.id == 44 })
  #expect(example.displayTitle == "Example Series (2023)")
  #expect(example.network == "Example Network")
  #expect(example.status == .continuing)
  #expect(example.seriesType == .standard)
  #expect(example.usesSeasonFolders)
  #expect(example.sizeOnDiskBytes == 85_899_345_920)
  #expect(example.posterURL?.host() == "artworks.thetvdb.com")
  #expect(example.rootFolderPath == "/data/media/tv")
  #expect(series.first { $0.id == 45 }?.seriesType == .anime)
}

@Test func completionCountsAiredEpisodesNotTotalOnes() async throws {
  // 16 of 17 aired, but 23 including unaired. Measuring against 23 would show a
  // fully up-to-date continuing series as 70% complete forever.
  let host = "sonarr-completion.test"
  let repository = try makeSonarr(host: host, fixture: "sonarr-series.json")

  let example = try #require(try await repository.series().first { $0.id == 44 })

  #expect(example.statistics?.episodeCount == 17)
  #expect(example.statistics?.totalEpisodeCount == 23)
  #expect(example.completion.map { ($0 * 100).rounded() } == 94)
  #expect(!example.isComplete)
}

@Test func seasonsAreOrderedWithSpecialsFirstAndCarryTheirOwnCounts() async throws {
  // The fixture lists them 0, 2, 1 — the API makes no ordering promise, and a
  // season list that jumps around is a season list nobody trusts.
  let host = "sonarr-seasons.test"
  let repository = try makeSonarr(host: host, fixture: "sonarr-series-detail.json")

  let series = try await repository.series(id: 44)

  #expect(series.seasons.map(\.seasonNumber) == [0, 1, 2])
  let specials = try #require(series.seasons.first)
  #expect(specials.isSpecials)
  #expect(specials.displayName == "Specials")
  let seasonOne = try #require(series.seasons.first { $0.seasonNumber == 1 })
  #expect(seasonOne.isComplete)
  #expect(seasonOne.sizeOnDiskBytes == 53_687_091_200)
  let seasonTwo = try #require(series.seasons.first { $0.seasonNumber == 2 })
  #expect(!seasonTwo.isComplete)
  #expect(seasonTwo.nextAiring != nil)
}

// MARK: - Episodes

@Test func episodesAreOrderedAndCodedTheWayTheRestOfTheStackSpellsThem() async throws {
  let host = "sonarr-episodes.test"
  let repository = try makeSonarr(host: host, fixture: "sonarr-episodes.json")

  let episodes = try await repository.episodes(seriesID: 44)

  #expect(episodes.map(\.episodeCode) == ["S01E01", "S02E07", "S02E08"])
  let downloaded = try #require(episodes.first { $0.id == 55021 })
  #expect(downloaded.title == "The One With The Pilot")
  #expect(downloaded.hasFile)
  #expect(downloaded.file?.sizeBytes == 5_368_709_120)
  #expect(downloaded.file?.quality == "WEBDL-1080p")
  #expect(downloaded.file?.languages == ["eng"])
  let query = try #require(sonarrRequests(host).last?.url?.query())
  #expect(query.contains("seriesId=44"))
}

@Test func episodesAskSonarrToIncludeTheFileDetailsTheDetailScreenRenders() async throws {
  // `includeEpisodeFile` defaults to *false* on `api/v3/episode`, so without it
  // Sonarr sends `hasFile: true` and no `episodeFile` at all — and the detail
  // screen then says "No file on disk." beside "On disk: Yes". Sonarr 4 sends
  // every with-file episode with no file object unless asked. The mapping test
  // above cannot catch this, because the fixture is
  // served whatever the query says.
  let host = "sonarr-episode-file-query.test"
  let repository = try makeSonarr(host: host, fixture: "sonarr-episodes.json")

  _ = try await repository.episodes(seriesID: 44)

  let query = try #require(sonarrRequests(host).last?.url?.query())
  #expect(query.contains("includeEpisodeFile=true"))
}

@Test func anAbsentHasFileIsInferredFromTheFileRatherThanAssumedFalse() async throws {
  // "The service didn't say" is not "there is no file". `hasFile` is optional on
  // the wire, and defaulting a missing one to false would hide a file the
  // episode plainly has — the same reasoning `RootFolderDTO` records for
  // `accessible`. The request sends `includeEpisodeFile=true`, so the file
  // object is the evidence to infer from.
  let host = "sonarr-episode-no-hasfile.test"
  let repository = try makeSonarr(host: host, fixture: "sonarr-episodes-no-hasfile.json")

  let episodes = try await repository.episodes(seriesID: 44)

  let saidNothingSentFile = try #require(episodes.first { $0.id == 66001 })
  #expect(saidNothingSentFile.hasFile)
  #expect(saidNothingSentFile.file?.sizeBytes == 2_147_483_648)
  #expect(saidNothingSentFile.fileSection == .details)

  // Nothing said and nothing sent: there is no evidence of a file, and the
  // screen may not invent one.
  let saidNothingSentNothing = try #require(episodes.first { $0.id == 66002 })
  #expect(!saidNothingSentNothing.hasFile)
  #expect(saidNothingSentNothing.file == nil)
  #expect(saidNothingSentNothing.fileSection == .missing)
}

@Test func anUnairedEpisodeIsNotMissingAndStillHasATitle() async throws {
  // Sonarr sends no title for unaired episodes; a blank row reads as broken,
  // and calling one "missing" offers a search that can only fail.
  let host = "sonarr-unaired.test"
  let repository = try makeSonarr(host: host, fixture: "sonarr-episodes.json")

  let episodes = try await repository.episodes(seriesID: 44)

  let unaired = try #require(episodes.first { $0.id == 55022 })
  #expect(unaired.title == "TBA")
  #expect(!unaired.hasAired)
  #expect(!unaired.isMissing)

  // Aired, monitored, and no file — that one *is* missing.
  let missing = try #require(episodes.first { $0.id == 55000 })
  #expect(missing.hasAired)
  #expect(missing.isMissing)
}

// MARK: - Lookup and add

@Test func lookupMarksSeriesAlreadyInTheLibrary() async throws {
  let host = "sonarr-lookup.test"
  let repository = try makeSonarr(host: host, fixture: "sonarr-lookup.json")

  let results = try await repository.lookup(term: "example")

  #expect(results.count == 3)
  #expect(!results[0].isAlreadyAdded)
  #expect(results[0].tvdbID == 555100)
  #expect(results[1].existingSeriesID == 44)
}

@Test func lookupDecodesASeriesThatOmitsItsID() async throws {
  // Newer *arr builds, Sonarr's lookup among them, omit `id` rather than
  // sending 0 for a series that isn't in the library.
  let host = "sonarr-lookup-noid.test"
  let repository = try makeSonarr(host: host, fixture: "sonarr-lookup.json")

  let results = try await repository.lookup(term: "example")

  let fresh = try #require(results.first { $0.title == "Unindexed Series" })
  #expect(!fresh.isAlreadyAdded)
  #expect(fresh.existingSeriesID == nil)
  #expect(fresh.tvdbID == 555200)
}

@Test func aSeriesWithNoIDIsReEncodedWithoutOne() async throws {
  // As in `MovieDTO`: the 0 sentinel is not an id, and Sonarr's PUT
  // would read `"id": 0` as one.
  let dto = try JSONDecoder().decode(
    SeriesDTO.self, from: Data(#"{"title":"Unindexed Series","tvdbId":555200}"#.utf8))
  #expect(dto.id == 0)

  let json = try #require(
    try JSONSerialization.jsonObject(with: try JSONEncoder().encode(dto)) as? [String: Any])
  #expect(json["id"] == nil, "a synthesised 0 must not be sent back as an id")
  #expect(json["title"] as? String == "Unindexed Series")
}

@Test func addingASeriesSendsSonarrsOwnMonitorVocabulary() async throws {
  // `monitor: firstSeason` means something specific to Sonarr; paraphrasing it
  // would make the picker mean something slightly different from what it does.
  let host = "sonarr-add.test"
  let repository = makeSonarr(host: host)
  ServiceStubURLProtocol.stub(
    host: host,
    reply: ServiceStubURLProtocol.Reply(status: 201, body: try sonarrFixture("sonarr-series-detail.json")))
  let lookup = SonarrSeriesLookup(
    tvdbID: 555100, title: "Brand New Series", year: 2026, overview: nil, network: nil,
    status: .upcoming, posterURL: nil, existingSeriesID: nil)

  _ = try await repository.add(
    SonarrAddSeriesRequest(
      lookup: lookup, qualityProfileID: 4, rootFolderPath: "/data/media/tv",
      seriesType: .anime, monitorOption: .firstSeason, usesSeasonFolders: false,
      searchOnAdd: true, tagIDs: [2]))

  let request = try #require(sonarrRequests(host).last)
  #expect(request.httpMethod == "POST")
  #expect(request.url?.path() == "/api/v3/series")
  let json = try sonarrJSONBody(request)
  #expect(json["tvdbId"] as? Int == 555100)
  #expect(json["seriesType"] as? String == "anime")
  #expect(json["seasonFolder"] as? Bool == false)
  #expect(json["monitored"] as? Bool == true)
  let options = try #require(json["addOptions"] as? [String: Any])
  #expect(options["monitor"] as? String == "firstSeason")
  #expect(options["searchForMissingEpisodes"] as? Bool == true)
}

@Test func addingWithMonitorNoneStillAddsAMonitoredSeries() async throws {
  // "Monitor nothing" is about episodes. A series added with `.none` is still a
  // monitored series with no monitored episodes — sending `monitored: false`
  // would quietly opt the whole series out of future ones too.
  let host = "sonarr-add-none.test"
  let repository = makeSonarr(host: host)
  ServiceStubURLProtocol.stub(
    host: host,
    reply: ServiceStubURLProtocol.Reply(status: 201, body: try sonarrFixture("sonarr-series-detail.json")))
  let lookup = SonarrSeriesLookup(
    tvdbID: 555100, title: "Brand New Series", year: nil, overview: nil, network: nil,
    status: .upcoming, posterURL: nil, existingSeriesID: nil)

  _ = try await repository.add(
    SonarrAddSeriesRequest(
      lookup: lookup, qualityProfileID: 4, rootFolderPath: "/data/media/tv",
      monitorOption: .none, searchOnAdd: false))

  let json = try sonarrJSONBody(try #require(sonarrRequests(host).last))
  #expect(json["monitored"] as? Bool == false)
  let options = try #require(json["addOptions"] as? [String: Any])
  #expect(options["monitor"] as? String == "none")
  #expect(options["searchForMissingEpisodes"] as? Bool == false)
}

// MARK: - Edit and monitoring

@Test func editingPutsTheWholeSeriesAndKeepsUnmodelledFields() async throws {
  let host = "sonarr-edit.test"
  let repository = makeSonarr(
    host: host, routes: ["/api/v3/series/44": try sonarrFixture("sonarr-series-detail.json")])
  let series = try await repository.series(id: 44)
  var edit = SonarrSeriesEdit(series: series)
  edit.isMonitored = false
  edit.seriesType = .daily
  edit.usesSeasonFolders = false
  edit.tagIDs = [1, 2]

  _ = try await repository.update(series, with: edit)

  let put = try #require(sonarrRequests(host).last { $0.httpMethod == "PUT" })
  let json = try sonarrJSONBody(put)
  #expect(json["monitored"] as? Bool == false)
  #expect(json["seriesType"] as? String == "daily")
  #expect(json["seasonFolder"] as? Bool == false)
  #expect(json["tags"] as? [Int] == [1, 2])
  #expect(json["title"] as? String == "Example Series")
  let unknown = try #require(json["someFieldTowerDoesNotModel"] as? [String: Any])
  #expect(unknown["keep"] as? String == "me")
}

@Test func settingSeasonMonitoringFlipsOneSeasonAndLeavesTheRest() async throws {
  // There is no per-season endpoint: season monitoring lives inside the series
  // resource, so this is a whole-series PUT with exactly one flag changed.
  let host = "sonarr-season-monitor.test"
  let repository = makeSonarr(
    host: host, routes: ["/api/v3/series/44": try sonarrFixture("sonarr-series-detail.json")])

  try await repository.setSeasonMonitored(false, seriesID: 44, seasonNumber: 2)

  let put = try #require(sonarrRequests(host).last { $0.httpMethod == "PUT" })
  let json = try sonarrJSONBody(put)
  let seasons = try #require(json["seasons"] as? [[String: Any]])
  let byNumber = Dictionary(
    uniqueKeysWithValues: seasons.compactMap { season -> (Int, Bool)? in
      guard let number = season["seasonNumber"] as? Int,
            let monitored = season["monitored"] as? Bool
      else { return nil }
      return (number, monitored)
    })
  #expect(byNumber[2] == false, "the targeted season didn't change")
  #expect(byNumber[1] == true, "another season's monitoring was disturbed")
  #expect(byNumber[0] == false)
}

@Test func settingEpisodeMonitoringUsesTheBulkEndpoint() async throws {
  let host = "sonarr-episode-monitor.test"
  ServiceStubURLProtocol.stub(host: host, reply: .json("{}"))
  let repository = makeSonarr(host: host)

  try await repository.setEpisodesMonitored(true, episodeIDs: [55021, 55022])

  let request = try #require(sonarrRequests(host).last)
  #expect(request.httpMethod == "PUT")
  #expect(request.url?.path() == "/api/v3/episode/monitor")
  let json = try sonarrJSONBody(request)
  #expect(json["episodeIds"] as? [Int] == [55021, 55022])
  #expect(json["monitored"] as? Bool == true)
}

@Test func monitoringNoEpisodesAsksTheServerNothing() async throws {
  let host = "sonarr-episode-monitor-empty.test"
  ServiceStubURLProtocol.stub(host: host, reply: .json("{}"))
  let repository = makeSonarr(host: host)

  try await repository.setEpisodesMonitored(true, episodeIDs: [])

  #expect(sonarrRequests(host).isEmpty)
}

// MARK: - Search

@Test func searchRunsTheRightCommandAtEachLevel() async throws {
  // Series, season, and episode are three different commands with three
  // different parameter shapes — the episode one takes an array.
  let host = "sonarr-search.test"
  ServiceStubURLProtocol.stub(
    host: host, reply: .json(#"{"id":1,"name":"SeriesSearch","status":"queued"}"#))
  let repository = makeSonarr(host: host)

  try await repository.searchSeries(id: 44)
  let seriesBody = try sonarrJSONBody(try #require(sonarrRequests(host).last))
  #expect(seriesBody["name"] as? String == "SeriesSearch")
  #expect(seriesBody["seriesId"] as? Int == 44)

  try await repository.searchSeason(seriesID: 44, seasonNumber: 2)
  let seasonBody = try sonarrJSONBody(try #require(sonarrRequests(host).last))
  #expect(seasonBody["name"] as? String == "SeasonSearch")
  #expect(seasonBody["seasonNumber"] as? Int == 2)

  try await repository.searchEpisodes(ids: [55021])
  let episodeBody = try sonarrJSONBody(try #require(sonarrRequests(host).last))
  #expect(episodeBody["name"] as? String == "EpisodeSearch")
  #expect(episodeBody["episodeIds"] as? [Int] == [55021])
}

@Test func releasesAreFetchedPerEpisode() async throws {
  let host = "sonarr-releases.test"
  let repository = try makeSonarr(host: host, fixture: "radarr-releases.json")

  let releases = try await repository.releases(episodeID: 55021)

  // Same shared `ArrRelease` as Radarr — the release list is one screen.
  #expect(releases.count == 2)
  #expect(releases.first?.quality == "Bluray-2160p")
  let query = try #require(sonarrRequests(host).last?.url?.query())
  #expect(query.contains("episodeId=55021"))
}

@Test func theSharedArrEndpointsAreReachableFromSonarrToo() async throws {
  let host = "sonarr-shared.test"
  let repository = try makeSonarr(host: host, fixture: "queue.json")

  let page = try await repository.arr.queue()

  #expect(page.items.count == 3)
  #expect(sonarrRequests(host).last?.url?.path() == "/api/v3/queue")
}
