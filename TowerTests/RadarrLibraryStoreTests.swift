import Foundation
import Testing
import TowerCore
import TowerData
@testable import Tower

/// Search, sort, filter, and the two actions — driven without SwiftUI.
@MainActor
@Suite
struct RadarrLibraryStoreTests {
  private func movie(
    id: Int, title: String, year: Int? = 2020, hasFile: Bool = true, size: Int64 = 0,
    available: Bool = true, monitored: Bool = true, studio: String? = nil,
    added: Date = Date(timeIntervalSince1970: 1_700_000_000)
  ) -> RadarrMovie {
    RadarrMovie(
      id: id, tmdbID: id, imdbID: nil, title: title, sortTitle: title.lowercased(), year: year,
      overview: nil, studio: studio, runtimeMinutes: nil, certification: nil, genres: [],
      status: available ? .released : .announced, minimumAvailability: .released,
      isMonitored: monitored, hasFile: hasFile, isAvailable: available, sizeOnDiskBytes: size,
      qualityProfileID: 1, path: nil, rootFolderPath: nil, tagIDs: [], added: added,
      inCinemas: nil, digitalRelease: nil, physicalRelease: nil, posterURL: nil,
      fanartURL: nil, file: nil)
  }

  private func makeStore(_ movies: [RadarrMovie], failing: Bool = false) async -> RadarrLibraryStore {
    let store = RadarrLibraryStore(
      repository: StubRadarrRepository(movies: movies, failing: failing))
    await store.load()
    return store
  }

  // MARK: - Search

  @Test func searchMatchesTitleAndStudio() async {
    // Studio as well as title: it's on the row, and it's how someone finds
    // "that A24 one" whose name they can't remember.
    let store = await makeStore([
      movie(id: 1, title: "Alpha"),
      movie(id: 2, title: "Beta", studio: "Example Pictures"),
    ])

    store.searchText = "example"
    #expect(store.filteredMovies.map(\.id) == [2])

    store.searchText = "alph"
    #expect(store.filteredMovies.map(\.id) == [1])
  }

  @Test func anEmptySearchReturnsEverything() async {
    let store = await makeStore([movie(id: 1, title: "Alpha"), movie(id: 2, title: "Beta")])
    store.searchText = "   "
    #expect(store.filteredMovies.count == 2)
  }

  // MARK: - Sort

  @Test func sortingByTitleUsesRadarrsSortTitle() async {
    let store = await makeStore([
      movie(id: 1, title: "The Zebra"),
      movie(id: 2, title: "Apple"),
    ])
    store.sort = .title
    #expect(store.filteredMovies.map(\.id) == [2, 1])
  }

  @Test func sortingByYearPutsNewestFirstAndUnknownYearsLast() async {
    // A film with no year is not the newest thing in the library.
    let store = await makeStore([
      movie(id: 1, title: "Old", year: 1999),
      movie(id: 2, title: "New", year: 2025),
      movie(id: 3, title: "Undated", year: nil),
    ])
    store.sort = .year
    #expect(store.filteredMovies.map(\.id) == [2, 1, 3])
  }

  @Test func sortingBySizeAndByAdded() async {
    let store = await makeStore([
      movie(id: 1, title: "Small", size: 1_000, added: Date(timeIntervalSince1970: 100)),
      movie(id: 2, title: "Huge", size: 90_000_000_000, added: Date(timeIntervalSince1970: 50)),
      movie(id: 3, title: "Newest", size: 5_000, added: Date(timeIntervalSince1970: 900)),
    ])

    store.sort = .size
    #expect(store.filteredMovies.first?.id == 2)

    store.sort = .added
    #expect(store.filteredMovies.first?.id == 3)
  }

  // MARK: - Filter

  @Test func theMissingFilterExcludesUnreleasedFilms() async {
    // The distinction the whole `libraryState` split exists for: an unreleased
    // film is not missing, and listing it sends someone searching for something
    // that doesn't exist yet.
    let store = await makeStore([
      movie(id: 1, title: "Downloaded", hasFile: true),
      movie(id: 2, title: "Missing", hasFile: false, available: true),
      movie(id: 3, title: "Unreleased", hasFile: false, available: false),
    ])

    store.filter = .missing
    #expect(store.filteredMovies.map(\.id) == [2])

    store.filter = .downloaded
    #expect(store.filteredMovies.map(\.id) == [1])
  }

  @Test func theMonitoredFilterKeepsOnlyMonitoredFilms() async {
    let store = await makeStore([
      movie(id: 1, title: "Watched", monitored: true),
      movie(id: 2, title: "Ignored", monitored: false),
    ])
    store.filter = .monitored
    #expect(store.filteredMovies.map(\.id) == [1])
  }

  @Test func searchAndFilterCompose() async {
    let store = await makeStore([
      movie(id: 1, title: "Alpha Missing", hasFile: false, available: true),
      movie(id: 2, title: "Alpha Downloaded", hasFile: true),
      movie(id: 3, title: "Beta Missing", hasFile: false, available: true),
    ])
    store.searchText = "alpha"
    store.filter = .missing
    #expect(store.filteredMovies.map(\.id) == [1])
  }

  @Test func anEmptyResultKnowsWhetherTheFilterCausedIt() async {
    // Three empty states, and the screen has to tell them apart: an empty
    // library, a filter that matched nothing, and a search that matched nothing.
    let store = await makeStore([movie(id: 1, title: "Downloaded", hasFile: true)])

    store.filter = .missing
    #expect(store.filteredMovies.isEmpty)
    #expect(store.isFilteredToNothing)

    store.filter = .all
    store.searchText = "nothing matches this"
    #expect(store.filteredMovies.isEmpty)
    #expect(!store.isFilteredToNothing, "a search miss is not a filter miss")
  }

  // MARK: - Actions

  @Test func deletingDropsTheRowWithoutRefetching() async {
    let store = await makeStore([movie(id: 1, title: "Alpha"), movie(id: 2, title: "Beta")])

    await store.delete(store.state.value![0], deleteFiles: true)

    #expect(store.state.value?.map(\.id) == [2])
  }

  @Test func aFailedDeleteKeepsTheLibraryAndSurfacesTheError() async {
    // The rule every Unraid list follows: an action failing must not cost the user
    // the list they were looking at.
    let store = await makeStore(
      [movie(id: 1, title: "Alpha"), movie(id: 2, title: "Beta")], failing: true)

    await store.delete(store.state.value![0], deleteFiles: false)

    #expect(store.state.value?.count == 2, "the library was lost to a failed delete")
    guard case .actionFailed(_, let error) = store.state else {
      Issue.record("expected .actionFailed, got \(store.state)")
      return
    }
    #expect(error == .serverUnreachable)
  }

  @Test func togglingMonitorReplacesOnlyThatRow() async {
    let store = await makeStore([
      movie(id: 1, title: "Alpha", monitored: true),
      movie(id: 2, title: "Beta", monitored: true),
    ])

    await store.setMonitored(false, for: store.state.value![0])

    #expect(store.state.value?.first { $0.id == 1 }?.isMonitored == false)
    #expect(store.state.value?.first { $0.id == 2 }?.isMonitored == true)
  }

  // MARK: - Action outcomes

  @Test func actionsThatLandCountAsSuccessesAndALoadDoesNot() async {
    // The detail screen's haptics are driven by these counters, and a
    // background fetch must never buzz.
    let store = await makeStore([movie(id: 1, title: "Alpha"), movie(id: 2, title: "Beta")])
    await store.refresh()
    #expect(store.lastActionSuccess == 0)

    await store.runAutomaticSearch(for: store.state.value![0])
    await store.setMonitored(false, for: store.state.value![0])
    await store.delete(store.state.value![1], deleteFiles: false)

    #expect(store.lastActionSuccess == 3)
    #expect(store.lastActionFailure == 0)
  }

  @Test func aFailedSearchCountsAsAFailureNotASuccess() async {
    // A failed search must not fire the success haptic.
    let store = await makeStore([movie(id: 1, title: "Alpha")], failing: true)

    await store.runAutomaticSearch(for: store.state.value![0])

    #expect(store.lastActionSuccess == 0, "a failed search counted as a success")
    #expect(store.lastActionFailure == 1)
    guard case .actionFailed(let movies, _) = store.state else {
      Issue.record("expected .actionFailed, got \(store.state)")
      return
    }
    #expect(movies.count == 1)
  }

  @Test func aFailedToggleAndAFailedDeleteCountAsFailures() async {
    let store = await makeStore([movie(id: 1, title: "Alpha")], failing: true)

    await store.setMonitored(false, for: store.state.value![0])
    await store.delete(store.state.value![0], deleteFiles: false)

    #expect(store.lastActionSuccess == 0)
    #expect(store.lastActionFailure == 2)
  }
}

/// The smallest repository that can answer the library screen. Mutations are
/// in-memory; nothing here is a network call.
private final class StubRadarrRepository: RadarrRepositoryProtocol, @unchecked Sendable {
  let instance = ServiceInstance(
    kind: .radarr, name: "Radarr", baseURL: URL(string: "http://192.0.2.1:7878")!,
    credentials: .apiKey("k"))
  var arr: ArrClientCore { ArrClientCore(client: ServiceHTTPClient(instance: instance)) }

  private let lock = NSLock()
  private var movies: [RadarrMovie]
  private let failing: Bool

  init(movies: [RadarrMovie], failing: Bool) {
    self.movies = movies
    self.failing = failing
  }

  func movies() async throws -> [RadarrMovie] { lock.withLock { movies } }

  func movie(id: Int) async throws -> RadarrMovie {
    guard let match = lock.withLock({ movies.first { $0.id == id } }) else {
      throw AppError.unknown("missing")
    }
    return match
  }

  func lookup(term: String) async throws -> [RadarrMovieLookup] { [] }

  func add(_ request: RadarrAddMovieRequest) async throws -> RadarrMovie {
    if failing { throw AppError.serverUnreachable }
    return lock.withLock {
      let added = RadarrMovie(
        id: 999, tmdbID: request.lookup.tmdbID, imdbID: nil, title: request.lookup.title,
        sortTitle: request.lookup.title.lowercased(), year: request.lookup.year, overview: nil,
        studio: nil, runtimeMinutes: nil, certification: nil, genres: [], status: .released,
        minimumAvailability: request.minimumAvailability, isMonitored: request.isMonitored,
        hasFile: false, isAvailable: true, sizeOnDiskBytes: 0,
        qualityProfileID: request.qualityProfileID, path: nil,
        rootFolderPath: request.rootFolderPath, tagIDs: request.tagIDs, added: nil,
        inCinemas: nil, digitalRelease: nil, physicalRelease: nil, posterURL: nil,
        fanartURL: nil, file: nil)
      movies.append(added)
      return added
    }
  }

  func update(_ movie: RadarrMovie, with edit: RadarrMovieEdit) async throws -> RadarrMovie {
    if failing { throw AppError.serverUnreachable }
    return lock.withLock {
      let updated = RadarrMovie(
        id: movie.id, tmdbID: movie.tmdbID, imdbID: movie.imdbID, title: movie.title,
        sortTitle: movie.sortTitle, year: movie.year, overview: movie.overview,
        studio: movie.studio, runtimeMinutes: movie.runtimeMinutes,
        certification: movie.certification, genres: movie.genres, status: movie.status,
        minimumAvailability: edit.minimumAvailability, isMonitored: edit.isMonitored,
        hasFile: movie.hasFile, isAvailable: movie.isAvailable,
        sizeOnDiskBytes: movie.sizeOnDiskBytes, qualityProfileID: edit.qualityProfileID,
        path: movie.path, rootFolderPath: movie.rootFolderPath, tagIDs: edit.tagIDs,
        added: movie.added, inCinemas: movie.inCinemas, digitalRelease: movie.digitalRelease,
        physicalRelease: movie.physicalRelease, posterURL: movie.posterURL,
        fanartURL: movie.fanartURL, file: movie.file)
      if let index = movies.firstIndex(where: { $0.id == movie.id }) { movies[index] = updated }
      return updated
    }
  }

  func delete(id: Int, deleteFiles: Bool, addImportExclusion: Bool) async throws {
    if failing { throw AppError.serverUnreachable }
    lock.withLock { movies.removeAll { $0.id == id } }
  }

  func releases(movieID: Int) async throws -> [ArrRelease] { [] }
  func grab(_ release: ArrRelease) async throws {}
  func search(movieID: Int) async throws {
    if failing { throw AppError.serverUnreachable }
  }
}

/// The edit and add stores.
@MainActor
@Suite
struct RadarrEditAndAddTests {
  private func movie(id: Int, monitored: Bool = true, profile: Int = 1) -> RadarrMovie {
    RadarrMovie(
      id: id, tmdbID: id, imdbID: nil, title: "Film \(id)", sortTitle: "film \(id)", year: 2020,
      overview: nil, studio: nil, runtimeMinutes: nil, certification: nil, genres: [],
      status: .released, minimumAvailability: .released, isMonitored: monitored, hasFile: true,
      isAvailable: true, sizeOnDiskBytes: 1, qualityProfileID: profile, path: nil,
      rootFolderPath: "/data/movies", tagIDs: [], added: nil, inCinemas: nil,
      digitalRelease: nil, physicalRelease: nil, posterURL: nil, fanartURL: nil, file: nil)
  }

  private func makeLibrary(_ movies: [RadarrMovie], failing: Bool = false) async -> RadarrLibraryStore {
    let store = RadarrLibraryStore(
      repository: StubRadarrRepository(movies: movies, failing: failing))
    await store.load()
    return store
  }

  @Test func anEditWithNoChangesCannotBeSaved() async {
    // The Save button is bound to this: a sheet that lets you "save" nothing
    // sends a PUT for no reason.
    let library = await makeLibrary([movie(id: 1)])
    let store = RadarrEditStore(movie: library.state.value![0], library: library)
    #expect(!store.hasChanges)

    store.edit.isMonitored = false
    #expect(store.hasChanges)
  }

  @Test func savingAnEditReplacesTheRowInTheLibrary() async {
    let library = await makeLibrary([movie(id: 1, monitored: true), movie(id: 2)])
    let store = RadarrEditStore(movie: library.state.value![0], library: library)
    store.edit.isMonitored = false
    store.edit.qualityProfileID = 7

    let closed = await store.save()

    #expect(closed)
    #expect(library.state.value?.first { $0.id == 1 }?.isMonitored == false)
    #expect(library.state.value?.first { $0.id == 1 }?.qualityProfileID == 7)
    #expect(library.state.value?.first { $0.id == 2 }?.qualityProfileID == 1, "another row changed")
  }

  @Test func aFailedSaveKeepsTheSheetOpenWithTheEditIntact() async {
    // Dismissing on failure loses what the user typed and tells them nothing.
    let library = await makeLibrary([movie(id: 1)], failing: true)
    let store = RadarrEditStore(movie: library.state.value![0], library: library)
    store.edit.isMonitored = false

    let closed = await store.save()

    #expect(!closed)
    #expect(store.saveError == .serverUnreachable)
    #expect(store.edit.isMonitored == false, "the edit was discarded")
    #expect(library.state.value?.first?.isMonitored == true, "the library changed anyway")
  }

  @Test func searchingWithAnEmptyTermAsksNothing() async {
    let library = await makeLibrary([])
    let store = RadarrAddStore(library: library)
    store.searchText = "   "

    await store.search()

    #expect(store.results.value == nil)
  }

  @Test func addingPutsTheNewMovieIntoTheLibraryList() async {
    let library = await makeLibrary([movie(id: 1)])
    let store = RadarrAddStore(library: library)
    let lookup = RadarrMovieLookup(
      tmdbID: 5, title: "Brand New", year: 2026, overview: nil, posterURL: nil,
      studio: nil, runtimeMinutes: nil, existingMovieID: nil)

    let added = await store.add(
      RadarrAddMovieRequest(
        lookup: lookup, qualityProfileID: 1, rootFolderPath: "/data/movies"))

    #expect(added != nil)
    #expect(library.state.value?.contains { $0.title == "Brand New" } == true)
  }

  @Test func aFailedAddLeavesTheLibraryAlone() async {
    let library = await makeLibrary([movie(id: 1)], failing: true)
    let store = RadarrAddStore(library: library)
    let lookup = RadarrMovieLookup(
      tmdbID: 5, title: "Brand New", year: 2026, overview: nil, posterURL: nil,
      studio: nil, runtimeMinutes: nil, existingMovieID: nil)

    let added = await store.add(
      RadarrAddMovieRequest(
        lookup: lookup, qualityProfileID: 1, rootFolderPath: "/data/movies"))

    #expect(added == nil)
    #expect(store.addError == .serverUnreachable)
    #expect(library.state.value?.count == 1)
  }
}
