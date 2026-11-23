import SwiftUI
import TowerCore

/// The Parity screen's route. One value, because there is one parity check per
/// server: the screen re-reads the current status from `DashboardStore` on
/// every render (ADR 0002), so the route carries nothing to go stale. Its own
/// type, not a `String`, because `DashboardView` already routes `String`
/// values (`ArrayDisk.ID`) to the disk detail screen.
struct ParityRoute: Hashable {}

/// The parity check buttons for the current state: Start when idle, Pause and
/// Cancel Check while running, Resume and Cancel Check while paused. Shared by
/// the dashboard's hero card and the Parity screen, so the two cannot disagree
/// about which actions apply or which confirm.
///
/// Start asks whether to correct errors, and Cancel Check asks for
/// confirmation, because both are expensive to undo: a check reads every disk
/// in the array for many hours, and a cancelled one starts again from zero.
/// Pause and Resume run at once.
struct ParityControls: View {
  let actions: [ParityAction]
  /// Disables every button while an action is in flight.
  let actionInFlight: ParityAction?
  /// The action and, for `.start`, whether to correct errors.
  let perform: (ParityAction, Bool) -> Void

  @State private var isConfirmingStart = false
  @State private var isConfirmingCancel = false
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  var body: some View {
    // Two buttons side by side do not fit at accessibility sizes.
    let layout = dynamicTypeSize.isAccessibilitySize
      ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
      : AnyLayout(HStackLayout(spacing: 8))
    layout {
      ForEach(actions, id: \.self) { action in
        button(for: action)
      }
    }
    .buttonStyle(.bordered)
    .disabled(actionInFlight != nil)
  }

  /// Icon and title at a fixed spacing. A plain `Label` inside a `List` row
  /// takes the list's icon column, which spreads the two apart on the Parity
  /// screen while the hero card keeps them together.
  private func label(_ action: ParityAction, systemImage: String) -> some View {
    HStack(spacing: 6) {
      // Hidden, as `Label` hides it: VoiceOver reads the title alone.
      Image(systemName: systemImage)
        .accessibilityHidden(true)
      Text(action.title)
    }
  }

  @ViewBuilder
  private func button(for action: ParityAction) -> some View {
    switch action {
    case .start:
      Button { isConfirmingStart = true } label: { label(action, systemImage: "play.fill") }
        .accessibilityIdentifier("parity.action.start")
        // On the button, not the container, so the iPad popover points at it.
        .confirmationDialog(
          "Start a parity check?", isPresented: $isConfirmingStart, titleVisibility: .visible
        ) {
          Button("Check and Correct Errors") { perform(.start, true) }
          Button("Check Only") { perform(.start, false) }
          Button("Cancel", role: .cancel) {}
        } message: {
          Text(
            "The check reads every disk in the array and can take many hours. "
              + "Correcting writes fixes to parity; checking only counts errors."
          )
        }
    case .pause:
      Button { perform(.pause, false) } label: { label(action, systemImage: "pause.fill") }
        .accessibilityIdentifier("parity.action.pause")
    case .resume:
      Button { perform(.resume, false) } label: { label(action, systemImage: "play.fill") }
        .accessibilityIdentifier("parity.action.resume")
    case .cancel:
      Button(role: .destructive) { isConfirmingCancel = true } label: { label(action, systemImage: "xmark") }
        .accessibilityIdentifier("parity.action.cancel")
        .confirmationDialog(
          "Cancel the parity check?", isPresented: $isConfirmingCancel, titleVisibility: .visible
        ) {
          Button("Cancel Check", role: .destructive) { perform(.cancel, false) }
          Button("Don't Cancel", role: .cancel) {}
        } message: {
          Text("Its progress is lost. The next check starts again from the beginning.")
        }
    }
  }
}
