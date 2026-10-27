import SwiftUI
import TowerCore

// Presentation for the service enums lives here, in the app layer, and not on
// the enums themselves — the same split `UsageLevel+Color.swift` and
// `StateDot.swift` use, and for the same reason: `TowerCore` imports Foundation
// only and must stay usable without SwiftUI.

extension ServiceKind {
  /// The row and sidebar glyph. SF Symbols only, no bundled service logos:
  /// the app's stated goal is to look like a system app, and eight third-party
  /// wordmarks in a list is the first thing that would break that.
  var systemImage: String {
    switch self {
    case .radarr: "film"
    case .sonarr: "tv"
    case .lidarr: "music.note"
    case .bazarr: "captions.bubble"
    case .prowlarr: "antenna.radiowaves.left.and.right"
    case .overseerr: "list.bullet.clipboard"
    case .nzbget: "arrow.down.doc"
    case .tautulli: "chart.bar"
    }
  }
}

extension ServiceStatus {
  /// `.red` for both failure states — the hub badge — and `.green` when the
  /// service answered. Never the only signal: `summary` says the same thing in
  /// words, in visible text, on every row.
  var indicatorColor: Color {
    isReachable ? .green : .red
  }
}
