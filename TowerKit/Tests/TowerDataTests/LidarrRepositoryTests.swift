import Foundation
import Testing
import TowerCore

@testable import TowerData

/// `LiveLidarrRepository` end to end: the artist → album → track
/// hierarchy against committed fixtures, and the proof that the shared *arr
/// surface is reused rather than reimplemented.
private func fixture(_ name: String) throws -> Data {
  let url = try #require(
    Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures/Lidarr"),
    "missing fixture \(name)")
  return try Data(contentsOf: url)
}

private func makeRepository(host: String) -> LiveLidarrRepository {
  let instance = ServiceInstance(
    kind: .lidarr, name: "Lidarr", baseURL: URL(string: "http://\(host)")!,
    credentials: .apiKey("k"))
  return LiveLidarrRepository(
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

private func lastBody(_ host: String) -> String {
  String(decoding: requests(host).last?.recordedBody ?? Data(), as: UTF8.self)
}

// MARK: - The hierarchy

@Suite struct LidarrHierarchyTests {
  @Test func artistsMapAndSortByLidarrsOwnSortName() async throws {
    // So Tower and the service agree about where "The Wandering Signal"
    // belongs — under W, not T.
    let host = "ld-artists.invalid"
    let body = try fixture("artists.json")
    stub(host: host) { _ in body }

    let artists = try await makeRepository(host: host).artists()

    #expect(artists.map(\.name) == ["Anvil Choir", "Quiet Ledger", "The Wandering Signal"])
    let signal = try #require(artists.first { $0.id == 1 })
    #expect(signal.status == .continuing)
    #expect(signal.isMonitored)
    #expect(signal.metadataProfileID == 2)
    #expect(signal.genres == ["Post-rock"])
    #expect(signal.tagIDs == [3])
    // `remoteUrl`, not the service-relative `url` — the latter needs an API key
    // an `AsyncImage` won't send.
    #expect(signal.posterURL?.absoluteString == "https://images.example.invalid/tws.jpg")
  }

  @Test func theLibraryStateIsThreeWayBecauseADiscographyIsRarelyAllOrNothing() async throws {
    let host = "ld-state.invalid"
    let body = try fixture("artists.json")
    stub(host: host) { _ in body }

    let artists = try await makeRepository(host: host).artists()

    // 38 of 44 tracked tracks.
    #expect(artists.first { $0.id == 1 }?.libraryState == .partial)
    // Nothing on disk.
    #expect(artists.first { $0.id == 2 }?.libraryState == .missing)
    #expect(artists.first { $0.id == 3 }?.libraryState == .complete)
  }

  @Test func progressCountsMonitoredTracksNotEveryTrackTheArtistHas() async throws {
    // Counting unmonitored albums would make every artist look permanently
    // incomplete — the same reasoning as Sonarr's aired-versus-total.
    let host = "ld-progress.invalid"
    let body = try fixture("artists.json")
    stub(host: host) { _ in body }

    let artists = try await makeRepository(host: host).artists()
    let statistics = try #require(artists.first { $0.id == 1 }?.statistics)

    #expect(statistics.trackCount == 44)
    #expect(statistics.totalTrackCount == 52)
    // 38/44, not 38/52.
    #expect(abs((statistics.progress ?? 0) - 0.8636) < 0.001)
  }

  @Test func albumsComeBackNewestFirst() async throws {
    // A discography is read from the current record backwards — the opposite
    // of how a series' seasons are read.
    let host = "ld-albums.invalid"
    let body = try fixture("albums.json")
    stub(host: host) { _ in body }

    let albums = try await makeRepository(host: host).albums(artistID: 1)

    #expect(albums.map(\.id) == [12, 10, 11])
    #expect(requests(host).last?.url?.query()?.contains("artistId=1") == true)
  }

  @Test func anAlbumCarriesItsTypesDisambiguationAndArtwork() async throws {
    let host = "ld-albumdetail.invalid"
    let body = try fixture("albums.json")
    stub(host: host) { _ in body }

    let albums = try await makeRepository(host: host).albums(artistID: 1)
    let longWave = try #require(albums.first { $0.id == 10 })

    #expect(longWave.displayTitle == "Long Wave (deluxe edition)")
    #expect(longWave.albumType == "Album")
    #expect(longWave.secondaryTypes == ["Live"])
    #expect(longWave.year == 2025)
    #expect(longWave.libraryState == .complete)
    #expect(longWave.coverURL?.absoluteString == "https://images.example.invalid/longwave.jpg")
  }

  @Test func anUnreleasedAlbumIsNotTreatedAsAvailable() async throws {
    // Offering a search for one sends the user after something that does not
    // exist yet.
    let host = "ld-unreleased.invalid"
    let body = try fixture("albums.json")
    stub(host: host) { _ in body }

    let albums = try await makeRepository(host: host).albums(artistID: 1)
    let future = try #require(albums.first { $0.id == 12 })

    #expect(!future.isReleased)
    #expect(future.libraryState == .missing)
    let released = try #require(albums.first { $0.id == 11 })
    #expect(released.isReleased)
    #expect(released.libraryState == .partial)
  }

  @Test func tracksSortByDiscThenTrackSoADoubleAlbumDoesNotInterleave() async throws {
    // `absoluteTrackNumber` alone would put the second disc's opener between
    // the first disc's tracks.
    let host = "ld-tracks.invalid"
    let body = try fixture("tracks.json")
    stub(host: host) { _ in body }

    let tracks = try await makeRepository(host: host).tracks(albumID: 10)

    #expect(tracks.map(\.id) == [301, 302, 300])
    // Track numbers are *strings*: vinyl and multi-disc releases use "A1".
    #expect(tracks.map(\.trackNumber) == ["A1", "A2", "B1"])
    #expect(tracks[0].hasFile)
    #expect(!tracks[1].hasFile)
    #expect(tracks[1].isExplicit)
  }
}

// MARK: - Add, edit, and pickers

@Suite struct LidarrAddEditTests {
  @Test func aLookupHitAlreadyInTheLibraryIsMarked() async throws {
    // Lidarr answers `/artist/lookup` with artist resources whose `id` is **0**
    // for anything not in the library. Reading that literally would mark every
    // result as already added.
    let host = "ld-lookup.invalid"
    let body = try fixture("artist-lookup.json")
    stub(host: host) { _ in body }

    let hits = try await makeRepository(host: host).lookup(term: "harbour")

    #expect(hits.count == 3)
    let fresh = try #require(hits.first { $0.name == "Harbour Choir" })
    #expect(!fresh.isAlreadyAdded)
    #expect(fresh.existingArtistID == nil)
    #expect(fresh.disambiguation == "the Bristol one")
    #expect(fresh.foreignArtistID == "dd44ee55-ff66-7788-9900-112233445566")

    let existing = try #require(hits.first { $0.name == "The Wandering Signal" })
    #expect(existing.isAlreadyAdded)
    #expect(existing.existingArtistID == 1)
  }

  @Test func aLookupHitThatOmitsItsIDStillDecodes() async throws {
    // Newer *arr builds omit `id` rather than sending 0. Decoded as required, one
    // such hit fails the whole array, so a single result breaks every artist
    // search.
    let host = "ld-lookup-noid.invalid"
    let body = try fixture("artist-lookup.json")
    stub(host: host) { _ in body }

    let hits = try await makeRepository(host: host).lookup(term: "harbour")

    let fresh = try #require(hits.first { $0.name == "Unindexed Ensemble" })
    #expect(!fresh.isAlreadyAdded)
    #expect(fresh.existingArtistID == nil)
    // Lidarr keys a lookup hit by its MusicBrainz id, which is present even
    // when the Lidarr-side `id` is not — so the row is still addable.
    #expect(fresh.foreignArtistID == "aa11bb22-cc33-4455-6677-889900aabbcc")
  }

  @Test func anEmptyLookupIsNotARequest() async throws {
    let host = "ld-emptylookup.invalid"
    stub(host: host) { _ in Data("[]".utf8) }

    let hits = try await makeRepository(host: host).lookup(term: "   ")

    #expect(hits.isEmpty)
    #expect(requests(host).isEmpty)
  }

  @Test func addingSendsBothProfilesAndTheMonitorOption() async throws {
    let host = "ld-add.invalid"
    let lookupBody = try fixture("artist-lookup.json")
    stub(host: host) { path in
      path.hasSuffix("artist/lookup") ? lookupBody : Data(#"{"id":9,"artistName":"Harbour Choir"}"#.utf8)
    }
    let repository = makeRepository(host: host)
    let hit = try #require(try await repository.lookup(term: "harbour").first)

    _ = try await repository.add(
      LidarrAddArtistRequest(
        lookup: hit, qualityProfileID: 4, metadataProfileID: 2,
        rootFolderPath: "/data/media/music", monitorOption: .future,
        searchForMissingAlbums: false, tagIDs: [7]))

    let body = lastBody(host)
    #expect(body.contains("\"foreignArtistId\":\"dd44ee55-ff66-7788-9900-112233445566\""))
    #expect(body.contains("\"qualityProfileId\":4"))
    // The second profile axis, which has no Radarr or Sonarr equivalent.
    #expect(body.contains("\"metadataProfileId\":2"))
    #expect(body.contains("\"monitor\":\"future\""))
    #expect(body.contains("\"searchForMissingAlbums\":false"))
    #expect(body.contains("\"tags\":[7]"))
  }

  @Test func editingReadsTheArtistBackAndPutsTheWholeThing() async throws {
    // Lidarr's PUT merges a fixed set of fields onto the stored record, so a
    // body built only from what Tower models would reset the ones it doesn't.
    let host = "ld-edit.invalid"
    let artists = try fixture("artists.json")
    let single = Data(
      #"{"id":1,"artistName":"The Wandering Signal","foreignArtistId":"aa11","monitored":true,"qualityProfileId":1,"metadataProfileId":2,"path":"/data/media/music/TWS","rootFolderPath":"/data/media/music","tags":[3],"monitorNewItems":"none"}"#
        .utf8)
    ServiceStubURLProtocol.stub(host: host) { request in
      if request.httpMethod == "PUT" { return .reply(.init(status: 200, body: single)) }
      if request.url?.path().hasSuffix("/artist") == true {
        return .reply(.init(status: 200, body: artists))
      }
      return .reply(.init(status: 200, body: single))
    }
    let repository = makeRepository(host: host)
    let artist = try #require(try await repository.artists().first { $0.id == 1 })

    var edit = LidarrArtistEdit(artist: artist)
    edit.isMonitored = false
    edit.metadataProfileID = 1
    edit.tagIDs = []
    _ = try await repository.update(artist, with: edit)

    let put = try #require(requests(host).last)
    #expect(put.httpMethod == "PUT")
    let body = String(decoding: put.recordedBody ?? Data(), as: UTF8.self)
    #expect(body.contains("\"monitored\":false"))
    #expect(body.contains("\"metadataProfileId\":1"))
    #expect(body.contains("\"tags\":[]"))
    // The fields Tower didn't touch came back on the wire.
    #expect(body.contains("\"foreignArtistId\":\"aa11\""))
    // Matched without the slashes: `JSONEncoder` escapes `/` as `\/`, which is
    // valid JSON and accepted everywhere, so the test reads around it rather
    // than the encoder being changed to suit the test.
    #expect(body.contains("TWS"), "the path Tower doesn't model was dropped: \(body)")
    // A field Tower doesn't model, which Lidarr applies on PUT and resets to
    // its first value when it is missing.
    #expect(
      body.contains("\"monitorNewItems\":\"none\""),
      "monitorNewItems was dropped: \(body)")
  }

  @Test func deletingNeverDefaultsTheDestructiveHalfOn() async throws {
    let host = "ld-delete.invalid"
    stub(host: host) { _ in Data() }

    try await makeRepository(host: host).delete(
      id: 1, deleteFiles: false, addImportExclusion: true)

    let query = try #require(requests(host).last?.url?.query())
    #expect(query.contains("deleteFiles=false"))
    #expect(query.contains("addImportListExclusion=true"))
  }

  @Test func albumMonitoringUsesTheBulkEndpointRatherThanAWholeAlbumPUT() async throws {
    // The dedicated endpoint exists for the single-flag case and can't drop a
    // field by omission.
    let host = "ld-monitor.invalid"
    stub(host: host) { _ in Data() }

    try await makeRepository(host: host).setAlbumMonitored(false, albumIDs: [10, 11])

    let request = try #require(requests(host).last)
    #expect(request.url?.path().hasSuffix("/album/monitor") == true)
    #expect(request.httpMethod == "PUT")
    let body = String(decoding: request.recordedBody ?? Data(), as: UTF8.self)
    #expect(body.contains("\"albumIds\":[10,11]"))
    #expect(body.contains("\"monitored\":false"))
  }

  @Test func anEmptyAlbumSelectionSendsNothing() async throws {
    let host = "ld-monitor-empty.invalid"
    stub(host: host) { _ in Data() }

    try await makeRepository(host: host).setAlbumMonitored(true, albumIDs: [])

    #expect(requests(host).isEmpty)
  }

  // MARK: - Live-backed pickers

  @Test func bothProfilePickersAreBackedByLiveValues() async throws {
    let host = "ld-pickers.invalid"
    let metadata = try fixture("metadataprofiles.json")
    let quality = Data(#"[{"id":1,"name":"Lossless"},{"id":4,"name":"Standard"}]"#.utf8)
    stub(host: host) { path in path.contains("metadataprofile") ? metadata : quality }
    let repository = makeRepository(host: host)

    let metadataProfiles = try await repository.metadataProfiles()
    #expect(metadataProfiles.map(\.name) == ["Standard", "Everything"])

    // Quality profiles come from the shared core — not reimplemented here.
    let qualityProfiles = try await repository.qualityProfiles()
    #expect(qualityProfiles.map(\.name) == ["Lossless", "Standard"])
  }
}

// MARK: - Reuse and search

@Suite struct LidarrSharedSurfaceTests {
  /// Shared `ArrClientCore` endpoints are reused, not duplicated, asserted on
  /// the wire: every one of these has to arrive at
  /// Lidarr's **v1** path, which only happens if it went through the shared
  /// core configured with `api/v1`.
  @Test func theSharedSurfaceGoesThroughArrClientCoreAtV1() async throws {
    let host = "ld-shared.invalid"
    stub(host: host) { path in
      if path.contains("queue") { return Data(#"{"records":[],"page":1,"pageSize":50,"totalRecords":0}"#.utf8) }
      if path.contains("history") { return Data(#"{"records":[],"page":1,"pageSize":50,"totalRecords":0}"#.utf8) }
      if path.contains("system/status") { return Data(#"{"version":"2.1.0","appName":"Lidarr"}"#.utf8) }
      return Data("[]".utf8)
    }
    let repository = makeRepository(host: host)

    _ = try await repository.queue()
    _ = try await repository.calendar(start: .now, end: .now)
    _ = try await repository.history(page: 1)
    _ = try await repository.health()
    _ = try await repository.diskSpace()
    _ = try await repository.systemStatus()
    _ = try await repository.rootFolders()
    _ = try await repository.tags()

    let paths = requests(host).compactMap { $0.url?.path() }
    #expect(paths.count == 8)
    #expect(paths.allSatisfy { $0.contains("/api/v1/") }, "got \(paths)")
    // And they are the shared core's own endpoint names, not Lidarr-specific
    // reimplementations.
    for expected in [
      "queue", "calendar", "history", "health", "diskspace", "system/status", "rootfolder", "tag",
    ] {
      #expect(paths.contains { $0.contains(expected) }, "no request hit \(expected)")
    }
  }

  @Test func searchRunsAtBothArtistAndAlbumLevel() async throws {
    let host = "ld-search.invalid"
    stub(host: host) { _ in Data(#"{"id":1,"name":"ArtistSearch","status":"queued"}"#.utf8) }
    let repository = makeRepository(host: host)

    try await repository.searchArtist(id: 1)
    #expect(lastBody(host).contains("\"name\":\"ArtistSearch\""))
    #expect(lastBody(host).contains("\"artistId\":1"))

    try await repository.searchAlbum(id: 10)
    #expect(lastBody(host).contains("\"name\":\"AlbumSearch\""))
    // Plural on the wire even for one album, which is what Lidarr expects.
    #expect(lastBody(host).contains("\"albumIds\":[10]"))
  }

  @Test func interactiveSearchWorksAtBothLevels() async throws {
    let host = "ld-releases.invalid"
    let releases = Data(
      #"[{"guid":"r1","title":"Long.Wave.FLAC","indexerId":2,"indexer":"Example","size":734003200,"protocol":"usenet","approved":true,"rejections":[]}]"#
        .utf8)
    stub(host: host) { _ in releases }
    let repository = makeRepository(host: host)

    _ = try await repository.releases(artistID: 1)
    #expect(requests(host).last?.url?.query()?.contains("artistId=1") == true)

    let albumReleases = try await repository.releases(albumID: 10)
    #expect(requests(host).last?.url?.query()?.contains("albumId=10") == true)
    #expect(albumReleases.count == 1)
    #expect(albumReleases[0].title == "Long.Wave.FLAC")
  }

  @Test func grabbingSendsTheGuidAndTheIndexerThatOfferedIt() async throws {
    // The same release from two indexers is two different grabs.
    let host = "ld-grab.invalid"
    let releases = Data(
      #"[{"guid":"r1","title":"Long.Wave.FLAC","indexerId":2,"indexer":"Example","size":1,"protocol":"usenet","approved":true,"rejections":[]}]"#
        .utf8)
    stub(host: host) { _ in releases }
    let repository = makeRepository(host: host)
    let release = try #require(try await repository.releases(albumID: 10).first)

    try await repository.grab(release)

    let post = try #require(requests(host).last)
    #expect(post.httpMethod == "POST")
    #expect(post.url?.path().hasSuffix("/api/v1/release") == true)
    let body = String(decoding: post.recordedBody ?? Data(), as: UTF8.self)
    #expect(body.contains("\"guid\":\"r1\""))
    #expect(body.contains("\"indexerId\":2"))
  }
}
