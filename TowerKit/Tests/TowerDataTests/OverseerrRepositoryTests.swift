import Foundation
import Testing
import TowerCore

@testable import TowerData

/// `LiveOverseerrRepository` end to end: committed fixtures answered
/// through the real `ServiceHTTPClient` and a stubbed `URLProtocol`, so the
/// path, the query, the decoding, and the mapping are all under test together.
private func fixture(_ name: String) throws -> Data {
  let url = try #require(
    Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures/Overseerr"),
    "missing fixture \(name)")
  return try Data(contentsOf: url)
}

private func makeRepository(host: String) -> LiveOverseerrRepository {
  let instance = ServiceInstance(
    kind: .overseerr, name: "Overseerr", baseURL: URL(string: "http://\(host)")!,
    credentials: .apiKey("k"))
  return LiveOverseerrRepository(
    instance: instance,
    client: ServiceHTTPClient(
      instance: instance, sessionConfiguration: ServiceStubURLProtocol.configuration()))
}

/// Routes by path, because most of these flows make more than one call.
private func stub(host: String, _ answer: @escaping @Sendable (String) -> Data) {
  ServiceStubURLProtocol.stub(host: host) { request in
    .reply(.init(status: 200, body: answer(request.url?.path() ?? "")))
  }
}

private func requests(_ host: String) -> [URLRequest] {
  ServiceStubURLProtocol.requests(host: host)
}

// MARK: - Requests and pagination

@Suite struct OverseerrRequestTests {
  private func stubRequests(host: String) throws {
    let page = try fixture("requests-page1.json")
    let movie = try fixture("movie-details.json")
    let tv = try fixture("tv-details.json")
    stub(host: host) { path in
      if path.contains("/movie/") { return movie }
      if path.contains("/tv/") { return tv }
      return page
    }
  }

  @Test func theRequestListMapsStatusRequesterAndSeasons() async throws {
    let host = "os-requests.invalid"
    try stubRequests(host: host)

    let page = try await makeRepository(host: host).requests(filter: .all, page: 1)

    #expect(page.requests.count == 2)
    let pending = page.requests[0]
    #expect(pending.status == .pending)
    #expect(pending.status.isActionable)
    // Overseerr's own precedence: displayName beats plexUsername beats username.
    #expect(pending.requestedBy == "Alex Doe")
    #expect(pending.mediaType == .movie)
    #expect(pending.mediaStatus == .pending)
    #expect(!pending.is4K)

    let approved = page.requests[1]
    #expect(approved.status == .approved)
    #expect(approved.is4K)
    #expect(approved.mediaType == .tv)
    #expect(approved.mediaStatus == .partiallyAvailable)
    // Sorted, because the API sends them in request order and a season list
    // that reads 2, 1 looks like a bug.
    #expect(approved.seasons == [1, 2])
    // No displayName on this user, so the username is next.
    #expect(approved.requestedBy == "bee")
  }

  @Test func anUnrecognisedStatusDegradesTheRowRatherThanTheScreen() async throws {
    let host = "os-newstatus.invalid"
    stub(host: host) { _ in
      Data(#"{"pageInfo":{"pages":1,"results":1},"results":[{"id":1,"status":99,"media":{"mediaType":"movie","tmdbId":1}}]}"#.utf8)
    }
    // The title lookup will 404-ish through the same stub, which is fine — the
    // point is the list survives.
    let page = try await makeRepository(host: host).requests(filter: .all, page: 1)

    #expect(page.requests.count == 1)
    #expect(page.requests[0].status == .unknown)
  }

  // MARK: - Pagination

  @Test func paginationConvertsPageNumbersToOverseerrsOffset() async throws {
    // Overseerr takes `skip`, not a page number. Sending the page number as an
    // offset would show page 3 as rows 3–22.
    let host = "os-paging.invalid"
    try stubRequests(host: host)
    let repository = makeRepository(host: host)

    _ = try await repository.requests(filter: .all, page: 1)
    var query = try #require(requests(host).first?.url?.query())
    #expect(query.contains("skip=0"), "got \(query)")
    #expect(query.contains("take=20"))

    _ = try await repository.requests(filter: .pending, page: 3)
    let listCalls = requests(host).filter { $0.url?.path().hasSuffix("/request") == true }
    query = try #require(listCalls.last?.url?.query())
    #expect(query.contains("skip=40"), "got \(query)")
    #expect(query.contains("filter=pending"))
  }

  @Test func thePageReportsWhetherThereIsMore() async throws {
    let host = "os-hasmore.invalid"
    try stubRequests(host: host)

    let page = try await makeRepository(host: host).requests(filter: .all, page: 1)

    #expect(page.pages == 2)
    #expect(page.totalResults == 23)
    #expect(page.hasMore, "page 1 of 2 didn't report more")

    let last = try await makeRepository(host: host).requests(filter: .all, page: 2)
    #expect(!last.hasMore, "page 2 of 2 claimed more")
  }

  // MARK: - Titles

  @Test func aRequestWithoutATitleIsFilledInFromTheMediaDetail() async throws {
    // Overseerr's `/request` response carries ids, not names — the title lives
    // behind a second call, and a list of "Movie #700001" is unusable.
    let host = "os-titles.invalid"
    try stubRequests(host: host)

    let page = try await makeRepository(host: host).requests(filter: .all, page: 1)

    #expect(page.requests[0].title == "The Cartographer")
    #expect(page.requests[0].posterURL?.absoluteString.hasSuffix("/carto.jpg") == true)
    // The second already had a name inline and must not be looked up again.
    #expect(page.requests[1].title == "Northern Lights")
    let tvLookups = requests(host).filter { $0.url?.path().contains("/tv/") == true }
    #expect(tvLookups.isEmpty, "looked up a title the list already had")
  }

  @Test func aFailedTitleLookupCostsTheTitleNotTheList() async throws {
    // A request you can still approve with the title missing beats an error
    // screen.
    let host = "os-titlefail.invalid"
    let page = try fixture("requests-page1.json")
    ServiceStubURLProtocol.stub(host: host) { request in
      if request.url?.path().contains("/movie/") == true {
        return .reply(.init(status: 500, body: Data()))
      }
      return .reply(.init(status: 200, body: page))
    }

    let result = try await makeRepository(host: host).requests(filter: .all, page: 1)

    #expect(result.requests.count == 2, "the list was lost to a title lookup")
    #expect(result.requests[0].title == nil)
    // And the row still says something useful.
    #expect(result.requests[0].displayTitle == "Movie #700001")
  }

  @Test func everyRequestGetsItsTitleLookedUp() async throws {
    // Eight requests, each needing its own lookup, all come back titled. The
    // stub answers instantly, so this does not show the lookups run
    // concurrently.
    let host = "os-concurrent.invalid"
    let manyResults = (1...8).map {
      #"{"id":\#($0),"status":1,"media":{"mediaType":"movie","tmdbId":70000\#($0)}}"#
    }.joined(separator: ",")
    let page = Data(#"{"pageInfo":{"pages":1,"results":8},"results":[\#(manyResults)]}"#.utf8)
    let movie = try fixture("movie-details.json")
    stub(host: host) { path in path.contains("/movie/") ? movie : page }

    let result = try await makeRepository(host: host).requests(filter: .all, page: 1)

    #expect(result.requests.count == 8)
    #expect(result.requests.allSatisfy { $0.title == "The Cartographer" })
  }

  // MARK: - Actions

  @Test func approveAndDeclinePostToTheStatusPathSegment() async throws {
    // The status is a path segment, not a body — a POST with a JSON status is
    // accepted and does nothing.
    let host = "os-decide.invalid"
    stub(host: host) { _ in Data("{}".utf8) }
    let repository = makeRepository(host: host)

    try await repository.approve(requestID: 501)
    #expect(requests(host).last?.url?.path().hasSuffix("/request/501/approve") == true)
    #expect(requests(host).last?.httpMethod == "POST")

    try await repository.decline(requestID: 501)
    #expect(requests(host).last?.url?.path().hasSuffix("/request/501/decline") == true)
  }
}

// MARK: - Search and submit

@Suite struct OverseerrSearchTests {
  @Test func searchDropsPeopleAndKeepsRequestableMedia() async throws {
    // `/search` mixes actors in with films; a person is not something Tower can
    // request, and rendering one as a requestable row is the bug this prevents.
    let host = "os-search.invalid"
    let body = try fixture("search.json")
    stub(host: host) { _ in body }

    let results = try await makeRepository(host: host).search(term: "lights")

    #expect(results.count == 2, "a person survived the filter")
    #expect(results.map(\.mediaType) == [.movie, .tv])
  }

  @Test func aSearchResultCarriesItsYearPosterAndLibraryState() async throws {
    let host = "os-searchmap.invalid"
    let body = try fixture("search.json")
    stub(host: host) { _ in body }

    let results = try await makeRepository(host: host).search(term: "lights")

    let movie = results[0]
    #expect(movie.title == "Harbour Lights")
    // TMDB sends `yyyy-MM-dd`, not ISO 8601 — the shared decoder's strategy
    // does not apply and the mapping parses it explicitly.
    #expect(movie.year == 2026)
    #expect(movie.posterURL?.absoluteString == "https://image.tmdb.org/t/p/w500/hl.jpg")
    #expect(!movie.isAlreadyInLibrary)

    // The series is already available, so the sheet can say so instead of
    // offering a duplicate request.
    let series = results[1]
    #expect(series.mediaStatus == .available)
    #expect(series.isAlreadyInLibrary)
  }

  @Test func anEmptySearchIsNotARequest() async throws {
    let host = "os-emptysearch.invalid"
    stub(host: host) { _ in Data("{}".utf8) }

    let results = try await makeRepository(host: host).search(term: "   ")

    #expect(results.isEmpty)
    #expect(requests(host).isEmpty, "an empty search reached the service")
  }

  @Test func seasonsDropTMDBsEmptyPlaceholderAndPutSpecialsFirst() async throws {
    let host = "os-seasons.invalid"
    let body = try fixture("tv-details.json")
    stub(host: host) { _ in body }

    let seasons = try await makeRepository(host: host).seasons(tmdbID: 700_002)

    // Season 3 has no episodes — TMDB placeholder noise.
    #expect(seasons.map(\.seasonNumber) == [0, 1, 2])
    #expect(seasons[0].displayName == "Specials")
    #expect(seasons[1].episodeCount == 12)
  }

  // MARK: - TV season selection

  @Test func aTVRequestSendsItsSelectedSeasons() async throws {
    let host = "os-submit-tv.invalid"
    stub(host: host) { _ in Data(#"{"id":9,"status":1,"media":{"mediaType":"tv","tmdbId":700002}}"#.utf8) }

    _ = try await makeRepository(host: host).submit(
      SubmitRequest(mediaType: .tv, mediaID: 700_002, seasons: [1, 2]))

    let body = String(decoding: requests(host).last?.recordedBody ?? Data(), as: UTF8.self)
    #expect(body.contains("\"mediaType\":\"tv\""), "got \(body)")
    #expect(body.contains("\"mediaId\":700002"))
    #expect(body.contains("\"seasons\":[1,2]"))
  }

  @Test func anAllSeasonsRequestOmitsTheKeyRatherThanSendingAnEmptyArray() async throws {
    // Overseerr treats `"seasons": []` as *none* on some builds, which files a
    // request for a series and no episodes — a request that can never complete.
    let host = "os-submit-all.invalid"
    stub(host: host) { _ in Data(#"{"id":9,"status":1,"media":{"mediaType":"tv","tmdbId":1}}"#.utf8) }

    _ = try await makeRepository(host: host).submit(
      SubmitRequest(mediaType: .tv, mediaID: 700_002, seasons: []))

    let body = String(decoding: requests(host).last?.recordedBody ?? Data(), as: UTF8.self)
    #expect(!body.contains("seasons"), "an empty seasons array was sent: \(body)")
  }

  @Test func aMovieRequestNeverSendsSeasons() async throws {
    let host = "os-submit-movie.invalid"
    stub(host: host) { _ in Data(#"{"id":9,"status":1,"media":{"mediaType":"movie","tmdbId":1}}"#.utf8) }

    _ = try await makeRepository(host: host).submit(
      // Seasons supplied by a caller that shouldn't have; they must be dropped.
      SubmitRequest(mediaType: .movie, mediaID: 700_001, seasons: [1], is4K: true))

    let body = String(decoding: requests(host).last?.recordedBody ?? Data(), as: UTF8.self)
    #expect(!body.contains("seasons"), "got \(body)")
    #expect(body.contains("\"is4k\":true"))
  }
}

// MARK: - Issues

@Suite struct OverseerrIssueTests {
  @Test func issuesMapTypeStatusAndComments() async throws {
    let host = "os-issues.invalid"
    let body = try fixture("issues.json")
    stub(host: host) { _ in body }

    let issues = try await makeRepository(host: host).issues(includeResolved: true)

    #expect(issues.count == 2)
    let audio = issues[0]
    #expect(audio.type == .audio)
    #expect(audio.status == .open)
    #expect(audio.createdBy == "Alex Doe")
    #expect(audio.title == "The Cartographer")
    #expect(audio.comments.count == 1)
    #expect(audio.comments[0].message.hasPrefix("Audio is out of sync"))
    #expect(audio.comments[0].author == "Alex Doe")

    let subtitles = issues[1]
    #expect(subtitles.type == .subtitles)
    #expect(subtitles.status == .resolved)
    // No title inline and no lookup for issues — the fallback has to be usable.
    #expect(subtitles.displayTitle == "Series #700002")
  }

  @Test func theOpenFilterIsAskedForRatherThanFilteredLocally() async throws {
    // Filtering client-side would page through resolved issues to find open
    // ones.
    let host = "os-issuefilter.invalid"
    let body = try fixture("issues.json")
    stub(host: host) { _ in body }
    let repository = makeRepository(host: host)

    _ = try await repository.issues(includeResolved: false)
    #expect(requests(host).last?.url?.query()?.contains("filter=open") == true)

    _ = try await repository.issues(includeResolved: true)
    #expect(requests(host).last?.url?.query()?.contains("filter=all") == true)
  }

  @Test func commentingPostsTheMessage() async throws {
    let host = "os-comment.invalid"
    stub(host: host) { _ in Data("{}".utf8) }

    try await makeRepository(host: host).comment(issueID: 12, message: "  Still broken.  ")

    let request = try #require(requests(host).last)
    #expect(request.url?.path().hasSuffix("/issue/12/comment") == true)
    let body = String(decoding: request.recordedBody ?? Data(), as: UTF8.self)
    // Trimmed: a comment of pure whitespace is not a comment.
    #expect(body.contains("\"message\":\"Still broken.\""), "got \(body)")
  }

  @Test func anEmptyCommentIsNotSent() async throws {
    let host = "os-emptycomment.invalid"
    stub(host: host) { _ in Data("{}".utf8) }

    try await makeRepository(host: host).comment(issueID: 12, message: "   ")

    #expect(requests(host).isEmpty)
  }

  @Test func resolvingAndReopeningUseThePathSegment() async throws {
    let host = "os-resolve.invalid"
    stub(host: host) { _ in Data("{}".utf8) }
    let repository = makeRepository(host: host)

    try await repository.setIssueResolved(true, issueID: 12)
    #expect(requests(host).last?.url?.path().hasSuffix("/issue/12/resolved") == true)

    try await repository.setIssueResolved(false, issueID: 12)
    #expect(requests(host).last?.url?.path().hasSuffix("/issue/12/open") == true)
  }
}
