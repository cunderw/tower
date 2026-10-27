import Foundation
import Testing
import TowerCore
import TowerData

@testable import Tower

/// The Lidarr library's three levels, its filters, and the add flow.
@MainActor
@Suite
struct LidarrLibraryStoreTests {
  private func artist(
    id: Int, name: String, monitored: Bool = true, albums: Int = 2, files: Int = 10,
    tracked: Int = 10, total: Int = 12, size: Int64 = 1_000,
    added: Date = Date(timeIntervalSince1970: 1_700_000_000), genres: [String] = []
  ) -> LidarrArtist {
    LidarrArtist(
      id: id, name: name, sortName: name.lowercased(), foreignArtistID: "mb-\(id)",
      overview: nil, artistType: "Group", disambiguation: nil, status: .continuing,
      isMonitored: monitored, qualityProfileID: 1, metadataProfileID: 2, path: nil,
      rootFolderPath: "/music", genres: genres, tagIDs: [], added: added, posterURL: nil,
      statistics: LidarrArtistStatistics(
        albumCount: albums, trackFileCount: files, trackCount: tracked,
        totalTrackCount: total, sizeOnDiskBytes: size))
  }

  private func album(
    id: Int, artistID: Int, title: String, monitored: Bool = true, files: Int = 10,
    tracks: Int = 10, released: Date? = Date(timeIntervalSince1970: 1_600_000_000)
  ) -> LidarrAlbum {
    LidarrAlbum(
      id: id, artistID: artistID, title: title, disambiguation: nil, overview: nil,
      albumType: "Album", secondaryTypes: [], releaseDate: released, isMonitored: monitored,
      durationMilliseconds: 2_400_000, genres: [], coverURL: nil,
      statistics: LidarrAlbumStatistics(
        trackFileCount: files, trackCount: tracks, totalTrackCount: tracks,
        sizeOnDiskBytes: 100))
  }

  private func makeStore(
    _ artists: [LidarrArtist], albums: [Int: [LidarrAlbum]] = [:],
    tracks: [Int: [LidarrTrack]] = [:], failing: Bool = false
  ) async -> (LidarrLibraryStore, StubLidarrRepository) {
    let repository = StubLidarrRepository(
      artists: artists, albums: albums, tracks: tracks, failing: failing)
    let store = LidarrLibraryStore(repository: repository)
    await store.load()
    return (store, repository)
  }

  // MARK: - Library

  @Test func searchMatchesNameAndGenre() async {
    let (store, _) = await makeStore([
      artist(id: 1, name: "Alpha"),
      artist(id: 2, name: "Beta", genres: ["Ambient"]),
    ])

    store.searchText = "ambient"
    #expect(store.filteredArtists.map(\.id) == [2])

    store.searchText = "alph"
    #expect(store.filteredArtists.map(\.id) == [1])
  }

  @Test func sortingByNameUsesLidarrsOwnSortName() async {
    // So "The Wandering Signal" files under W, matching the service.
    let (store, _) = await makeStore([
      LidarrArtist(
        id: 1, name: "The Wandering Signal", sortName: "wandering signal, the",
        foreignArtistID: nil, overview: nil, artistType: nil, disambiguation: nil,
        status: .continuing, isMonitored: true, qualityProfileID: 1, metadataProfileID: 1,
        path: nil, rootFolderPath: nil, genres: [], tagIDs: [], added: nil, posterURL: nil,
        statistics: nil),
      artist(id: 2, name: "Anvil Choir"),
    ])

    store.sort = .name
    #expect(store.filteredArtists.map(\.id) == [2, 1])
  }

  @Test func theMissingFilterIncludesPartialBecauseThereIsStillSomethingToFind() async {
    let (store, _) = await makeStore([
      artist(id: 1, name: "Complete", files: 10, tracked: 10),
      artist(id: 2, name: "Partial", files: 4, tracked: 10),
      artist(id: 3, name: "Nothing", files: 0, tracked: 10),
    ])

    store.filter = .missing
    #expect(Set(store.filteredArtists.map(\.id)) == [2, 3])

    store.filter = .complete
    #expect(store.filteredArtists.map(\.id) == [1])
  }

  @Test func aMetadataProfileFailureCostsTheLabelNotTheList() async {
    let (store, repository) = await makeStore([artist(id: 1, name: "Alpha")])
    repository.failProfiles = true

    await store.loadMetadataProfiles()

    #expect(store.state.value?.count == 1)
    #expect(store.metadataProfileName(for: store.state.value![0]) == nil)
  }

  // MARK: - Three-level navigation

  @Test func albumsLoadPerArtistAndTracksPerAlbum() async {
    let (store, repository) = await makeStore(
      [artist(id: 1, name: "Alpha")],
      albums: [1: [album(id: 10, artistID: 1, title: "First")]],
      tracks: [
        10: [
          LidarrTrack(
            id: 100, albumID: 10, title: "Opener", trackNumber: "A1",
            absoluteTrackNumber: 1, mediumNumber: 1, durationMilliseconds: 200_000,
            hasFile: true, isExplicit: false)
        ]
      ])

    await store.loadAlbums(artistID: 1)
    #expect(store.albums(for: 1).value?.count == 1)
    #expect(repository.albumCalls == 1)

    await store.loadTracks(albumID: 10)
    #expect(store.tracks(for: 10).value?.count == 1)
    #expect(store.tracks(for: 10).value?.first?.trackNumber == "A1")
  }

  @Test func albumsAndTracksAreNotRefetchedOnEveryVisit() async {
    let (store, repository) = await makeStore(
      [artist(id: 1, name: "Alpha")],
      albums: [1: [album(id: 10, artistID: 1, title: "First")]])

    await store.loadAlbums(artistID: 1)
    await store.loadAlbums(artistID: 1)
    #expect(repository.albumCalls == 1)

    await store.loadAlbums(artistID: 1, force: true)
    #expect(repository.albumCalls == 2)
  }

  @Test func anAlbumLoadFailureIsScopedToThatArtist() async {
    let (store, repository) = await makeStore([
      artist(id: 1, name: "Alpha"), artist(id: 2, name: "Beta"),
    ])
    repository.failAlbums = true

    await store.loadAlbums(artistID: 1)

    guard case .failed = store.albums(for: 1) else {
      Issue.record("expected .failed, got \(store.albums(for: 1))")
      return
    }
    // The library itself is untouched.
    #expect(store.state.value?.count == 2)
  }

  // MARK: - Monitor toggles at both upper levels

  @Test func togglingAnArtistUpdatesItsRow() async {
    let (store, repository) = await makeStore([artist(id: 1, name: "Alpha")])

    await store.setArtistMonitored(false, for: store.state.value![0])

    #expect(repository.artistEdits.count == 1)
    #expect(repository.artistEdits[0].isMonitored == false)
    #expect(store.state.value?[0].isMonitored == false)
  }

  @Test func togglingAnAlbumPatchesTheRowWithoutRefetchingTheTracks() async {
    // Unlike Sonarr's season toggle — which Sonarr applies down to its
    // episodes server-side — Lidarr's album flag governs nothing below it that
    // Tower shows, so refetching the tracks would be work with no visible
    // result.
    let (store, repository) = await makeStore(
      [artist(id: 1, name: "Alpha")],
      albums: [1: [album(id: 10, artistID: 1, title: "First")]],
      tracks: [10: []])
    await store.loadAlbums(artistID: 1)
    await store.loadTracks(albumID: 10)
    let trackCallsBefore = repository.trackCalls

    await store.setAlbumMonitored(false, album: store.albums(for: 1).value![0])

    #expect(repository.albumMonitorWrites == [AlbumMonitorWrite(ids: [10], monitored: false)])
    #expect(store.albums(for: 1).value?[0].isMonitored == false)
    #expect(repository.trackCalls == trackCallsBefore, "the track list was refetched")
  }

  @Test func aFailedAlbumToggleKeepsTheLibraryAndSaysWhy() async {
    let (store, repository) = await makeStore(
      [artist(id: 1, name: "Alpha")],
      albums: [1: [album(id: 10, artistID: 1, title: "First")]])
    await store.loadAlbums(artistID: 1)
    repository.failWrites = true

    await store.setAlbumMonitored(false, album: store.albums(for: 1).value![0])

    guard case .actionFailed(let artists, _) = store.state else {
      Issue.record("expected .actionFailed, got \(store.state)")
      return
    }
    #expect(artists.count == 1)
    #expect(store.albums(for: 1).value?[0].isMonitored == true, "the row flipped anyway")
  }

  // MARK: - Delete and search

  @Test func deletingRemovesTheArtist() async {
    let (store, repository) = await makeStore([
      artist(id: 1, name: "Alpha"), artist(id: 2, name: "Beta"),
    ])

    await store.delete(store.state.value![0], deleteFiles: true)

    #expect(repository.deletes.count == 1)
    #expect(repository.deletes[0].deleteFiles == true)
    #expect(store.state.value?.map(\.id) == [2])
  }

  @Test func searchRunsAtBothLevels() async {
    let (store, repository) = await makeStore(
      [artist(id: 1, name: "Alpha")],
      albums: [1: [album(id: 10, artistID: 1, title: "First")]])
    await store.loadAlbums(artistID: 1)

    await store.runAutomaticSearch(artist: store.state.value![0])
    #expect(repository.artistSearches == [1])

    await store.runAutomaticSearch(album: store.albums(for: 1).value![0])
    #expect(repository.albumSearches == [10])
    #expect(store.lastActionSuccess == 2)
    #expect(store.lastActionFailure == 0)
  }

  @Test func aFailedActionAtEitherLevelCountsAsAFailureNotASuccess() async {
    // The artist and album screens' haptics are driven by these counters.
    let (store, repository) = await makeStore(
      [artist(id: 1, name: "Alpha")],
      albums: [1: [album(id: 10, artistID: 1, title: "First")]])
    await store.loadAlbums(artistID: 1)
    #expect(store.lastActionSuccess == 0, "a load counted as an action")
    repository.failWrites = true

    await store.runAutomaticSearch(artist: store.state.value![0])
    await store.runAutomaticSearch(album: store.albums(for: 1).value![0])
    await store.setArtistMonitored(false, for: store.state.value![0])
    await store.setAlbumMonitored(false, album: store.albums(for: 1).value![0])

    #expect(store.lastActionSuccess == 0, "a failed action counted as a success")
    #expect(store.lastActionFailure == 4)
  }
}

struct AlbumMonitorWrite: Equatable, Sendable {
  let ids: [Int]
  let monitored: Bool
}

// MARK: - The add flow

@MainActor
@Suite
struct LidarrAddStoreTests {
  private func hit(id: String, name: String, existing: Int? = nil) -> LidarrArtistLookup {
    LidarrArtistLookup(
      foreignArtistID: id, name: name, overview: nil, artistType: "Group",
      disambiguation: nil, posterURL: nil, existingArtistID: existing)
  }

  private func makeStore(
    _ hits: [LidarrArtistLookup]
  ) async -> (LidarrAddStore, StubLidarrRepository, LidarrLibraryStore) {
    let repository = StubLidarrRepository(artists: [], albums: [:], tracks: [:], failing: false)
    repository.lookupHits = hits
    let library = LidarrLibraryStore(repository: repository)
    await library.load()
    let add = LidarrAddStore(library: library)
    await add.loadPickers()
    return (add, repository, library)
  }

  @Test func addIsDisabledUntilThePickersHaveAnswered() async {
    let repository = StubLidarrRepository(artists: [], albums: [:], tracks: [:], failing: false)
    repository.lookupHits = [hit(id: "mb-1", name: "Alpha")]
    repository.failProfiles = true
    let library = LidarrLibraryStore(repository: repository)
    await library.load()
    let add = LidarrAddStore(library: library)
    await add.loadPickers()

    add.searchText = "alpha"
    await add.search()
    add.select(add.state.value![0])

    // The defaults come from the service, so there is nothing to add yet.
    #expect(!add.canSubmit)
  }

  @Test func thePickersDefaultToTheFirstLiveValue() async {
    let (add, _, _) = await makeStore([hit(id: "mb-1", name: "Alpha")])

    #expect(add.qualityProfileID == 1)
    // Lidarr's second axis, which Radarr and Sonarr don't have.
    #expect(add.metadataProfileID == 2)
    #expect(add.rootFolderPath == "/music")
  }

  @Test func anArtistAlreadyInTheLibraryCannotBeSelected() async {
    // Adding a duplicate is rejected by Lidarr and reads as the app being
    // broken.
    let (add, _, _) = await makeStore([hit(id: "mb-1", name: "Alpha", existing: 7)])
    add.searchText = "alpha"
    await add.search()

    add.select(add.state.value![0])

    #expect(add.selected == nil)
  }

  @Test func addingSendsBothProfilesAndTheMonitorOption() async {
    // Without a monitor option Lidarr files an artist whose entire discography
    // is ignored, which looks like the add silently failing.
    let (add, repository, _) = await makeStore([hit(id: "mb-1", name: "Alpha")])
    add.searchText = "alpha"
    await add.search()
    add.select(add.state.value![0])
    add.monitorOption = .future
    add.searchOnAdd = false

    #expect(await add.submit())

    let request = try! #require(repository.adds.last)
    #expect(request.qualityProfileID == 1)
    #expect(request.metadataProfileID == 2)
    #expect(request.rootFolderPath == "/music")
    #expect(request.monitorOption == .future)
    #expect(!request.searchForMissingAlbums)
  }

  @Test func aSuccessfulAddPutsTheArtistInTheLibraryBehindTheSheet() async {
    let (add, _, library) = await makeStore([hit(id: "mb-1", name: "Alpha")])
    add.searchText = "alpha"
    await add.search()
    add.select(add.state.value![0])
    #expect(library.state.value?.isEmpty == true)

    #expect(await add.submit())

    #expect(library.state.value?.count == 1, "the added artist never reached the library")
    #expect(library.state.value?.first?.name == "Alpha")
  }

  @Test func aRejectedAddKeepsTheSheetAndTheSelection() async {
    let (add, repository, _) = await makeStore([hit(id: "mb-1", name: "Alpha")])
    add.searchText = "alpha"
    await add.search()
    add.select(add.state.value![0])
    repository.failWrites = true

    #expect(await add.submit() == false)

    #expect(add.addError != nil)
    #expect(add.selected != nil, "the selection was lost on a rejected add")
  }

  @Test func anEmptySearchIsNotARequest() async {
    let (add, repository, _) = await makeStore([hit(id: "mb-1", name: "Alpha")])
    add.searchText = "   "

    await add.search()

    #expect(repository.lookups.isEmpty)
    #expect(!add.canSearch)
  }
}

// MARK: - Stub

final class StubLidarrRepository: LidarrRepositoryProtocol, @unchecked Sendable {
  let instance = ServiceInstance(
    kind: .lidarr, name: "Lidarr", baseURL: URL(string: "http://192.0.2.1:8686")!,
    credentials: .apiKey("k"))
  var arr: ArrClientCore { ArrClientCore(client: ServiceHTTPClient(instance: instance)) }

  private let lock = NSLock()
  private var storedArtists: [LidarrArtist]
  private var storedAlbums: [Int: [LidarrAlbum]]
  private let storedTracks: [Int: [LidarrTrack]]
  private let failing: Bool

  var lookupHits: [LidarrArtistLookup] = []
  var failWrites = false
  var failAlbums = false
  var failProfiles = false

  private(set) var albumCalls = 0
  private(set) var trackCalls = 0
  private(set) var lookups: [String] = []
  private(set) var adds: [LidarrAddArtistRequest] = []
  private(set) var artistEdits: [LidarrArtistEdit] = []
  private(set) var albumMonitorWrites: [AlbumMonitorWrite] = []
  private(set) var deletes: [(id: Int, deleteFiles: Bool)] = []
  private(set) var artistSearches: [Int] = []
  private(set) var albumSearches: [Int] = []

  init(
    artists: [LidarrArtist], albums: [Int: [LidarrAlbum]], tracks: [Int: [LidarrTrack]],
    failing: Bool
  ) {
    self.storedArtists = artists
    self.storedAlbums = albums
    self.storedTracks = tracks
    self.failing = failing
  }

  func artists() async throws -> [LidarrArtist] {
    if failing { throw AppError.serverUnreachable }
    return lock.withLock { storedArtists }
  }

  func artist(id: Int) async throws -> LidarrArtist {
    guard let match = lock.withLock({ storedArtists.first { $0.id == id } }) else {
      throw AppError.unknown("missing")
    }
    return match
  }

  func albums(artistID: Int) async throws -> [LidarrAlbum] {
    if failAlbums { throw AppError.serverUnreachable }
    return lock.withLock {
      albumCalls += 1
      return storedAlbums[artistID] ?? []
    }
  }

  func tracks(albumID: Int) async throws -> [LidarrTrack] {
    lock.withLock {
      trackCalls += 1
      return storedTracks[albumID] ?? []
    }
  }

  func lookup(term: String) async throws -> [LidarrArtistLookup] {
    lock.withLock {
      lookups.append(term)
      return lookupHits
    }
  }

  @discardableResult
  func add(_ request: LidarrAddArtistRequest) async throws -> LidarrArtist {
    if failWrites { throw AppError.actionRefused("Root folder is not writable.") }
    return lock.withLock {
      adds.append(request)
      let added = LidarrArtist(
        id: 99, name: request.lookup.name, sortName: request.lookup.name.lowercased(),
        foreignArtistID: request.lookup.foreignArtistID, overview: nil, artistType: nil,
        disambiguation: nil, status: .continuing, isMonitored: request.isMonitored,
        qualityProfileID: request.qualityProfileID,
        metadataProfileID: request.metadataProfileID, path: nil,
        rootFolderPath: request.rootFolderPath, genres: [], tagIDs: request.tagIDs,
        added: Date(), posterURL: nil, statistics: nil)
      storedArtists.append(added)
      return added
    }
  }

  @discardableResult
  func update(_ artist: LidarrArtist, with edit: LidarrArtistEdit) async throws -> LidarrArtist {
    if failWrites { throw AppError.serverUnreachable }
    return lock.withLock {
      artistEdits.append(edit)
      let updated = LidarrArtist(
        id: artist.id, name: artist.name, sortName: artist.sortName,
        foreignArtistID: artist.foreignArtistID, overview: artist.overview,
        artistType: artist.artistType, disambiguation: artist.disambiguation,
        status: artist.status, isMonitored: edit.isMonitored,
        qualityProfileID: edit.qualityProfileID, metadataProfileID: edit.metadataProfileID,
        path: artist.path, rootFolderPath: edit.rootFolderPath, genres: artist.genres,
        tagIDs: edit.tagIDs, added: artist.added, posterURL: artist.posterURL,
        statistics: artist.statistics)
      storedArtists = storedArtists.map { $0.id == updated.id ? updated : $0 }
      return updated
    }
  }

  func delete(id: Int, deleteFiles: Bool, addImportExclusion: Bool) async throws {
    if failWrites { throw AppError.serverUnreachable }
    lock.withLock {
      deletes.append((id, deleteFiles))
      storedArtists.removeAll { $0.id == id }
    }
  }

  func setAlbumMonitored(_ isMonitored: Bool, albumIDs: [Int]) async throws {
    if failWrites { throw AppError.serverUnreachable }
    lock.withLock {
      albumMonitorWrites.append(AlbumMonitorWrite(ids: albumIDs, monitored: isMonitored))
    }
  }

  func metadataProfiles() async throws -> [LidarrMetadataProfile] {
    if failProfiles { throw AppError.serverUnreachable }
    return [LidarrMetadataProfile(id: 2, name: "Everything")]
  }

  func qualityProfiles() async throws -> [ArrQualityProfile] {
    if failProfiles { throw AppError.serverUnreachable }
    return [ArrQualityProfile(id: 1, name: "Lossless")]
  }

  func rootFolders() async throws -> [ArrRootFolder] {
    if failProfiles { throw AppError.serverUnreachable }
    return [ArrRootFolder(id: 1, path: "/music", isAccessible: true, freeBytes: 1_000)]
  }

  func tags() async throws -> [ArrTag] { [] }

  func releases(artistID: Int) async throws -> [ArrRelease] { [] }
  func releases(albumID: Int) async throws -> [ArrRelease] { [] }
  func grab(_ release: ArrRelease) async throws {}

  func searchArtist(id: Int) async throws {
    if failWrites { throw AppError.serverUnreachable }
    lock.withLock { artistSearches.append(id) }
  }

  func searchAlbum(id: Int) async throws {
    if failWrites { throw AppError.serverUnreachable }
    lock.withLock { albumSearches.append(id) }
  }

  // The shared surface, unused by these tests but required by the protocol.
  func queue() async throws -> ArrQueuePage {
    ArrQueuePage(items: [], page: 1, pageSize: 50, totalRecords: 0)
  }
  func removeQueueItem(id: Int, removeFromClient: Bool, blocklist: Bool) async throws {}
  func calendar(start: Date, end: Date) async throws -> [ArrCalendarEntry] { [] }
  func history(page: Int) async throws -> ArrHistoryPage {
    ArrHistoryPage(records: [], page: 1, pageSize: 50, totalRecords: 0)
  }
  func health() async throws -> [ArrHealthCheck] { [] }
  func diskSpace() async throws -> [ArrDiskSpace] { [] }
  func systemStatus() async throws -> ArrSystemStatus {
    ArrSystemStatus(
      appName: "Lidarr", instanceName: nil, version: "2.1.0", osName: nil, osVersion: nil,
      isDocker: false, startTime: nil)
  }
  @discardableResult
  func runCommand(_ name: String) async throws -> ArrCommand {
    ArrCommand(id: 1, name: name, status: .queued, message: nil, started: nil, ended: nil)
  }
}
