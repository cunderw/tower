import Foundation
import Testing
import TowerCore
@testable import TowerData

/// `LiveRadarrRepository` against committed fixtures and a stubbed transport.
///
/// Mutations are exercised here and **never against a real Radarr**. The rule
/// (CLAUDE.md, "A live Unraid server is someone's real machine") applies to a
/// live service too: it is someone's real library. What the tests assert is
/// the request that would go out: method, path, query, and body.
private func fixture(_ name: String) throws -> Data {
  let url = try #require(
    Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures/Arr"),
    "missing fixture \(name)")
  return try Data(contentsOf: url)
}

private func makeRepository(host: String) -> LiveRadarrRepository {
  let instance = ServiceInstance(
    kind: .radarr, name: "Radarr", baseURL: URL(string: "http://\(host)")!,
    credentials: .apiKey("k"))
  return LiveRadarrRepository(
    instance: instance, sessionConfiguration: ServiceStubURLProtocol.configuration())
}

/// Answers every request with one fixture — enough for the read paths.
private func makeRepository(host: String, fixture name: String) throws -> LiveRadarrRepository {
  let body = try fixture(name)
  ServiceStubURLProtocol.stub(
    host: host, reply: ServiceStubURLProtocol.Reply(status: 200, body: body))
  return makeRepository(host: host)
}

/// Routes by path, for the mutations that read before they write.
private func makeRepository(
  host: String, routes: [String: Data]
) -> LiveRadarrRepository {
  ServiceStubURLProtocol.stub(host: host) { request in
    let path = request.url?.path() ?? ""
    let body = routes.first { path.hasSuffix($0.key) }?.value ?? Data("{}".utf8)
    return .reply(ServiceStubURLProtocol.Reply(status: 200, body: body))
  }
  return makeRepository(host: host)
}

private func requests(_ host: String) -> [URLRequest] {
  ServiceStubURLProtocol.requests(host: host)
}

/// A request's JSON body. Extracted because `#require` cannot be nested inside
/// another `#require`, and both the body and the parse can fail.
private func jsonBody(_ request: URLRequest) throws -> [String: Any] {
  let body = try #require(request.recordedBody)
  let parsed = try JSONSerialization.jsonObject(with: body) as? [String: Any]
  return try #require(parsed)
}

// MARK: - Library

@Test func moviesMapTheFieldsTheLibraryRowShows() async throws {
  let host = "radarr-movies.test"
  let repository = try makeRepository(host: host, fixture: "radarr-movies.json")

  let movies = try await repository.movies()

  #expect(movies.count == 3)
  // Sorted by Radarr's own sort title, so Tower's order matches the service's.
  #expect(movies.map(\.title) == ["Another Movie", "Example Movie", "Missing Movie"])
  let example = try #require(movies.first { $0.id == 812 })
  #expect(example.displayTitle == "Example Movie (2024)")
  #expect(example.studio == "Example Pictures")
  #expect(example.runtimeMinutes == 128)
  #expect(example.certification == "PG-13")
  #expect(example.genres == ["Drama", "Science Fiction"])
  #expect(example.status == .released)
  #expect(example.minimumAvailability == .released)
  #expect(example.isMonitored)
  #expect(example.hasFile)
  #expect(example.qualityProfileID == 4)
  #expect(example.tagIDs == [1])
  #expect(example.posterURL?.host() == "image.tmdb.org")
  #expect(example.fanartURL != nil)
}

@Test func aMultiTerabyteSizeSurvivesAsInt64() async throws {
  // A single 4K remux is already past Int32; a library total is far past it.
  // Decoding this as Int32 would trap or wrap, and either way the size shown on
  // the row would be fiction.
  let host = "radarr-size.test"
  let repository = try makeRepository(host: host, fixture: "radarr-movies.json")

  let movies = try await repository.movies()
  let total = movies.reduce(Int64(0)) { $0 + $1.sizeOnDiskBytes }

  #expect(movies.first { $0.id == 812 }?.sizeOnDiskBytes == 87_241_068_544)
  #expect(total == 87_241_068_544)
  #expect(total > Int64(Int32.max))
}

@Test func theLibraryStateDistinguishesMissingFromUnreleased() async throws {
  // Three states the user acts on differently: downloaded, missing something
  // that exists, and waiting for something that doesn't exist yet. Collapsing
  // the last two puts a "search" button in front of a film nobody can find.
  let host = "radarr-state.test"
  let repository = try makeRepository(host: host, fixture: "radarr-movies.json")

  let movies = try await repository.movies()

  #expect(movies.first { $0.id == 812 }?.libraryState == .downloaded)
  #expect(movies.first { $0.id == 913 }?.libraryState == .unreleased)
  #expect(movies.first { $0.id == 914 }?.libraryState == .missing)
}

@Test func theRootFolderIsDerivedWhenTheListEndpointOmitsIt() async throws {
  // `rootFolderPath` is absent from `/movie`. Without deriving it, the edit
  // sheet opens with no root folder selected for every film in the library.
  let host = "radarr-root.test"
  let repository = try makeRepository(host: host, fixture: "radarr-movies.json")

  let movies = try await repository.movies()

  #expect(movies.first { $0.id == 812 }?.rootFolderPath == "/data/media/movies")
  // Nothing to derive from, and nothing invented.
  #expect(movies.first { $0.id == 914 }?.rootFolderPath == nil)
}

@Test func movieDetailCarriesTheFileInfo() async throws {
  let host = "radarr-detail.test"
  let repository = try makeRepository(host: host, fixture: "radarr-movie.json")

  let movie = try await repository.movie(id: 812)

  let file = try #require(movie.file)
  #expect(file.sizeBytes == 87_241_068_544)
  #expect(file.quality == "Bluray-2160p")
  #expect(file.videoCodec == "HEVC")
  #expect(file.audioCodec == "TrueHD Atmos")
  #expect(file.audioChannels == 7.1)
  #expect(file.resolution == "3840x2160")
  // "eng / fra" is one string on the wire and two languages to a reader.
  #expect(file.languages == ["eng", "fra"])
  #expect(requests(host).last?.url?.path() == "/api/v3/movie/812")
}

// MARK: - Lookup

@Test func lookupMarksFilmsAlreadyInTheLibrary() async throws {
  // A lookup result's `id` is 0 until the film is added — which is exactly how
  // the add screen knows to say "Already added" instead of offering it again.
  let host = "radarr-lookup.test"
  let repository = try makeRepository(host: host, fixture: "radarr-lookup.json")

  let results = try await repository.lookup(term: "example")

  #expect(results.count == 3)
  #expect(results[0].isAlreadyAdded == false)
  #expect(results[0].tmdbID == 999100)
  #expect(results[1].isAlreadyAdded)
  #expect(results[1].existingMovieID == 812)
  let query = try #require(requests(host).last?.url?.query())
  #expect(query.contains("term=example"))
}

@Test func lookupDecodesAResultThatOmitsItsID() async throws {
  // Radarr 6 leaves `id` **out** of a lookup result that isn't in the library,
  // where earlier versions sent 0. Decoding it as required fails the
  // whole array, so one such result breaks every search.
  let host = "radarr-lookup-noid.test"
  let repository = try makeRepository(host: host, fixture: "radarr-lookup.json")

  let results = try await repository.lookup(term: "example")

  let fresh = try #require(results.first { $0.title == "Unindexed Film" })
  #expect(fresh.isAlreadyAdded == false)
  #expect(fresh.existingMovieID == nil)
  #expect(fresh.tmdbID == 999200)
}

@Test func anEmptyLookupTermAsksTheServerNothing() async throws {
  let host = "radarr-lookup-empty.test"
  let repository = try makeRepository(host: host, fixture: "radarr-lookup.json")

  let results = try await repository.lookup(term: "   ")

  #expect(results.isEmpty)
  #expect(requests(host).isEmpty, "an empty search must not hit the indexers")
}

// MARK: - Add

@Test func addingAMoviePostsWhatRadarrNeedsAndNothingElse() async throws {
  let host = "radarr-add.test"
  let repository = makeRepository(host: host)
  ServiceStubURLProtocol.stub(
    host: host, reply: ServiceStubURLProtocol.Reply(status: 201, body: try fixture("radarr-movie.json")))
  let lookup = RadarrMovieLookup(
    tmdbID: 999100, title: "Brand New Film", year: 2026, overview: nil, posterURL: nil,
    studio: nil, runtimeMinutes: 105, existingMovieID: nil)

  _ = try await repository.add(
    RadarrAddMovieRequest(
      lookup: lookup, qualityProfileID: 4, rootFolderPath: "/data/media/movies",
      minimumAvailability: .announced, isMonitored: true, searchOnAdd: true, tagIDs: [2]))

  let request = try #require(requests(host).last)
  #expect(request.httpMethod == "POST")
  #expect(request.url?.path() == "/api/v3/movie")
  let json = try jsonBody(request)
  #expect(json["tmdbId"] as? Int == 999100)
  #expect(json["qualityProfileId"] as? Int == 4)
  #expect(json["rootFolderPath"] as? String == "/data/media/movies")
  #expect(json["minimumAvailability"] as? String == "announced")
  #expect(json["monitored"] as? Bool == true)
  #expect(json["tags"] as? [Int] == [2])
  let options = try #require(json["addOptions"] as? [String: Any])
  #expect(options["searchForMovie"] as? Bool == true)
}

@Test func addingUnmonitoredDoesNotAskRadarrToMonitor() async throws {
  let host = "radarr-add-unmonitored.test"
  let repository = makeRepository(host: host)
  ServiceStubURLProtocol.stub(
    host: host, reply: ServiceStubURLProtocol.Reply(status: 201, body: try fixture("radarr-movie.json")))
  let lookup = RadarrMovieLookup(
    tmdbID: 999100, title: "Brand New Film", year: 2026, overview: nil, posterURL: nil,
    studio: nil, runtimeMinutes: nil, existingMovieID: nil)

  _ = try await repository.add(
    RadarrAddMovieRequest(
      lookup: lookup, qualityProfileID: 4, rootFolderPath: "/data/media/movies",
      isMonitored: false, searchOnAdd: false))

  let request = try #require(requests(host).last)
  let json = try jsonBody(request)
  #expect(json["monitored"] as? Bool == false)
  let options = try #require(json["addOptions"] as? [String: Any])
  #expect(options["searchForMovie"] as? Bool == false)
  #expect(options["monitor"] as? String == "none")
}

// MARK: - Edit

@Test func editingReadsTheResourceBackAndPutsTheWholeThing() async throws {
  // Radarr's PUT merges a fixed set of fields onto the stored record, so the
  // edit is applied to the movie as fetched and sent back whole rather than as
  // a patch of the changed fields.
  let host = "radarr-edit.test"
  let repository = makeRepository(
    host: host, routes: ["/api/v3/movie/812": try fixture("radarr-movie.json")])
  let movie = try await repository.movie(id: 812)
  var edit = RadarrMovieEdit(movie: movie)
  edit.isMonitored = false
  edit.qualityProfileID = 6
  edit.minimumAvailability = .inCinemas
  edit.tagIDs = [1, 2]

  _ = try await repository.update(movie, with: edit)

  let put = try #require(requests(host).last { $0.httpMethod == "PUT" })
  #expect(put.url?.path() == "/api/v3/movie/812")
  let json = try jsonBody(put)
  #expect(json["monitored"] as? Bool == false)
  #expect(json["qualityProfileId"] as? Int == 6)
  #expect(json["minimumAvailability"] as? String == "inCinemas")
  #expect(json["tags"] as? [Int] == [1, 2])
  // Untouched fields still there — this is the half that a patch would destroy.
  #expect(json["title"] as? String == "Example Movie")
  #expect(json["path"] as? String == "/data/media/movies/Example Movie (2024)")
  #expect(json["tmdbId"] as? Int == 999001)
  // The real id survives the round trip — the counterpart to omitting a
  // synthesised 0.
  #expect(json["id"] as? Int == 812)
}

@Test func aResourceWithNoIDIsReEncodedWithoutOne() async throws {
  // The encode side: an absent `id` decodes to the 0 sentinel, and 0 is
  // not an id Radarr should ever be handed back. Encoding it as `"id": 0`
  // would address record zero.
  let decoder = JSONDecoder()
  let encoder = JSONEncoder()
  let withoutID = Data(#"{"title":"Unindexed Film","tmdbId":999200}"#.utf8)

  let dto = try decoder.decode(MovieDTO.self, from: withoutID)
  #expect(dto.id == 0, "an absent id reads as the not-in-library sentinel")

  let reEncoded = try JSONSerialization.jsonObject(with: try encoder.encode(dto))
  let json = try #require(reEncoded as? [String: Any])
  #expect(json["id"] == nil, "a synthesised 0 must not be sent back as an id")
  #expect(json["title"] as? String == "Unindexed Film")
}

@Test func anEditPreservesFieldsTowerDoesNotModel() async throws {
  // Radarr adds fields between minor versions. A round trip that dropped them
  // would silently reset settings Tower has never heard of — the fixture
  // carries `someFieldTowerDoesNotModel` for exactly this assertion.
  let host = "radarr-edit-unknown.test"
  let repository = makeRepository(
    host: host, routes: ["/api/v3/movie/812": try fixture("radarr-movie.json")])
  let movie = try await repository.movie(id: 812)

  _ = try await repository.update(movie, with: RadarrMovieEdit(movie: movie))

  let put = try #require(requests(host).last { $0.httpMethod == "PUT" })
  let json = try jsonBody(put)
  let unknown = try #require(json["someFieldTowerDoesNotModel"] as? [String: Any])
  #expect(unknown["nested"] as? Bool == true)
  #expect(unknown["count"] as? Int == 3)
}

// MARK: - Delete

@Test func deleteSendsBothDecisionsExplicitly() async throws {
  let host = "radarr-delete.test"
  ServiceStubURLProtocol.stub(host: host, reply: .json("{}"))
  let repository = makeRepository(host: host)

  try await repository.delete(id: 812, deleteFiles: true, addImportExclusion: false)

  let request = try #require(requests(host).last)
  #expect(request.httpMethod == "DELETE")
  #expect(request.url?.path() == "/api/v3/movie/812")
  let query = try #require(request.url?.query())
  #expect(query.contains("deleteFiles=true"))
  #expect(query.contains("addImportExclusion=false"))
}

// MARK: - Interactive search

@Test func releasesMapQualitySizeAndWhyOneWasRejected() async throws {
  let host = "radarr-releases.test"
  let repository = try makeRepository(host: host, fixture: "radarr-releases.json")

  let releases = try await repository.releases(movieID: 812)

  #expect(releases.count == 2)
  let best = try #require(releases.first)
  #expect(best.quality == "Bluray-2160p")
  #expect(best.sizeBytes == 87_241_068_544)
  // A protocol Tower does not name is kept verbatim and shown as nothing.
  #expect(best.downloadProtocol.apiValue == "other")
  #expect(best.downloadProtocol.displayName == nil)
  #expect(best.isApproved)
  #expect(best.rejections.isEmpty)

  let rejected = releases[1]
  #expect(!rejected.isApproved)
  // Shown verbatim: these are Radarr's own words, and the reason a user either
  // overrides or moves on.
  #expect(rejected.rejections.first?.contains("already downloaded") == true)
  #expect(rejected.downloadProtocol == .usenet)

  let query = try #require(requests(host).last?.url?.query())
  #expect(query.contains("movieId=812"))
}

@Test func grabbingPostsTheGuidAndTheIndexerThatOfferedIt() async throws {
  // The same release from two indexers is two different grabs.
  let host = "radarr-grab.test"
  ServiceStubURLProtocol.stub(host: host, reply: .json("{}"))
  let repository = makeRepository(host: host)
  let release = ArrRelease(
    id: "example-indexer-0001", title: "Example.Movie.2024.2160p", indexer: "Example Indexer",
    indexerID: 3, quality: "Bluray-2160p", sizeBytes: 1,
    downloadProtocol: .usenet, publishDate: nil, ageHours: nil, isApproved: true, rejections: [])

  try await repository.grab(release)

  let request = try #require(requests(host).last)
  #expect(request.httpMethod == "POST")
  #expect(request.url?.path() == "/api/v3/release")
  let json = try jsonBody(request)
  #expect(json["guid"] as? String == "example-indexer-0001")
  #expect(json["indexerId"] as? Int == 3)
}

@Test func anAutomaticSearchRunsRadarrsOwnCommand() async throws {
  let host = "radarr-search.test"
  ServiceStubURLProtocol.stub(
    host: host, reply: .json(#"{"id":1,"name":"MoviesSearch","status":"queued"}"#))
  let repository = makeRepository(host: host)

  try await repository.search(movieID: 812)

  let request = try #require(requests(host).last)
  #expect(request.url?.path() == "/api/v3/command")
  let json = try jsonBody(request)
  #expect(json["name"] as? String == "MoviesSearch")
  // Plural, and an array — the command rejects a bare integer.
  #expect(json["movieIds"] as? [Int] == [812])
}

// MARK: - Shared surface

@Test func theSharedArrEndpointsAreReachableThroughTheRepository() async throws {
  // Radarr doesn't reimplement the queue; it exposes the shared core, which is
  // the whole reuse bet.
  let host = "radarr-shared.test"
  let repository = try makeRepository(host: host, fixture: "queue.json")

  let page = try await repository.arr.queue()

  #expect(page.items.count == 3)
  #expect(requests(host).last?.url?.path() == "/api/v3/queue")
}
