import Foundation
import TowerCore

enum SonarrSort: String, CaseIterable, Identifiable, Hashable {
  case title, network, size, added

  var id: String { rawValue }

  var displayName: String {
    switch self {
    case .title: "Title"
    case .network: "Network"
    case .size: "Size"
    case .added: "Recently added"
    }
  }

  func areInOrder(_ lhs: SonarrSeries, _ rhs: SonarrSeries) -> Bool {
    switch self {
    case .title:
      lhs.sortTitle.localizedCaseInsensitiveCompare(rhs.sortTitle) == .orderedAscending
    case .network:
      // Series with no network sort last, then by title within a network.
      (lhs.network ?? "\u{10FFFF}", lhs.sortTitle) < (rhs.network ?? "\u{10FFFF}", rhs.sortTitle)
    case .size:
      lhs.sizeOnDiskBytes > rhs.sizeOnDiskBytes
    case .added:
      (lhs.added ?? .distantPast) > (rhs.added ?? .distantPast)
    }
  }
}

enum SonarrFilter: String, CaseIterable, Identifiable, Hashable {
  case all, monitored, missing, continuing

  var id: String { rawValue }

  var displayName: String {
    switch self {
    case .all: "All"
    case .monitored: "Monitored"
    case .missing: "Missing episodes"
    case .continuing: "Continuing"
    }
  }

  func matches(_ series: SonarrSeries) -> Bool {
    switch self {
    case .all: true
    case .monitored: series.isMonitored
    // Missing counts *aired* episodes without files — the same distinction
    // Radarr's missing filter makes, applied per series.
    case .missing: !series.isComplete && (series.statistics?.episodeCount ?? 0) > 0
    case .continuing: series.status == .continuing
    }
  }
}
