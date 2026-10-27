import Foundation
import Testing
import TowerCore
import TowerData

@testable import Tower

/// Demo mode's Lidarr and Bazarr, including their actions checked in demo
/// mode.
@MainActor
struct DemoLidarrBazarrTests {
  private func makeLidarr() -> (DemoLidarrRepository, DemoLidarrServer, DemoArrServer) {
    let server = DemoLidarrServer()
    let arrServer = DemoArrServer()
    let instance = DemoServices.instances.first { $0.kind == .lidarr }!
    return (
      DemoLidarrRepository(instance: instance, server: server, arrServer: arrServer),
      server, arrServer
    )
  }

  private func makeBazarr() -> (DemoBazarrRepository, DemoBazarrServer) {
    let server = DemoBazarrServer()
    let instance = DemoServices.instances.first { $0.kind == .bazarr }!
    return (DemoBazarrRepository(instance: instance, server: server), server)
  }

  // MARK: - Lidarr's dataset

  @Test func theLidarrDemoSpansTheStatesTheLibraryRowCanRender() async throws {
    let (lidarr, _, _) = makeLidarr()

    let artists = try await lidarr.artists()
    #expect(artists.count >= 4)
    // Complete, partial, and nothing-on-disk — a library of four identical
    // artists would demo nothing.
    #expect(artists.contains(where: { $0.statistics?.trackFileCount == 0 }))
    #expect(
      artists.contains(where: {
        guard let stats = $0.statistics else { return false }
        return stats.trackFileCount > 0 && stats.trackFileCount < stats.totalTrackCount
      }))
    #expect(
      artists.contains(where: {
        guard let stats = $0.statistics else { return false }
        return stats.trackFileCount == stats.totalTrackCount && stats.trackFileCount > 0
      }))
    #expect(artists.contains(where: { !$0.isMonitored }))
  }

  @Test func theAlbumListCoversComplete_partial_andUnreleased() async throws {
    let (lidarr, _, _) = makeLidarr()

    let albums = try await lidarr.albums(artistID: 1)

    #expect(
      albums.contains(where: {
        guard let stats = $0.statistics else { return false }
        return stats.trackFileCount > 0 && stats.trackFileCount == stats.trackCount
      }))
    #expect(albums.contains(where: { $0.statistics?.trackFileCount == 0 }))
    #expect(albums.contains(where: { !$0.isMonitored }))
    let unreleased = albums.filter({ ($0.releaseDate ?? .distantPast) > Date() })
    #expect(!unreleased.isEmpty)
    let partial = albums.filter({
      guard let stats = $0.statistics else { return false }
      return stats.trackFileCount > 0 && stats.trackFileCount < stats.trackCount
    })
    #expect(!partial.isEmpty)
  }

  @Test func eachArtistsStatisticsAreTheSumOfItsAlbums() throws {
    // The library row reads the artist's statistics and the artist screen
    // lists the albums, so a disagreement shows on the first tap.
    let albums = DemoLidarrFixtures.albums()

    for artist in DemoLidarrFixtures.artists() {
      let stats = try #require(artist.statistics)
      let own = (albums[artist.id] ?? []).compactMap(\.statistics)
      #expect(stats.albumCount == own.count, "\(artist.name)")
      #expect(stats.trackFileCount == own.reduce(0) { $0 + $1.trackFileCount }, "\(artist.name)")
      #expect(stats.trackCount == own.reduce(0) { $0 + $1.trackCount }, "\(artist.name)")
      #expect(
        stats.totalTrackCount == own.reduce(0) { $0 + $1.totalTrackCount }, "\(artist.name)")
      #expect(
        stats.sizeOnDiskBytes == own.reduce(Int64(0)) { $0 + $1.sizeOnDiskBytes }, "\(artist.name)")
    }
  }

  @Test func trackedCountsFollowLidarrsRule() throws {
    // Lidarr counts a track when its album is monitored and released, or when
    // the track already has a file.
    let albums = try #require(DemoLidarrFixtures.albums()[1])
    let unreleased = try #require(albums.first { $0.id == 12 }?.statistics)
    #expect(unreleased.trackCount == 0)
    #expect(unreleased.totalTrackCount == 4)
    let unmonitoredOnDisk = try #require(albums.first { $0.id == 13 }?.statistics)
    #expect(unmonitoredOnDisk.trackCount == 12)
    let artist = try #require(DemoLidarrFixtures.artists().first { $0.id == 1 }?.statistics)
    #expect(artist.trackFileCount == 26)
    #expect(artist.trackCount == 31)
    #expect(artist.totalTrackCount == 35)
  }

  @Test func theUnreleasedAlbumIsOnTheCalendarOnItsReleaseDate() throws {
    let album = try #require(DemoLidarrFixtures.albums()[1]?.first { $0.id == 12 })
    let entry = try #require(DemoLidarrFixtures.calendar().first { $0.id == album.id })

    #expect(entry.date == album.releaseDate)
  }

  @Test func theTrackListShowsSomeOnDiskAndSomeMissing() async throws {
    let (lidarr, _, _) = makeLidarr()

    let tracks = try await lidarr.tracks(albumID: 11)

    #expect(tracks.count == 10)
    #expect(tracks.filter({ $0.hasFile }).count == 5)
  }

  // MARK: - Lidarr's mutations, which have to be visible

  @Test func addingAnArtistPutsItInTheLibraryInDemoMode() async throws {
    let (lidarr, _, _) = makeLidarr()
    let lookup = try #require(try await lidarr.lookup(term: "Coastal").first)

    let added = try await lidarr.add(
      LidarrAddArtistRequest(
        lookup: lookup, qualityProfileID: 1, metadataProfileID: 2,
        rootFolderPath: "/data/media/music", isMonitored: true,
        searchForMissingAlbums: false, tagIDs: []))

    let artists = try await lidarr.artists()
    #expect(artists.contains(where: { $0.id == added.id && $0.name == lookup.name }))
    // A just-added artist has nothing on disk yet; claiming otherwise would
    // make the demo's progress rows lie.
    #expect(added.statistics?.trackFileCount == 0)
  }

  @Test func lookupMarksAnArtistAlreadyInTheLibrary() async throws {
    let (lidarr, _, _) = makeLidarr()

    let results = try await lidarr.lookup(term: "Wandering")

    let existing = try #require(results.first)
    #expect(existing.existingArtistID == 1)
  }

  @Test func editingAnArtistSticksInDemoMode() async throws {
    let (lidarr, _, _) = makeLidarr()
    let artist = try await lidarr.artist(id: 1)
    var edit = LidarrArtistEdit(artist: artist)
    edit.isMonitored = false
    edit.qualityProfileID = 2
    edit.metadataProfileID = 1
    edit.tagIDs = [1]

    _ = try await lidarr.update(artist, with: edit)

    let reread = try await lidarr.artist(id: 1)
    #expect(reread.isMonitored == false)
    #expect(reread.qualityProfileID == 2)
    #expect(reread.metadataProfileID == 1)
    #expect(reread.tagIDs == [1])
  }

  @Test func deletingAnArtistRemovesItInDemoMode() async throws {
    let (lidarr, _, _) = makeLidarr()

    try await lidarr.delete(id: 3, deleteFiles: true, addImportExclusion: false)

    let artists = try await lidarr.artists()
    #expect(!artists.contains(where: { $0.id == 3 }))
    await #expect(throws: AppError.self) { try await lidarr.artist(id: 3) }
  }

  @Test func unmonitoringAnAlbumSticksInDemoMode() async throws {
    let (lidarr, _, _) = makeLidarr()

    try await lidarr.setAlbumMonitored(false, albumIDs: [10, 11])

    let albums = try await lidarr.albums(artistID: 1)
    #expect(albums.filter({ [10, 11].contains($0.id) }).allSatisfy({ !$0.isMonitored }))
    // Untouched albums keep their own state rather than being swept along.
    #expect(albums.first(where: { $0.id == 12 })?.isMonitored == true)
  }

  @Test func grabbingAReleaseShowsUpInLidarrsQueue() async throws {
    let (lidarr, _, _) = makeLidarr()
    let before = try await lidarr.queue().items.count
    let release = try #require(try await lidarr.releases(albumID: 11).first)

    try await lidarr.grab(release)

    let after = try await lidarr.queue()
    #expect(after.items.count == before + 1)
    #expect(after.items.contains(where: { $0.title == release.title }))
  }

  @Test func lidarrSharesTheArrDatasetItsShellExpects() async throws {
    // The shared surface is the point of the shell: an empty queue or history
    // here would make five of Lidarr's sections blank in the demo.
    let (lidarr, _, _) = makeLidarr()

    let queue = try await lidarr.queue()
    let history = try await lidarr.history(page: 1)
    let calendar = try await lidarr.calendar(start: Date(), end: Date())
    let disks = try await lidarr.diskSpace()
    let status = try await lidarr.systemStatus()

    #expect(!queue.items.isEmpty)
    #expect(!history.records.isEmpty)
    #expect(!calendar.isEmpty)
    #expect(!disks.isEmpty)
    #expect(status.appName == "Lidarr")
  }

  // MARK: - Bazarr's dataset

  @Test func theBazarrDemoHasWantedItemsAcrossBothLibraries() async throws {
    let (bazarr, _) = makeBazarr()

    let wanted = try await bazarr.wanted()

    #expect(wanted.contains(where: { $0.seriesID != nil }))
    #expect(wanted.contains(where: { $0.radarrID != nil }))
    // One row missing two languages — the case a single download must not clear.
    #expect(wanted.contains(where: { $0.missing.count > 1 }))
    // Hearing-impaired and forced variants, because they are separate files.
    let languages = wanted.flatMap(\.missing)
    #expect(languages.contains(where: { $0.isHearingImpaired }))
    #expect(languages.contains(where: { $0.isForced }))
  }

  @Test func everyWantedSubtitleIsForMediaOnDiskUnderItsLibraryTitle() throws {
    // Bazarr only wants subtitles for a file it can see, and the demo Sonarr
    // and Radarr are where a reviewer checks.
    let episodes = DemoArrFixtures.episodes()
    let movies = DemoArrFixtures.movies()

    for item in DemoBazarrFixtures.wanted() {
      if let episodeID = item.episodeID {
        let episode = try #require(episodes.first { $0.id == episodeID })
        #expect(episode.hasFile, "\(item.title) \(item.subtitle ?? "")")
        #expect(item.subtitle?.hasSuffix(" · \(episode.title)") == true, "\(item.subtitle ?? "")")
      } else {
        let movie = try #require(movies.first { $0.id == item.radarrID })
        #expect(movie.hasFile, "\(item.title)")
        #expect(movie.title == item.title)
      }
    }
  }

  @Test func everyBazarrLibraryItemIsInSonarrOrRadarrUnderTheSameTitle() {
    // Bazarr syncs its film library from Radarr's films with a file.
    let series = DemoArrFixtures.series()
    let movies = DemoArrFixtures.movies()

    for item in DemoBazarrFixtures.seriesShells {
      #expect(
        series.contains { $0.id == item.serviceID && $0.title == item.title }, "\(item.title)")
    }
    for item in DemoBazarrFixtures.movieShells {
      #expect(
        movies.contains { $0.id == item.serviceID && $0.title == item.title && $0.hasFile },
        "\(item.title)")
    }
  }

  @Test func theProviderListHasSomethingFailing() async throws {
    let (bazarr, _) = makeBazarr()

    let providers = try await bazarr.providers()

    #expect(providers.contains(where: { $0.status == .healthy }))
    #expect(providers.contains(where: { $0.status == .failing }))
  }

  @Test func candidatesSpanAllThreeConfidenceBands() async throws {
    let (bazarr, _) = makeBazarr()
    let item = try #require(try await bazarr.wanted().first)

    let candidates = try await bazarr.candidates(for: item)

    #expect(candidates.contains(where: { $0.confidence == .high }))
    #expect(candidates.contains(where: { $0.confidence == .medium }))
    #expect(candidates.contains(where: { $0.confidence == .low }))
    // At least one matching the release file, so the "in sync" badge shows.
    #expect(candidates.contains(where: { $0.matchedBy.contains("release_group") }))
    // One set per wanted language, not one set overall.
    #expect(candidates.filter({ $0.language.isHearingImpaired }).isEmpty == false)
  }

  // MARK: - Bazarr's mutations

  @Test func downloadingASubtitleClearsOneLanguageInDemoMode() async throws {
    let (bazarr, _) = makeBazarr()
    // The two-language row: downloading English must leave English (HI) wanted.
    let item = try #require(try await bazarr.wanted().first(where: { $0.missing.count == 2 }))
    let candidate = try #require(
      try await bazarr.candidates(for: item)
        .first(where: { !$0.language.isHearingImpaired }))

    try await bazarr.download(candidate, for: item)

    let wanted = try await bazarr.wanted()
    let row = try #require(wanted.first(where: { $0.id == item.id }))
    #expect(row.missing.count == 1)
    #expect(row.missing.allSatisfy({ $0.isHearingImpaired }))
  }

  @Test func satisfyingTheLastLanguageDropsTheRowInDemoMode() async throws {
    let (bazarr, _) = makeBazarr()
    let item = try #require(try await bazarr.wanted().first(where: { $0.missing.count == 1 }))
    let language = try #require(item.missing.first)

    try await bazarr.downloadBest(language, for: item)

    let wanted = try await bazarr.wanted()
    #expect(!wanted.contains(where: { $0.id == item.id }))
  }

  @Test func aDownloadShowsUpInBazarrsHistoryInDemoMode() async throws {
    let (bazarr, _) = makeBazarr()
    let before = try await bazarr.history().count
    let item = try #require(try await bazarr.wanted().first)
    let language = try #require(item.missing.first)

    try await bazarr.downloadBest(language, for: item)

    let history = try await bazarr.history()
    #expect(history.count == before + 1)
    let newest = try #require(history.first)
    #expect(newest.title == item.title)
    #expect(newest.language?.code == language.code)
  }

  @Test func theLibraryCountsFollowTheWantedList() async throws {
    let (bazarr, _) = makeBazarr()
    let before = try await bazarr.series().first { $0.serviceID == 1 }
    let missingBefore = try #require(before?.missingCount)
    let item = try #require(
      try await bazarr.wanted().first(where: { $0.seriesID == 1 && $0.missing.count == 1 }))
    let language = try #require(item.missing.first)

    try await bazarr.downloadBest(language, for: item)

    let after = try await bazarr.series().first { $0.serviceID == 1 }
    #expect(after?.missingCount == missingBefore - 1)
  }

  @Test func theMovieLibraryIsSeparateFromTheSeriesOne() async throws {
    let (bazarr, _) = makeBazarr()

    let series = try await bazarr.series()
    let movies = try await bazarr.movies()

    #expect(series.allSatisfy({ $0.isSeries }))
    #expect(movies.allSatisfy({ !$0.isSeries }))
    #expect(!series.isEmpty)
    #expect(!movies.isEmpty)
  }

  // MARK: - Wiring

  @Test func theDemoEnvironmentServesLidarrAndBazarr() async throws {
    let environment = AppEnvironment.demo

    for kind in [ServiceKind.lidarr, .bazarr] {
      let instance = try #require(DemoServices.instances.first { $0.kind == kind })
      #expect(environment.makeServiceRepository(instance) != nil)
    }
  }
}
