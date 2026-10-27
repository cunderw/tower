import Foundation
import Observation
import TowerCore
import TowerData

/// The pickers every *arr edit and add sheet needs: quality profiles, root
/// folders, and tags.
///
/// **Loaded from the service, never hardcoded.** These are per-instance
/// settings — one Radarr's "HD-1080p" is profile 4 and another's is profile 6 —
/// so a hardcoded list would send the wrong id to half the instances someone
/// owns.
@MainActor
@Observable
final class ArrPickerOptions {
  private(set) var qualityProfiles: [ArrQualityProfile] = []
  private(set) var rootFolders: [ArrRootFolder] = []
  private(set) var tags: [ArrTag] = []
  private(set) var error: AppError?
  private(set) var isLoading = false

  private let source: any ArrPickerSource

  init(source: any ArrPickerSource) {
    self.source = source
  }

  var isLoaded: Bool { !qualityProfiles.isEmpty && !rootFolders.isEmpty }

  func load() async {
    guard !isLoaded, !isLoading else { return }
    isLoading = true
    defer { isLoading = false }
    do {
      // Concurrently: three independent GETs, and a sheet that waits for them
      // in sequence is three round trips of blank pickers.
      async let profiles = source.qualityProfiles()
      async let folders = source.rootFolders()
      async let tagList = source.tags()
      qualityProfiles = try await profiles
      rootFolders = try await folders
      tags = try await tagList
      error = nil
    } catch {
      self.error = AppError.wrapping(error)
    }
  }
}

/// The edit sheet's state for one movie.
@MainActor
@Observable
final class RadarrEditStore: Identifiable {
  /// `Identifiable` only so the detail screen can present it with
  /// `.sheet(item:)`, which guarantees a fresh store per presentation.
  let id = UUID()

  let movie: RadarrMovie
  var edit: RadarrMovieEdit
  let options: ArrPickerOptions
  private(set) var isSaving = false
  private(set) var saveError: AppError?

  private let library: RadarrLibraryStore

  init(movie: RadarrMovie, library: RadarrLibraryStore) {
    self.movie = movie
    self.edit = RadarrMovieEdit(movie: movie)
    self.library = library
    self.options = ArrPickerOptions(source: library.repository)
  }

  var hasChanges: Bool { edit != RadarrMovieEdit(movie: movie) }

  /// Saves, and reports whether the sheet should close. A failure keeps the
  /// sheet open with what the user typed still in it — dismissing on failure
  /// loses the edit and tells them nothing.
  func save() async -> Bool {
    isSaving = true
    defer { isSaving = false }
    do {
      let updated = try await library.repository.update(movie, with: edit)
      library.replace(updated)
      saveError = nil
      return true
    } catch {
      saveError = AppError.wrapping(error)
      return false
    }
  }
}

/// The add-movie flow: search TMDb through Radarr, pick a result, configure it.
@MainActor
@Observable
final class RadarrAddStore: Identifiable {
  let id = UUID()

  var searchText: String = ""
  private(set) var results: Loadable<[RadarrMovieLookup]> = .idle
  let options: ArrPickerOptions
  private(set) var isAdding = false
  private(set) var addError: AppError?

  private let library: RadarrLibraryStore

  init(library: RadarrLibraryStore) {
    self.library = library
    self.options = ArrPickerOptions(source: library.repository)
  }

  /// Runs the lookup. Deliberately explicit (submit, not every keystroke): each
  /// search hits TMDb through the service, and typing "the matrix" would fire
  /// ten of them.
  func search() async {
    let term = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !term.isEmpty else {
      results = .idle
      return
    }
    results = .loading
    do {
      results = .loaded(try await library.repository.lookup(term: term))
    } catch {
      results = .failed(AppError.wrapping(error))
    }
  }

  /// Adds the configured movie and puts it in the library list. Returns the
  /// added movie, or `nil` if it failed — in which case the sheet stays open
  /// with the configuration intact.
  func add(_ request: RadarrAddMovieRequest) async -> RadarrMovie? {
    isAdding = true
    defer { isAdding = false }
    do {
      let added = try await library.repository.add(request)
      library.insert(added)
      addError = nil
      return added
    } catch {
      addError = AppError.wrapping(error)
      return nil
    }
  }
}

/// The add-series flow: search TVDB through Sonarr, pick a result, configure it.
///
/// The Radarr shape with Sonarr's extra decisions — series type, season
/// folders, and *which* episodes to monitor, which is a question Radarr simply
/// doesn't have.
@MainActor
@Observable
final class SonarrAddStore: Identifiable {
  let id = UUID()
  var searchText: String = ""
  private(set) var results: Loadable<[SonarrSeriesLookup]> = .idle
  let options: ArrPickerOptions
  private(set) var isAdding = false
  private(set) var addError: AppError?

  private let library: SonarrLibraryStore

  init(library: SonarrLibraryStore) {
    self.library = library
    self.options = ArrPickerOptions(source: library.repository)
  }

  func search() async {
    let term = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !term.isEmpty else {
      results = .idle
      return
    }
    results = .loading
    do {
      results = .loaded(try await library.repository.lookup(term: term))
    } catch {
      results = .failed(AppError.wrapping(error))
    }
  }

  func add(_ request: SonarrAddSeriesRequest) async -> SonarrSeries? {
    isAdding = true
    defer { isAdding = false }
    do {
      let added = try await library.repository.add(request)
      library.insert(added)
      addError = nil
      return added
    } catch {
      addError = AppError.wrapping(error)
      return nil
    }
  }
}
