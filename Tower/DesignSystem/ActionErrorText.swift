import SwiftUI
import TowerCore

/// The red caption a list shows first when an action on it failed: the list
/// stays on screen, and this row says what went wrong.
struct ActionErrorText: View {
  let error: AppError
  let identifier: String

  var body: some View {
    Text(error.message)
      .font(.caption)
      .foregroundStyle(.red)
      .accessibilityIdentifier(identifier)
  }
}
