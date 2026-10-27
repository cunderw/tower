import SwiftUI
import TowerCore

extension Duration {
  /// The refresh policy: a 30-second poll while a tab is visible.
  ///
  /// `#if DEBUG` only, a UI test can override this via
  /// `UITEST_POLL_INTERVAL_MS` in `launchEnvironment`, so it can observe a
  /// poll actually land — and reach an already-open detail screen — without
  /// waiting 30 real seconds. See `DiskDetailUITests`' liveness
  /// proof. Never read outside DEBUG, so a shipped build's poll cadence can't
  /// be influenced by a stray environment variable.
  ///
  /// Lives here, as `pollingRefresh`'s own default, rather than as a private
  /// computed property per screen, because many screens poll and a
  /// per-screen copy drifts. A cadence that drifts between tabs is a bug nobody
  /// would notice from reading one file.
  static var towerPoll: Duration {
    uiTestOverride ?? .seconds(30)
  }

  /// The download clients' cadence: the same policy, six times as often.
  ///
  /// These screens earn it because a transfer speed thirty seconds old is not
  /// stale, it is *wrong*.
  static var towerFastPoll: Duration {
    uiTestOverride ?? .seconds(5)
  }

  /// Shared by both cadences so a UI test overriding the interval reaches every
  /// polling screen, and so the two can't drift apart. A screen that carries
  /// its own copy of this block escapes the override.
  private static var uiTestOverride: Duration? {
    #if DEBUG
    if let raw = ProcessInfo.processInfo.environment["UITEST_POLL_INTERVAL_MS"],
       let milliseconds = Int(raw) {
      return .milliseconds(milliseconds)
    }
    #endif
    return nil
  }
}

extension View {
  /// Refreshes on appear, whenever the app returns to the foreground, and
  /// every `interval` while `isActive`. The `.task(id:)` is torn down —
  /// cancelling the loop — when the app backgrounds or `isActive` goes
  /// false, so a hidden tab costs nothing.
  func pollingRefresh(
    every interval: Duration = .towerPoll,
    isActive: Bool,
    action: @escaping () async -> Void
  ) -> some View { modifier(PollingRefresh(interval: interval, isActive: isActive, action: action)) }
}

/// The `View`-side half of the refresh policy: decides *when* the `TowerCore
/// .poll` loop should be alive, and lets `.task(id:)` do the cancellation.
///
/// Keyed on `(isActive, scenePhase)` rather than just `scenePhase`: either
/// value changing tears down the running `.task` (cancelling `poll` via
/// `Task.isCancelled`/`Task.sleep`'s `CancellationError`) and starts a fresh
/// one, which is exactly "refresh on foreground" and "stop when the tab
/// isn't visible" for free, with no separate observer code.
private struct PollingRefresh: ViewModifier {
  let interval: Duration
  let isActive: Bool
  let action: () async -> Void

  @Environment(\.scenePhase) private var scenePhase

  private struct TaskKey: Hashable {
    let isActive: Bool
    let scenePhase: ScenePhase
  }

  func body(content: Content) -> some View {
    content.task(id: TaskKey(isActive: isActive, scenePhase: scenePhase)) {
      guard isActive, scenePhase == .active else { return }
      await poll(every: interval, action: action)
    }
  }
}
