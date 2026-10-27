import SwiftUI

/// What the app shows between its first frame and knowing whether a credential
/// is stored.
///
/// Deliberately just the launch screen's own background. Tower generates its
/// launch screen (`INFOPLIST_KEY_UILaunchScreen_Generation`), which is a plain
/// `systemBackground` fill, so drawing the same thing makes the handoff from the
/// launch image to SwiftUI invisible. `systemGroupedBackground` — what the rest
/// of the app's surfaces use — would be the wrong choice here for exactly that
/// reason: the point is to remove a visible change of screen at launch, not to
/// match whatever comes after it.
///
/// The spinner is delayed rather than immediate on the same reasoning. Reading
/// the keychain normally finishes within a frame or two, and a spinner that
/// appears and vanishes that fast is itself a flicker. It earns
/// its place only when the read is genuinely slow — a first unlock after a
/// reboot, or a device still bringing up its data protection classes.
struct LaunchPlaceholderView: View {
  /// Overridable so the previews can show both states at once: the spinner
  /// immediately, and the bare background. The app always uses the default.
  var progressDelay: Duration = .milliseconds(500)

  @State private var showsProgress = false

  var body: some View {
    ZStack {
      Color(.systemBackground)
        .ignoresSafeArea()
      ProgressView()
        .opacity(showsProgress ? 1 : 0)
    }
    .animation(.easeIn(duration: 0.2), value: showsProgress)
    // On the `ZStack`, not the `ProgressView`: the spinner doesn't exist for the
    // first half-second, and a test asserting "the placeholder is up, the
    // connect form is not" needs something present for the whole phase.
    .accessibilityIdentifier("launch.placeholder")
    .accessibilityLabel("Starting Tower")
    .task {
      try? await Task.sleep(for: progressDelay)
      showsProgress = true
    }
  }
}

#Preview("Before the spinner") {
  LaunchPlaceholderView(progressDelay: .seconds(60))
}

#Preview("Slow keychain read") {
  LaunchPlaceholderView(progressDelay: .zero)
}
