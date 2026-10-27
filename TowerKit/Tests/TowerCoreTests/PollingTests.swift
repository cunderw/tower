import Testing
import Foundation
@testable import TowerCore

struct PollingTests {
  /// Fires immediately, then once per interval — a poll that waits a full
  /// interval before its first run leaves a stale screen for 30 seconds.
  @Test func runsImmediatelyThenOncePerInterval() async {
    let counter = Counter()
    await poll(
      every: .seconds(30),
      sleep: { _ in
        if await counter.count >= 3 { throw CancellationError() }
      },
      action: { await counter.increment() }
    )
    #expect(await counter.count == 3)
  }

  /// A throwing sleep is how cancellation reaches the loop; it must exit,
  /// not spin.
  @Test func stopsWhenSleepThrows() async {
    let counter = Counter()
    await poll(
      every: .seconds(30),
      sleep: { _ in throw CancellationError() },
      action: { await counter.increment() }
    )
    #expect(await counter.count == 1)
  }

  @Test func passesTheConfiguredIntervalToSleep() async {
    let recorded = Recorder()
    await poll(
      every: .seconds(5),
      sleep: { duration in
        await recorded.record(duration)
        throw CancellationError()
      },
      action: {}
    )
    #expect(await recorded.durations == [.seconds(5)])
  }
}

actor Counter {
  private(set) var count = 0
  func increment() { count += 1 }
}

actor Recorder {
  private(set) var durations: [Duration] = []
  func record(_ duration: Duration) { durations.append(duration) }
}
