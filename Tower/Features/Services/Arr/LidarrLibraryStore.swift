import Foundation
import Observation
import TowerCore
import TowerData

/// How the Lidarr library is ordered.
enum LidarrSort: String, CaseIterable, Identifiable, Hashable {
  case name, added, albums, size

  var id: String { rawValue }

  var displayName: String {
    switch self {
    case .name: "Name"
    case .added: "Recently added"
    case .albums: "Album count"
    case .size: "Size"
    }
  }

  func areInOrder(_ lhs: LidarrArtist, _ rhs: LidarrArtist) -> Bool {
    switch self {
    case .name:
      // Lidarr's own sort name, so Tower and the service agree about where
      // "The Wandering Signal" belongs.
      lhs.sortName.localizedCaseInsensitiveCompare(rhs.sortName) == .orderedAscending
    case .added:
      (lhs.added ?? .distantPast) > (rhs.added ?? .distantPast)
    case .albums:
      (lhs.statistics?.albumCount ?? 0, lhs.sortName) > (rhs.statistics?.albumCount ?? 0, rhs.sortName)
    case .size:
      (lhs.statistics?.sizeOnDiskBytes ?? 0) > (rhs.statistics?.sizeOnDiskBytes ?? 0)
    }
  }
}

/// The library filter, as one exclusive choice — the same shape Radarr's uses.
enum LidarrFilter: String, CaseIterable, Identifiable, Hashable {
  case all, monitored, missing, complete

  var id: String { rawValue }

  var displayName: String {
    switch self {
    case .all: "All"
    case .monitored: "Monitored"
    case .missing: "Missing"
    case .complete: "Complete"
    }
  }

  func matches(_ artist: LidarrArtist) -> Bool {
    switch self {
    case .all: true
    case .monitored: artist.isMonitored
    // "Missing" includes partial: an artist with half a discography has
    // something to go and find, which is what this filter is for.
    case .missing: artist.libraryState != .complete
    case .complete: artist.libraryState == .complete
    }
  }
}

/// Lidarr's library — artists, their albums, and those albums' tracks.
///
/// **One store for all three levels**, like `SonarrLibraryStore` and for the
/// same reason: an album's monitor toggle and the track list it governs must
/// not be able to disagree, which they can if each level owns its own copy.
@MainActor
@Observable
final class LidarrLibraryStore: RefreshableStore {
  var state: Loadable<[LidarrArtist]> = .idle
  let loads = LoadTracker()

  var searchText: String = ""
  var sort: LidarrSort = .name
  var filter: LidarrFilter = .all
  /// Bumped once per action that lands (a search, a monitor toggle, a
  /// delete), never by a load or a refresh, so a background fetch never buzzes.
  /// `LidarrServiceView` drives `.sensoryFeedback(.success, trigger:)` off it,
  /// once for the whole stack, so the artist and album screens do not.
  private(set) var lastActionSuccess = 0
  /// The failure twin of `lastActionSuccess`, driving
  /// `.sensoryFeedback(.error, trigger:)`.
  private(set) var lastActionFailure = 0

  /// Albums per artist, loaded when an artist screen opens.
  private(set) var albums: [Int: Loadable<[LidarrAlbum]>] = [:]
  /// Tracks per album, loaded when an album screen opens.
  private(set) var tracks: [Int: Loadable<[LidarrTrack]>] = [:]
  /// Metadata profile names, for the row and the edit sheet. A failure here
  /// costs a label, never the list.
  private(set) var metadataProfiles: [Int: String] = [:]

  let repository: any LidarrRepositoryProtocol

  init(repository: any LidarrRepositoryProtocol) {
    self.repository = repository
  }

  // MARK: - Loading

  func load() async {
    await load { [self] in try await repository.artists() }
  }

  func refresh() async {
    guard state.value != nil else { return await load() }
    await mutate { [self] in try await repository.artists() }
  }

  func loadMetadataProfiles() async {
    guard metadataProfiles.isEmpty else { return }
    guard let profiles = try? await repository.metadataProfiles() else { return }
    metadataProfiles = Dictionary(
      profiles.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
  }

  func metadataProfileName(for artist: LidarrArtist) -> String? {
    metadataProfiles[artist.metadataProfileID]
  }

  var filteredArtists: [LidarrArtist] {
    guard let artists = state.value else { return [] }
    let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    let searched = query.isEmpty
      ? artists
      // Genre as well as name: it is on the row, and it is how someone finds
      // "the ambient ones" without remembering a name.
      : artists.filter {
        $0.name.localizedCaseInsensitiveContains(query)
          || $0.genres.contains { $0.localizedCaseInsensitiveContains(query) }
      }
    return searched.filter(filter.matches).sorted(by: sort.areInOrder)
  }

  var isFilteredToNothing: Bool {
    guard let artists = state.value, !artists.isEmpty else { return false }
    return filteredArtists.isEmpty && filter != .all
  }

  func artist(id: Int) -> LidarrArtist? { state.value?.first { $0.id == id } }

  // MARK: - Albums and tracks

  func albums(for artistID: Int) -> Loadable<[LidarrAlbum]> { albums[artistID] ?? .idle }
  func tracks(for albumID: Int) -> Loadable<[LidarrTrack]> { tracks[albumID] ?? .idle }

  func album(id: Int, artistID: Int) -> LidarrAlbum? {
    albums[artistID]?.value?.first { $0.id == id }
  }

  func loadAlbums(artistID: Int, force: Bool = false) async {
    if !force, albums[artistID]?.value != nil { return }
    if albums[artistID]?.value == nil { albums[artistID] = .loading }
    do {
      albums[artistID] = .loaded(try await repository.albums(artistID: artistID))
    } catch {
      albums[artistID] = .failed(AppError.wrapping(error))
    }
  }

  func loadTracks(albumID: Int, force: Bool = false) async {
    if !force, tracks[albumID]?.value != nil { return }
    if tracks[albumID]?.value == nil { tracks[albumID] = .loading }
    do {
      tracks[albumID] = .loaded(try await repository.tracks(albumID: albumID))
    } catch {
      tracks[albumID] = .failed(AppError.wrapping(error))
    }
  }

  // MARK: - Monitoring

  func setArtistMonitored(_ isMonitored: Bool, for artist: LidarrArtist) async {
    await perform { [self] in
      var edit = LidarrArtistEdit(artist: artist)
      edit.isMonitored = isMonitored
      let updated = try await repository.update(artist, with: edit)
      return (state.value ?? []).map { $0.id == updated.id ? updated : $0 }
    }
  }

  /// Flips an album's monitor flag and patches that row.
  ///
  /// **Patched, not refetched.** Unlike Sonarr's season toggle — which Sonarr
  /// applies down to its episodes server-side, so the episode list has to be
  /// re-read — Lidarr's album flag governs nothing below it that Tower shows.
  /// The track list is unaffected, so refetching it would be work with no
  /// visible result.
  func setAlbumMonitored(_ isMonitored: Bool, album: LidarrAlbum) async {
    do {
      try await repository.setAlbumMonitored(isMonitored, albumIDs: [album.id])
      if let list = albums[album.artistID]?.value {
        albums[album.artistID] = .loaded(
          list.map { $0.id == album.id ? $0.settingMonitored(isMonitored) : $0 })
      }
      lastActionSuccess += 1
    } catch {
      state = .actionFailed(state.value ?? [], AppError.wrapping(error))
      lastActionFailure += 1
    }
  }

  // MARK: - Library maintenance

  func insert(_ artist: LidarrArtist) {
    guard let artists = state.value else { return }
    guard !artists.contains(where: { $0.id == artist.id }) else { return replace(artist) }
    state = .loaded(artists + [artist])
  }

  func replace(_ artist: LidarrArtist) {
    guard let artists = state.value else { return }
    state = .loaded(artists.map { $0.id == artist.id ? artist : $0 })
  }

  func delete(_ artist: LidarrArtist, deleteFiles: Bool) async {
    await perform { [self] in
      try await repository.delete(
        id: artist.id, deleteFiles: deleteFiles, addImportExclusion: false)
      return (state.value ?? []).filter { $0.id != artist.id }
    }
  }

  // MARK: - Search

  func runAutomaticSearch(artist: LidarrArtist) async {
    await perform { [self] in
      try await repository.searchArtist(id: artist.id)
      return state.value ?? []
    }
  }

  func runAutomaticSearch(album: LidarrAlbum) async {
    await perform { [self] in
      try await repository.searchAlbum(id: album.id)
      return state.value ?? []
    }
  }

  /// `mutate`, counting the outcome for the haptics.
  private func perform(_ action: () async throws -> [LidarrArtist]) async {
    var succeeded = false
    await mutate {
      let value = try await action()
      succeeded = true
      return value
    }
    if succeeded { lastActionSuccess += 1 } else { lastActionFailure += 1 }
  }
}

extension LidarrAlbum {
  /// A copy with the monitor flag flipped — the one field the album list
  /// changes locally.
  func settingMonitored(_ isMonitored: Bool) -> LidarrAlbum {
    LidarrAlbum(
      id: id, artistID: artistID, title: title, disambiguation: disambiguation,
      overview: overview, albumType: albumType, secondaryTypes: secondaryTypes,
      releaseDate: releaseDate, isMonitored: isMonitored,
      durationMilliseconds: durationMilliseconds, genres: genres, coverURL: coverURL,
      statistics: statistics)
  }
}
