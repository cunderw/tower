import Foundation
import Testing
import TowerCore

@testable import TowerData

/// `LiveBazarrRepository` end to end.
///
/// Bazarr gets more tolerance testing than the other services because it is
/// the only one with **no response contract at all** — its served Swagger
/// declares requests precisely and responses not at all. So the decoding tests
/// here deliberately feed it the shapes it is known to vary between: a
/// language as an object *and* as a bare string, booleans as `true` *and* as
/// `"True"`, a score as a number *and* as `"88%"`.
private func fixture(_ name: String) throws -> Data {
  let url = try #require(
    Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures/Bazarr"),
    "missing fixture \(name)")
  return try Data(contentsOf: url)
}

private func makeRepository(host: String) -> LiveBazarrRepository {
  let instance = ServiceInstance(
    kind: .bazarr, name: "Bazarr", baseURL: URL(string: "http://\(host)")!,
    credentials: .apiKey("k"))
  return LiveBazarrRepository(
    instance: instance,
    client: ServiceHTTPClient(
      instance: instance, sessionConfiguration: ServiceStubURLProtocol.configuration()))
}

private func stub(host: String, _ answer: @escaping @Sendable (String) -> Data) {
  ServiceStubURLProtocol.stub(host: host) { request in
    .reply(.init(status: 200, body: answer(request.url?.path() ?? "")))
  }
}

private func requests(_ host: String) -> [URLRequest] {
  ServiceStubURLProtocol.requests(host: host)
}

// MARK: - Wanted

@Suite struct BazarrWantedTests {
  private func stubWanted(host: String) throws {
    let episodes = try fixture("episodes-wanted.json")
    let movies = try fixture("movies-wanted.json")
    stub(host: host) { path in path.contains("movies") ? movies : episodes }
  }

  @Test func theWantedListMergesEpisodesAndFilms() async throws {
    let host = "bz-wanted.invalid"
    try stubWanted(host: host)

    let wanted = try await makeRepository(host: host).wanted()

    #expect(wanted.count == 3)
    #expect(wanted.filter({ $0.isEpisode }).count == 2)
    #expect(wanted.filter({ !$0.isEpisode }).count == 1)
  }

  @Test func anEpisodeRowCarriesBothIDsBecauseTheDownloadNeedsThem() async throws {
    // Bazarr's episode download requires `seriesid` *and* `episodeid`; a row
    // carrying only one can't be actioned.
    let host = "bz-ids.invalid"
    try stubWanted(host: host)

    let wanted = try await makeRepository(host: host).wanted()
    let episode = try #require(wanted.first { $0.episodeID == 2011 })

    #expect(episode.seriesID == 14)
    #expect(episode.title == "Northern Lights")
    #expect(episode.subtitle == "2x11 · The Missing Signal")
    #expect(episode.radarrID == nil)
  }

  @Test func theThreeLanguageFlagsTravelTogether() async throws {
    // A subtitle matching the language but not the HI/forced flags is the
    // wrong subtitle, so they are one value rather than three fields.
    let host = "bz-flags.invalid"
    try stubWanted(host: host)

    let wanted = try await makeRepository(host: host).wanted()
    let episode = try #require(wanted.first { $0.episodeID == 2011 })

    #expect(episode.missing.count == 2)
    #expect(episode.missing[0].displayName == "English")
    #expect(episode.missing[1].displayName == "English (HI)")
    // Distinct identities, so a list of both doesn't collapse to one row.
    #expect(episode.missing[0].id != episode.missing[1].id)
  }

  @Test func aLanguageSentAsABareStringStillDecodes() async throws {
    // Bazarr is inconsistent here, and a strict decode of the object form
    // would fail the whole row.
    let host = "bz-strlang.invalid"
    try stubWanted(host: host)

    let wanted = try await makeRepository(host: host).wanted()
    let episode = try #require(wanted.first { $0.episodeID == 2012 })

    #expect(episode.missing.count == 1)
    #expect(episode.missing[0].code == "es")
    #expect(episode.missing[0].name == "ES")
  }

  @Test func booleansSentAsStringsAreStillBooleans() async throws {
    // Older builds send `"True"`/`"False"` rather than `true`/`false`.
    let host = "bz-strbool.invalid"
    try stubWanted(host: host)

    let wanted = try await makeRepository(host: host).wanted()
    let film = try #require(wanted.first { $0.radarrID == 3 })

    #expect(film.missing[0].isForced)
    #expect(!film.missing[0].isHearingImpaired)
    #expect(film.missing[0].displayName == "French (forced)")
  }

  @Test func aBazarrWithOnlyOneLibraryStillShowsThatLibrary() async throws {
    // A Bazarr with no Radarr connected errors on `/movies/wanted`; losing the
    // whole screen for that would be wrong.
    let host = "bz-onelib.invalid"
    let episodes = try fixture("episodes-wanted.json")
    ServiceStubURLProtocol.stub(host: host) { request in
      if request.url?.path().contains("movies") == true {
        return .reply(.init(status: 500, body: Data()))
      }
      return .reply(.init(status: 200, body: episodes))
    }

    let wanted = try await makeRepository(host: host).wanted()

    #expect(wanted.count == 2)
    #expect(wanted.allSatisfy({ $0.isEpisode }))
  }

  @Test func listsAskForEverythingRatherThanTheDefaultPage() async throws {
    // Bazarr paginates by start/length and defaults to a page, which would
    // silently truncate the wanted list.
    let host = "bz-nolimit.invalid"
    try stubWanted(host: host)

    _ = try await makeRepository(host: host).wanted()

    let queries = requests(host).compactMap { $0.url?.query() }
    #expect(queries.count == 2)
    #expect(queries.allSatisfy({ $0.contains("length=-1") }), "got \(queries)")
  }
}

// MARK: - Manual search and download

@Suite struct BazarrSearchTests {
  @Test func candidatesMapAndLeadWithTheBestScore() async throws {
    let host = "bz-candidates.invalid"
    let body = try fixture("candidates.json")
    stub(host: host) { _ in body }
    let item = WantedSubtitle(
      title: "Northern Lights", subtitle: nil, seriesID: 14, episodeID: 2011, radarrID: nil,
      missing: [])

    let candidates = try await makeRepository(host: host).candidates(for: item)

    // The row with no downloadable handle is dropped, so two remain.
    #expect(candidates.count == 2)
    #expect(candidates[0].score == 96)
    #expect(candidates[0].provider == "opensubtitles.com")
    #expect(candidates[0].confidence == .high)
    #expect(candidates[0].matchedBy.contains("release_group"))
    #expect(candidates[1].score == 62)
    #expect(candidates[1].confidence == .low)
  }

  @Test func aCandidateWithNoHandleIsDroppedRatherThanOfferedAsABrokenGrab() async throws {
    // Without a provider and a subtitle handle there is nothing to send back,
    // so offering it would produce a download that silently fails.
    let host = "bz-nohandle.invalid"
    let body = try fixture("candidates.json")
    stub(host: host) { _ in body }
    let item = WantedSubtitle(
      title: "x", subtitle: nil, seriesID: 14, episodeID: 2011, radarrID: nil, missing: [])

    let candidates = try await makeRepository(host: host).candidates(for: item)

    #expect(!candidates.contains(where: { $0.provider == "brokenprovider" }))
  }

  @Test func flagsBesideTheLanguageAreFoldedIntoIt() async throws {
    // Some builds put `hearing_impaired` next to the language rather than
    // inside it; a candidate whose flags don't match what gets downloaded is
    // the wrong variant of the right subtitle.
    let host = "bz-outerflags.invalid"
    let body = try fixture("candidates.json")
    stub(host: host) { _ in body }
    let item = WantedSubtitle(
      title: "x", subtitle: nil, seriesID: 14, episodeID: 2011, radarrID: nil, missing: [])

    let candidates = try await makeRepository(host: host).candidates(for: item)
    let addic7ed = try #require(candidates.first { $0.provider == "addic7ed" })

    #expect(addic7ed.language.isHearingImpaired)
    #expect(!addic7ed.language.isForced)
  }

  @Test func anEpisodeSearchAsksTheEpisodeEndpointAndAFilmTheMovieOne() async throws {
    let host = "bz-route.invalid"
    let body = try fixture("candidates.json")
    stub(host: host) { _ in body }
    let repository = makeRepository(host: host)

    _ = try await repository.candidates(
      for: WantedSubtitle(
        title: "x", subtitle: nil, seriesID: 14, episodeID: 2011, radarrID: nil, missing: []))
    #expect(requests(host).last?.url?.path().hasSuffix("/providers/episodes") == true)
    #expect(requests(host).last?.url?.query()?.contains("episodeid=2011") == true)

    _ = try await repository.candidates(
      for: WantedSubtitle(
        title: "x", subtitle: nil, seriesID: nil, episodeID: nil, radarrID: 3, missing: []))
    #expect(requests(host).last?.url?.path().hasSuffix("/providers/movies") == true)
    #expect(requests(host).last?.url?.query()?.contains("radarrid=3") == true)
  }

  // MARK: - Manual pick carries everything through

  @Test func aManualDownloadCarriesProviderLanguageAndTheHandleAsQueryParameters() async throws {
    // **Query parameters, not a body** — verified against the served Swagger,
    // where all seven are required. A body-shaped POST is accepted and does
    // nothing.
    let host = "bz-download.invalid"
    let body = try fixture("candidates.json")
    stub(host: host) { _ in body }
    let repository = makeRepository(host: host)
    let item = WantedSubtitle(
      title: "Northern Lights", subtitle: nil, seriesID: 14, episodeID: 2011, radarrID: nil,
      missing: [])
    let candidate = try #require(try await repository.candidates(for: item).first)

    try await repository.download(candidate, for: item)

    let post = try #require(requests(host).last)
    #expect(post.httpMethod == "POST")
    #expect(post.url?.path().hasSuffix("/providers/episodes") == true)
    let query = try #require(post.url?.query()?.removingPercentEncoding)
    // The provider and the opaque handle together identify the exact file.
    #expect(query.contains("provider=opensubtitles.com"), "got \(query)")
    #expect(query.contains("subtitle=b64-handle-aaa"))
    // The language flags have to match the candidate's, or Bazarr fetches the
    // wrong variant of the right subtitle.
    #expect(query.contains("hi=False"))
    #expect(query.contains("forced=False"))
    #expect(query.contains("original_format=False"))
    #expect(query.contains("seriesid=14"))
    #expect(query.contains("episodeid=2011"))
    // And no JSON body, which is the mistake this shape prevents.
    #expect((post.recordedBody ?? Data()).isEmpty)
  }

  @Test func aManualDownloadForAFilmSendsRadarrIDInstead() async throws {
    let host = "bz-download-movie.invalid"
    let body = try fixture("candidates.json")
    stub(host: host) { _ in body }
    let repository = makeRepository(host: host)
    let item = WantedSubtitle(
      title: "Winter Ledger", subtitle: nil, seriesID: nil, episodeID: nil, radarrID: 3,
      missing: [])
    let candidate = try #require(try await repository.candidates(for: item).first)

    try await repository.download(candidate, for: item)

    let post = try #require(requests(host).last)
    #expect(post.url?.path().hasSuffix("/providers/movies") == true)
    let query = try #require(post.url?.query())
    #expect(query.contains("radarrid=3"))
    #expect(!query.contains("episodeid"))
  }

  @Test func theAutomaticDownloadIsADifferentVerbOnADifferentEndpoint() async throws {
    // Bazarr's "find one yourself" is a PATCH on the media's own subtitles
    // resource, not a POST to the providers one.
    let host = "bz-auto.invalid"
    stub(host: host) { _ in Data() }
    let repository = makeRepository(host: host)
    let language = SubtitleLanguage(
      code: "en", name: "English", isHearingImpaired: true, isForced: false)

    try await repository.downloadBest(
      language,
      for: WantedSubtitle(
        title: "x", subtitle: nil, seriesID: 14, episodeID: 2011, radarrID: nil, missing: []))

    let patch = try #require(requests(host).last)
    #expect(patch.httpMethod == "PATCH")
    #expect(patch.url?.path().hasSuffix("/episodes/subtitles") == true)
    let query = try #require(patch.url?.query())
    #expect(query.contains("language=en"))
    #expect(query.contains("hi=True"))
    #expect(query.contains("forced=False"))
  }

  @Test func anItemWithNoUsableIDIsNotARequest() async throws {
    let host = "bz-noid.invalid"
    stub(host: host) { _ in Data("[]".utf8) }
    let item = WantedSubtitle(
      title: "x", subtitle: nil, seriesID: nil, episodeID: nil, radarrID: nil, missing: [])

    let candidates = try await makeRepository(host: host).candidates(for: item)

    #expect(candidates.isEmpty)
    #expect(requests(host).isEmpty)
  }
}

// MARK: - Providers and history

@Suite struct BazarrProviderTests {
  /// Provider health maps to the standard states.
  @Test func providerHealthMapsOntoTheStandardStatuses() async throws {
    let host = "bz-providers.invalid"
    let body = try fixture("providers.json")
    stub(host: host) { _ in body }

    let providers = try await makeRepository(host: host).providers()

    #expect(providers.count == 3)
    // Bazarr says "Good" for a working provider rather than sending nothing,
    // so a naive "has a message means broken" reading marks it failing.
    let good = try #require(providers.first { $0.name == "opensubtitles.com" })
    #expect(good.status == .healthy)
    #expect(good.status.displayName == "Working")

    let throttled = try #require(providers.first { $0.name == "addic7ed" })
    #expect(throttled.status == .failing)
    #expect(throttled.message?.contains("Throttled") == true)
    #expect(throttled.retryAt == "in 2 hours")

    // A null status is healthy too.
    let quiet = try #require(providers.first { $0.name == "gestdown" })
    #expect(quiet.status == .healthy)
  }

  @Test func historyMergesBothLibrariesAndMapsItsActionCodes() async throws {
    let host = "bz-history.invalid"
    let body = try fixture("history.json")
    stub(host: host) { _ in body }

    let history = try await makeRepository(host: host).history()

    // Both endpoints answer with the same fixture here, so four rows.
    #expect(history.count == 4)
    let downloaded = try #require(history.first { $0.id == "900" })
    #expect(downloaded.action == .downloaded)
    #expect(downloaded.title == "Northern Lights")
    #expect(downloaded.subtitle == "2x11 · The Missing Signal")
    #expect(downloaded.provider == "opensubtitles.com")
    // A score sent as "96%" rather than a number.
    #expect(downloaded.score == 96)

    let manual = try #require(history.first { $0.id == "901" })
    #expect(manual.action == .manuallyDownloaded)
    // And one sent as a plain number.
    #expect(manual.score == 74)
    #expect(manual.language?.isForced == true)
  }

  @Test func anUnrecognisedActionCodeDegradesTheRow() async throws {
    let host = "bz-newaction.invalid"
    stub(host: host) { _ in Data(#"{"data":[{"id":1,"action":99,"title":"X"}]}"#.utf8) }

    let history = try await makeRepository(host: host).history()

    #expect(history.first?.action == .unknown)
    #expect(history.first?.title == "X")
  }

  @Test func theLibraryListsMapMissingCounts() async throws {
    let host = "bz-series.invalid"
    let body = try fixture("series.json")
    stub(host: host) { _ in body }

    let series = try await makeRepository(host: host).series()

    #expect(series.map(\.title) == ["Anvil Road", "Northern Lights"])
    let northern = try #require(series.first { $0.serviceID == 14 })
    #expect(northern.isSeries)
    #expect(northern.missingCount == 3)
    #expect(northern.languageProfileName == "English + French")
    #expect(northern.monitored)
  }
}
