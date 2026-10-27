import SwiftUI

/// The `.idle`/`.loading` branch every store-backed screen shows, with an escape
/// hatch.
///
/// **Why the Cancel button exists:** a bare `ProgressView` leaves a
/// hung request as an indeterminate spinner with no way out for the full 60-second
/// timeout. That is most likely on exactly the network Tower is designed for — a
/// LAN address that has become unreachable, where a request neither succeeds nor
/// fails fast. The `.failed` branch offers "Try Again", and without this the
/// loading branch would offer nothing.
///
/// Cancelling lands on `.failed(.cancelled)`, which every screen already renders
/// with its retry affordance — so the user ends somewhere with a way forward
/// rather than back on the same spinner.
///
/// The button appears only while a load is genuinely in flight. `.idle` shows a
/// spinner too (the moment between a screen appearing and its `.task` running),
/// and offering Cancel there would be a button that does nothing.
struct LoadingStateView: View {
  let title: String
  /// Whether a load is actually running — `store.isLoadInFlight`.
  let isLoadInFlight: Bool
  let onCancel: () -> Void

  var body: some View {
    VStack(spacing: 16) {
      ProgressView(title)
      if isLoadInFlight {
        Button("Cancel", role: .cancel, action: onCancel)
          .accessibilityIdentifier("loading.cancel")
      }
    }
  }
}

#Preview("Loading, cancellable") {
  LoadingStateView(title: "Loading dashboard…", isLoadInFlight: true) {}
}

/// The `.idle` moment before a `.task` has started: a spinner, but nothing to
/// cancel yet.
#Preview("Idle, nothing to cancel") {
  LoadingStateView(title: "Loading dashboard…", isLoadInFlight: false) {}
}
