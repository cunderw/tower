import Foundation
import Observation
import TowerCore
import TowerData

/// The add-artist flow.
///
/// Mirrors `RadarrAddStore` — search, pick, configure, add — with one shape
/// difference that matters: Lidarr needs a **metadata profile** as well as a
/// quality profile, and it needs to be told which of the artist's albums to
/// monitor. Adding an artist with no monitor option files an artist whose
/// entire discography is ignored.
@MainActor
@Observable
final class LidarrAddStore: LoadingStore, Identifiable {
  let id = UUID()

  var state: Loadable<[LidarrArtistLookup]> = .idle
  let loads = LoadTracker()

  var searchText: String = ""
  private(set) var lastSearchedTerm = ""

  /// The hit being configured, once one is picked.
  private(set) var selected: LidarrArtistLookup?

  var qualityProfileID: Int?
  var metadataProfileID: Int?
  var rootFolderPath: String?
  var monitorOption: LidarrMonitorOption = .all
  var isMonitored = true
  var searchOnAdd = true

  private(set) var qualityProfiles: [ArrQualityProfile] = []
  private(set) var metadataProfiles: [LidarrMetadataProfile] = []
  private(set) var rootFolders: [ArrRootFolder] = []

  private(set) var isSubmitting = false
  private(set) var addError: AppError?

  private let library: LidarrLibraryStore

  init(library: LidarrLibraryStore) {
    self.library = library
  }

  var canSearch: Bool {
    !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  /// Add is available only once the pickers have answered — the defaults come
  /// from the service, so there is nothing to add until they arrive.
  var canSubmit: Bool {
    selected != nil && qualityProfileID != nil && metadataProfileID != nil
      && rootFolderPath != nil && !isSubmitting
  }

  // MARK: - Search

  func search() async {
    let term = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !term.isEmpty else { return }
    lastSearchedTerm = term
    await load { [self] in try await library.repository.lookup(term: term) }
  }

  /// The pickers. Loaded once, alongside the sheet opening, and non-throwing:
  /// a failure leaves Add disabled rather than blanking the search.
  func loadPickers() async {
    async let quality = try? library.repository.qualityProfiles()
    async let metadata = try? library.repository.metadataProfiles()
    async let folders = try? library.repository.rootFolders()

    if let quality = await quality {
      qualityProfiles = quality
      qualityProfileID = qualityProfileID ?? quality.first?.id
    }
    if let metadata = await metadata {
      metadataProfiles = metadata
      metadataProfileID = metadataProfileID ?? metadata.first?.id
    }
    if let folders = await folders {
      rootFolders = folders
      rootFolderPath = rootFolderPath ?? folders.first?.path
    }
  }

  // MARK: - Selecting and adding

  func select(_ hit: LidarrArtistLookup) {
    guard !hit.isAlreadyAdded else { return }
    selected = hit
    addError = nil
  }

  func clearSelection() {
    selected = nil
    addError = nil
  }

  /// Adds the artist and puts them in the library. Returns true when the sheet
  /// should close.
  func submit() async -> Bool {
    guard let selected, let qualityProfileID, let metadataProfileID, let rootFolderPath,
      !isSubmitting
    else { return false }
    isSubmitting = true
    addError = nil
    defer { isSubmitting = false }

    do {
      let added = try await library.repository.add(
        LidarrAddArtistRequest(
          lookup: selected, qualityProfileID: qualityProfileID,
          metadataProfileID: metadataProfileID, rootFolderPath: rootFolderPath,
          monitorOption: monitorOption, isMonitored: isMonitored,
          searchForMissingAlbums: searchOnAdd))
      // The artist has to *appear in the library* at once, so the list is told
      // rather than left to a refresh that may not happen.
      library.insert(added)
      return true
    } catch {
      // The sheet stays open carrying the selection: a rejected add is usually
      // a root-folder or permissions problem, not a reason to search again.
      addError = AppError.wrapping(error)
      return false
    }
  }
}
