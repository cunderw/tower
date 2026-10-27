import Foundation

/// A gate any number of `async` calls can suspend on until the test lets them
/// through — either one at a time, by the index `enter()` handed back (so two
/// overlapping calls can be resolved in either order), or all together.
///
/// This is what makes the store concurrency tests deterministic rather than
/// timing-dependent: `waitUntilEntered(atLeast:)` proves a call has actually
/// parked inside the repository before the test asserts in-flight state or
/// releases another index, so nothing here depends on a sleep or a scheduling
/// guess.
///
/// An actor, not an `NSLock`-guarded class like `UITestSupport.swift`'s
/// `Attempts`, because releasing waiters means resuming continuations from
/// arbitrary callers without hand-rolling that safety.
///
/// Lives in its own file rather than `private` inside one test file because
/// `DockerStoreTests` and `VMStoreTests` both need it, for the same reason (a
/// stale refresh racing a completed mutation).
actor Gate {
  private var nextIndex = 0
  private var enterCount = 0
  private var releasedIndices: Set<Int> = []
  private var allReleased = false
  private var continuations: [Int: CheckedContinuation<Void, Never>] = [:]

  /// Called by the code under test. Returns this call's index immediately once
  /// let through — by `release(_:)` with a matching index, or by
  /// `releaseAll()` — otherwise suspends.
  @discardableResult
  func enter() async -> Int {
    let index = nextIndex
    nextIndex += 1
    enterCount += 1
    if allReleased || releasedIndices.contains(index) { return index }
    await withCheckedContinuation { continuations[index] = $0 }
    return index
  }

  /// Lets exactly the call whose `enter()` returned `index` through — resolves
  /// immediately if it's already waiting, or marks it so a not-yet-arrived
  /// `enter()` with that index returns right away.
  func release(_ index: Int) {
    releasedIndices.insert(index)
    if let continuation = continuations.removeValue(forKey: index) {
      continuation.resume()
    }
  }

  /// Lets every past/future `enter()` through, with no ordering guarantee
  /// between multiple already-waiting calls — for tests that only need to
  /// unblock one caller and don't care about relative ordering.
  func releaseAll() {
    allReleased = true
    let pending = continuations
    continuations = [:]
    pending.values.forEach { $0.resume() }
  }

  /// Yields until `enter()` has been called at least `count` times — how the
  /// test knows a call has actually reached the gate (not merely that its
  /// `Task` was created) before asserting in-flight state or releasing a
  /// specific index.
  func waitUntilEntered(atLeast count: Int) async {
    while enterCount < count { await Task.yield() }
  }
}
