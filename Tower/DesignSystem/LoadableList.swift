import SwiftUI
import TowerCore

/// A loadable list with its own spinner, error, and empty state, so one
/// failing section of a screen doesn't affect another.
/// `Item: Sendable` because `Loadable`'s value must be — the same constraint
/// every store in this app already satisfies.
struct LoadableList<Item: Sendable, Content: View>: View {
  let state: Loadable<[Item]>
  let emptyTitle: String
  let identifier: String
  @ViewBuilder let content: ([Item]) -> Content

  /// The error a failed action left behind, if any.
  private var actionError: AppError? {
    if case .actionFailed(_, let error) = state { error } else { nil }
  }

  var body: some View {
    switch state {
    case .idle, .loading:
      ProgressView()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    case .failed(let error):
      ContentUnavailableView {
        Label(error.message, systemImage: "exclamationmark.triangle")
      } description: {
        if let suggestion = error.serviceRecoverySuggestion { Text(suggestion) }
      }
      .accessibilityIdentifier("\(identifier).error")
    case .loaded(let items), .actionFailed(let items, _):
      if items.isEmpty {
        ContentUnavailableView {
          Label(emptyTitle, systemImage: "tray")
        } description: {
          // An action that failed on the last row has no row left to sit
          // above, so the empty state carries the error instead.
          if let actionError { Text(actionError.message) }
        }
        .accessibilityIdentifier("\(identifier).empty")
      } else {
        // **No identifier on the `List`.** One on a container overwrites every
        // child's, which would rename every row underneath it to the
        // container's name (CLAUDE.md, "An accessibility identifier on a
        // container overwrites every child's"). The rows carry their own.
        List {
          if let actionError {
            ActionErrorText(error: actionError, identifier: "\(identifier).actionError")
          }
          content(items)
        }
      }
    }
  }
}

extension Double {
  /// A progress fraction held to 0...1. A service can report a progress
  /// slightly outside that range, and `ProgressView` renders that as a bar
  /// overflowing its track.
  var clampedToUnitInterval: Double { Swift.min(Swift.max(self, 0), 1) }
}
