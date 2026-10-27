import Foundation

/// Runs `action` immediately, then every `interval` until cancelled.
///
/// `sleep` is injected so the loop is testable without real time passing —
/// a test supplies a closure that throws after N iterations, which is also
/// exactly how real cancellation arrives (`Task.sleep` throws
/// `CancellationError`).
///
/// `isolation: isolated (any Actor)? = #isolation`: the real caller today is
/// a SwiftUI `ViewModifier.body`, which this SDK marks `@MainActor`, and its
/// `action` is always `{ await store.refresh() }` against an `@MainActor`
/// store — a plain, non-isolated `poll` fails to compile there with "sending
/// 'action' risks causing data races" (confirmed empirically against a build,
/// along with `sending` and `sending @isolated(any)` on the closures, which
/// fail the same way). `#isolation` fixes this without
/// pinning `poll` to any one actor: it captures the *caller's* isolation at
/// the call site, so the call from `ViewModifier.body` is a same-actor call
/// with no `Sendable` requirement — but `poll` itself stays non-isolated and
/// callable from any context, including a future non-`@MainActor` caller
/// (e.g. a widget timeline provider) without forcing a hop to the main
/// actor for the loop's entire lifetime.
public func poll(
  every interval: Duration,
  sleep: (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
  action: () async -> Void,
  isolation: isolated (any Actor)? = #isolation
) async {
  while !Task.isCancelled {
    await action()
    do { try await sleep(interval) } catch { return }
  }
}
