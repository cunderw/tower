import Foundation
import Testing
import TowerCore
import TowerData
@testable import Tower

/// Demo mode's *arr dataset and its mutations.
@MainActor
struct DemoArrRepositoriesTests {
  private func makeRadarr() -> (DemoRadarrRepository, DemoArrServer) {
    let server = DemoArrServer()
    let instance = DemoServices.instances.first { $0.kind == .radarr }!
    return (DemoRadarrRepository(instance: instance, server: server), server)
  }

  private func makeSonarr(server: DemoArrServer) -> DemoSonarrRepository {
    let instance = DemoServices.instances.first { $0.kind == .sonarr }!
    return DemoSonarrRepository(instance: instance, server: server)
  }

  @Test func theLibraryIsBigEnoughForSearchAndFiltersToMeanSomething() async throws {
    let (radarr, _) = makeRadarr()

    let movies = try await radarr.movies()

    #expect(movies.count >= 50, "a demo library that fits on one screen shows nothing off")
    // Every state the library screen can render.
    #expect(movies.contains { $0.libraryState == .downloaded })
    #expect(movies.contains { $0.libraryState == .missing })
    #expect(movies.contains { $0.libraryState == .unreleased })
    #expect(movies.contains { !$0.isMonitored })

    let sonarr = makeSonarr(server: DemoArrServer())
    let shows = try await sonarr.series()
    #expect(shows.count >= 12, "the demo should show at least a dozen series")
    #expect(shows.contains { !$0.isMonitored })
    #expect(shows.contains { $0.seasons.count > 1 }, "no multi-season show to expand")
  }

  @Test func addingAMovieShowsUpInTheLibrary() async throws {
    let (radarr, _) = makeRadarr()
    let candidates = try await radarr.lookup(term: "harbour")
    let lookup = candidates.first { !$0.isAlreadyAdded }
    let request = RadarrAddMovieRequest(
      lookup: try #require(lookup), qualityProfileID: 4, rootFolderPath: "/data/media/movies")

    let added = try await radarr.add(request)

    let movies = try await radarr.movies()
    #expect(movies.contains { $0.id == added.id })
  }

  @Test func editingAndDeletingAMovieBothStick() async throws {
    let (radarr, _) = makeRadarr()
    let library = try await radarr.movies()
    let movie = try #require(library.first)

    var edit = RadarrMovieEdit(movie: movie)
    edit.isMonitored = !movie.isMonitored
    _ = try await radarr.update(movie, with: edit)
    let updated = try await radarr.movie(id: movie.id)
    #expect(updated.isMonitored == edit.isMonitored)

    try await radarr.delete(id: movie.id, deleteFiles: true, addImportExclusion: false)
    let remaining = try await radarr.movies()
    #expect(!remaining.contains { $0.id == movie.id })
  }

  @Test func aLookupMarksWhatIsAlreadyInTheLibrary() async throws {
    let (radarr, _) = makeRadarr()

    let results = try await radarr.lookup(term: "cartographer")

    #expect(results.contains { $0.isAlreadyAdded })
  }

  // MARK: - Cross-service links

  @Test func theDemoUsenetQueueRowCarriesTheSharedNZBID() async throws {
    // The demo is the only place a reviewer without a server sees the queue →
    // client link, so the join key has to be seeded on this side too.
    let (radarr, _) = makeRadarr()

    let items = try await radarr.queue().items
    let usenet = try #require(items.first { $0.downloadID != nil })

    #expect(usenet.downloadProtocol == .usenet)
    #expect(usenet.downloadID == String(DemoDownloadIDs.northernLightsNZB))
  }

  // MARK: - The demo's headline path

  @Test func aMissingEpisodeHasAGrabbableReleaseThatLandsInTheQueue() async throws {
    // The demo's headline path: find the missing episode, search it, grab a
    // release, and see it in the queue. Anything less is a demo where the
    // highest-value daily action doesn't visibly work.
    let server = DemoArrServer()
    let sonarr = makeSonarr(server: server)

    let episodes = try await sonarr.episodes(seriesID: 1)
    let missing = try #require(episodes.first { $0.isMissing })
    #expect(missing.title == "The Missing Signal")

    let releases = try await sonarr.releases(episodeID: missing.id)
    let approved = try #require(releases.first { $0.isApproved })
    // The release names what was actually searched for. The grab confirmation
    // quotes this title back, so a fixture name that doesn't match the episode
    // lands in the one dialog a reviewer is most likely to read.
    #expect(approved.title.hasPrefix("Northern Lights S02E11"), "got \(approved.title)")
    let queueBefore = try await sonarr.queue().items.count

    try await sonarr.grab(approved)

    let queueAfter = try await sonarr.queue()
    #expect(queueAfter.items.count == queueBefore + 1, "the grab never reached the queue")
    #expect(queueAfter.items.contains { $0.title == approved.title })
    // And it shows up in history, where a real grab would.
    let history = try await sonarr.history(page: 1)
    #expect(history.records.contains { $0.sourceTitle == approved.title })
  }

  @Test func removingFromTheQueueTakesItOut() async throws {
    let (radarr, _) = makeRadarr()
    let queueBefore = try await radarr.queue()
    let item = try #require(queueBefore.items.first)

    try await radarr.removeQueueItem(id: item.id, removeFromClient: true, blocklist: true)

    let queue = try await radarr.queue()
    #expect(!queue.items.contains { $0.id == item.id })
  }

  @Test func radarrAndSonarrShareOneQueue() async throws {
    // One dataset per demo entry: a grab in Sonarr is visible from Radarr's
    // queue, because they are the same download client in the story the demo
    // tells.
    let server = DemoArrServer()
    let sonarr = makeSonarr(server: server)
    let instance = DemoServices.instances.first { $0.kind == .radarr }!
    let radarr = DemoRadarrRepository(instance: instance, server: server)
    let releases = try await sonarr.releases(episodeID: 2_011)
    let release = try #require(releases.first)

    try await sonarr.grab(release)

    let radarrQueue = try await radarr.queue()
    #expect(radarrQueue.items.contains { $0.title == release.title })
  }

  @Test func repeatedGrabsNeverReuseAQueueOrHistoryID() async throws {
    // The queue and history are `ForEach`ed by id, so two rows sharing one is a
    // list that draws the wrong row.
    let server = DemoArrServer()

    for index in 0..<101 {
      server.grab(
        ArrRelease(
          id: "release-\(index)", title: "Release \(index)", indexer: "Example",
          indexerID: 1, quality: "WEBDL-1080p", sizeBytes: 1_000, downloadProtocol: .usenet,
          publishDate: nil, ageHours: 1, isApproved: true, rejections: []))
    }

    let queueIDs = server.queue.map(\.id)
    let historyIDs = server.history.map(\.id)
    #expect(Set(queueIDs).count == queueIDs.count, "a grab reused a queue id")
    #expect(Set(historyIDs).count == historyIDs.count, "a grab reused a history id")
  }

  @Test func repeatedAddsNeverReuseAMovieOrSeriesID() throws {
    // More adds than a 5,000-wide random range holds, so an id scheme that
    // could repeat certainly does here. Checked against the fixtures' own ids
    // as well as each other.
    let server = DemoArrServer()
    let movie = RadarrAddMovieRequest(
      lookup: try #require(DemoArrFixtures.movieLookups(matching: "", existing: []).first),
      qualityProfileID: 4, rootFolderPath: "/data/media/movies")
    let show = SonarrAddSeriesRequest(
      lookup: try #require(DemoArrFixtures.seriesLookups(matching: "", existing: []).first),
      qualityProfileID: 4, rootFolderPath: "/data/media/tv")

    for _ in 0..<5_001 {
      _ = server.add(movie)
      _ = server.add(show)
    }

    let movieIDs = server.movies.map(\.id)
    let seriesIDs = server.series.map(\.id)

    #expect(Set(movieIDs).count == movieIDs.count, "an add reused a movie id")
    #expect(Set(seriesIDs).count == seriesIDs.count, "an add reused a series id")
  }

  // MARK: - Sonarr's three levels

  @Test func seasonMonitoringAppliesToItsEpisodes() async throws {
    let server = DemoArrServer()
    let sonarr = makeSonarr(server: server)

    try await sonarr.setSeasonMonitored(false, seriesID: 1, seasonNumber: 2)

    let episodes = try await sonarr.episodes(seriesID: 1)
    let seasonTwoUnmonitored = episodes.filter { $0.seasonNumber == 2 }.allSatisfy { !$0.isMonitored }
    let seasonOneUntouched = episodes.filter { $0.seasonNumber == 1 }.allSatisfy(\.isMonitored)
    #expect(seasonTwoUnmonitored)
    #expect(seasonOneUntouched)
    let series = try await sonarr.series(id: 1)
    #expect(series.seasons.first { $0.seasonNumber == 2 }?.isMonitored == false)
  }

  @Test func theQueueCarriesEveryStateTheScreenTellsApart() async throws {
    let (radarr, _) = makeRadarr()

    let items = try await radarr.queue().items

    #expect(items.contains { $0.trackedState == .downloading })
    #expect(items.contains { $0.needsAttention }, "no stuck item to demonstrate the badge")
    #expect(items.contains { $0.trackedState == .importPending })
  }

  @Test func theSeriesCalendarAgreesWithTheEpisodeList() throws {
    // S02E12 is the one calendar entry the episode list also carries.
    let entry = try #require(DemoArrFixtures.seriesCalendar().first { $0.id == 2_012 })
    let episode = try #require(DemoArrFixtures.episodes().first { $0.id == entry.id })

    #expect(entry.date == episode.airDate)
    #expect(entry.subtitle == "S02E12 · \(episode.title)")
  }

  @Test func theSharedSurfacesAreAllPopulated() async throws {
    let (radarr, _) = makeRadarr()

    let calendar = try await radarr.calendar(start: .distantPast, end: .distantFuture)
    let history = try await radarr.history(page: 1)
    let health = try await radarr.health()
    let disks = try await radarr.diskSpace()
    let status = try await radarr.systemStatus()
    let profiles = try await radarr.qualityProfiles()
    let folders = try await radarr.rootFolders()

    #expect(!calendar.isEmpty)
    #expect(!history.records.isEmpty)
    #expect(!health.isEmpty, "no health warning to demonstrate the list")
    #expect(!disks.isEmpty)
    #expect(status.version != nil)
    #expect(!profiles.isEmpty)
    #expect(!folders.isEmpty)
  }

  @Test func noDemoPathNamesAnAddressAndEveryFilmIsUnderTheDemoRoot() async throws {
    // The same rule as `DemoServices`: a screenshot of this ships.
    let (radarr, _) = makeRadarr()
    let folders = try await radarr.rootFolders()
    let disks = try await radarr.diskSpace()
    let movies = try await radarr.movies()

    for path in folders.map(\.path) + disks.map(\.path) {
      #expect(path.range(of: #"\d+\.\d+\.\d+\.\d+"#, options: .regularExpression) == nil, "\(path) names an address")
    }
    let allUnderDemoRoot = movies.allSatisfy { $0.path?.contains("/data/media") == true }
    #expect(allUnderDemoRoot)
  }
}
