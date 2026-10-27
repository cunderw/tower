import Foundation
import Observation
import TowerCore
import TowerData

/// How the release list is ordered.
///
/// There is no quality sort. A quality *rank* isn't in the API's release
/// payload, alphabetical is meaningless for quality names, and the only proxy
/// left is size — which is the Size sort under another name.
enum ReleaseSort: String, CaseIterable, Identifiable, Hashable {
  case bestMatch, size, age

  var id: String { rawValue }

  var displayName: String {
    switch self {
    case .bestMatch: "Best match"
    case .size: "Size"
    case .age: "Age"
    }
  }

  func areInOrder(_ lhs: ArrRelease, _ rhs: ArrRelease) -> Bool {
    switch self {
    case .bestMatch:
      // The *arr has already decided what it would take; approved releases lead,
      // and within each group the service's own order stands (`releases` keeps
      // ties stable). Anything else puts a rejected release at the top of a
      // list whose whole purpose is picking one.
      lhs.isApproved && !rhs.isApproved
    case .size:
      lhs.sizeBytes > rhs.sizeBytes
    case .age:
      (lhs.ageHours ?? .greatestFiniteMagnitude) < (rhs.ageHours ?? .greatestFiniteMagnitude)
    }
  }
}

/// What an interactive search is *for*: one movie, one episode, one artist or
/// one album.
///
/// The screen is built once and parameterised by this: Radarr, Sonarr's
/// episode level and Lidarr reach the same list, which is the point of the
/// shared `ArrRelease` model.
enum InteractiveSearchScope: Equatable, Sendable {
  case movie(id: Int, title: String)
  case episode(id: Int, title: String)
  /// Lidarr searches at two levels rather than one. Added here rather
  /// than in a parallel music-only search screen, because the releases and the
  /// grab are the shared `ArrRelease` shape — the sorting, the rejection
  /// handling, and the confirm-before-grab are all already right.
  case artist(id: Int, title: String)
  case album(id: Int, title: String)

  var title: String {
    switch self {
    case .movie(_, let title), .episode(_, let title),
      .artist(_, let title), .album(_, let title):
      title
    }
  }
}

/// Fetches releases for a scope and grabs the one the user picks.
@MainActor
@Observable
final class InteractiveSearchStore: Identifiable {
  let id = UUID()
  let scope: InteractiveSearchScope
  private(set) var state: Loadable<[ArrRelease]> = .idle
  private(set) var grabError: AppError?
  private(set) var grabbing: Set<String> = []
  /// Bumped on a successful grab — what the view's `.sensoryFeedback` watches.
  private(set) var grabCount = 0
  var sort: ReleaseSort = .bestMatch

  private let fetch: @Sendable () async throws -> [ArrRelease]
  private let grabRelease: @Sendable (ArrRelease) async throws -> Void

  init(
    scope: InteractiveSearchScope,
    fetch: @escaping @Sendable () async throws -> [ArrRelease],
    grab: @escaping @Sendable (ArrRelease) async throws -> Void
  ) {
    self.scope = scope
    self.fetch = fetch
    self.grabRelease = grab
  }

  /// Sorted by `sort`, with ties left in the order the service sent them.
  var releases: [ArrRelease] {
    (state.value ?? []).enumerated()
      .sorted {
        if sort.areInOrder($0.element, $1.element) { return true }
        if sort.areInOrder($1.element, $0.element) { return false }
        return $0.offset < $1.offset
      }
      .map(\.element)
  }

  func load() async {
    state = .loading
    do {
      state = .loaded(try await fetch())
    } catch {
      state = .failed(AppError.wrapping(error))
    }
  }

  /// Grabs a release. The list stays exactly as it is — a grab is a request to
  /// the download client, not an edit to the search results, and re-running the
  /// search to "refresh" it would cost another round of indexer queries.
  func grab(_ release: ArrRelease) async {
    grabbing.insert(release.id)
    defer { grabbing.remove(release.id) }
    do {
      try await grabRelease(release)
      grabError = nil
      grabCount += 1
    } catch {
      // The *arr's own words — a rejected grab usually explains itself better
      // than any wording here could.
      grabError = AppError.wrapping(error)
    }
  }

  func isGrabbing(_ release: ArrRelease) -> Bool { grabbing.contains(release.id) }
}

extension InteractiveSearchStore {
  /// Radarr: one movie.
  static func movie(
    _ movie: RadarrMovie, repository: any RadarrRepositoryProtocol
  ) -> InteractiveSearchStore {
    InteractiveSearchStore(
      scope: .movie(id: movie.id, title: movie.title),
      fetch: { try await repository.releases(movieID: movie.id) },
      grab: { try await repository.grab($0) }
    )
  }

  /// Sonarr: one episode. Series- and season-level searches are *automatic*
  /// searches (a command), not interactive ones — Sonarr's interactive search
  /// is per episode, and pretending otherwise would offer a release list that
  /// can't be acted on.
  static func episode(
    _ episode: SonarrEpisode, repository: any SonarrRepositoryProtocol
  ) -> InteractiveSearchStore {
    InteractiveSearchStore(
      scope: .episode(id: episode.id, title: "\(episode.episodeCode) · \(episode.title)"),
      fetch: { try await repository.releases(episodeID: episode.id) },
      grab: { try await repository.grab($0) }
    )
  }
}
