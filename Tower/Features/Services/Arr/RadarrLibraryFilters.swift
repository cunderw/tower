import Foundation
import TowerCore

/// How the Radarr library is ordered.
///
/// Title uses Radarr's own `sortTitle` so Tower and the service agree about
/// where "The Thing" belongs.
enum RadarrSort: String, CaseIterable, Identifiable, Hashable {
  case title, year, size, added

  var id: String { rawValue }

  var displayName: String {
    switch self {
    case .title: "Title"
    case .year: "Year"
    case .size: "Size"
    case .added: "Recently added"
    }
  }

  func areInOrder(_ lhs: RadarrMovie, _ rhs: RadarrMovie) -> Bool {
    switch self {
    case .title:
      lhs.sortTitle.localizedCaseInsensitiveCompare(rhs.sortTitle) == .orderedAscending
    case .year:
      // Newest first, and an unknown year sorts last rather than to the top —
      // a film with no year is not the newest thing in the library.
      (lhs.year ?? Int.min, lhs.sortTitle) > (rhs.year ?? Int.min, rhs.sortTitle)
    case .size:
      lhs.sizeOnDiskBytes > rhs.sizeOnDiskBytes
    case .added:
      (lhs.added ?? .distantPast) > (rhs.added ?? .distantPast)
    }
  }
}

/// The two filters, as one exclusive choice rather than two
/// toggles: "monitored *and* missing" is the useful combination and "unmonitored
/// and missing" is noise, so the list offers the states a user actually asks
/// for.
enum RadarrFilter: String, CaseIterable, Identifiable, Hashable {
  case all, monitored, missing, downloaded

  var id: String { rawValue }

  var displayName: String {
    switch self {
    case .all: "All"
    case .monitored: "Monitored"
    case .missing: "Missing"
    case .downloaded: "Downloaded"
    }
  }

  func matches(_ movie: RadarrMovie) -> Bool {
    switch self {
    case .all: true
    case .monitored: movie.isMonitored
    // Missing means *available and not downloaded* — an unreleased film is not
    // missing, and listing it here sends the user searching for something that
    // does not exist yet.
    case .missing: movie.libraryState == .missing
    case .downloaded: movie.hasFile
    }
  }
}
