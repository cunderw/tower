import Foundation
import Observation
import TowerCore
import TowerData

/// Overseerr's issues — what someone files when a request arrived broken.
///
/// **Not paginated, unlike the requests list.** Open issues are a handful even
/// on a busy server; the whole point is that they get resolved. `/issue` is
/// asked for 50 at a time, which is more than any real backlog.
@MainActor
@Observable
final class OverseerrIssuesStore: RefreshableStore {
  var state: Loadable<[OverseerrIssue]> = .idle
  let loads = LoadTracker()

  /// Off by default: an issues screen exists to show what is *wrong*, and
  /// leading with resolved history buries it.
  var includeResolved = false {
    didSet {
      guard includeResolved != oldValue else { return }
      Task { await load() }
    }
  }

  private(set) var inFlight: Set<Int> = []
  private(set) var lastActionSuccess = 0
  private(set) var lastActionFailure = 0

  let repository: any OverseerrRepositoryProtocol

  init(repository: any OverseerrRepositoryProtocol) {
    self.repository = repository
  }

  func load() async {
    await load { [self] in try await repository.issues(includeResolved: includeResolved) }
  }

  func refresh() async {
    guard state.value != nil else { return await load() }
    await mutate { [self] in try await repository.issues(includeResolved: includeResolved) }
  }

  func issue(id: Int) -> OverseerrIssue? {
    state.value?.first { $0.id == id }
  }

  var isEmpty: Bool { (state.value ?? []).isEmpty }

  func isInFlight(_ issue: OverseerrIssue) -> Bool { inFlight.contains(issue.id) }

  // MARK: - Actions

  /// Posts a comment and re-reads the thread.
  ///
  /// **Re-read rather than appended locally.** The comment's id, its author as
  /// the *server* resolves it, and its timestamp all come from Overseerr; a
  /// locally-appended row would show the wrong name for anyone whose display
  /// name differs from their login, and would need a fake id that a later
  /// refresh would replace with a different one.
  func comment(on issue: OverseerrIssue, message: String) async -> Bool {
    let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return false }
    return await act(on: issue) { [self] in
      try await repository.comment(issueID: issue.id, message: trimmed)
    }
  }

  /// Resolves or reopens. Reversible in both directions — an issue closed by
  /// mistake is a normal thing, and the API supports reopening.
  @discardableResult
  func setResolved(_ isResolved: Bool, for issue: OverseerrIssue) async -> Bool {
    await act(on: issue) { [self] in
      try await repository.setIssueResolved(isResolved, issueID: issue.id)
    }
  }

  @discardableResult
  private func act(
    on issue: OverseerrIssue, _ action: @escaping () async throws -> Void
  ) async -> Bool {
    guard !inFlight.contains(issue.id) else { return false }
    inFlight.insert(issue.id)
    defer { inFlight.remove(issue.id) }

    do {
      try await action()
      lastActionSuccess += 1
      // Re-reads the whole list rather than the one issue: the list is small,
      // and a resolved issue *leaves* the list when resolved ones are hidden,
      // which only a re-read gets right.
      await mutate { [self] in
        try await repository.issues(includeResolved: includeResolved)
      }
      return true
    } catch {
      lastActionFailure += 1
      state = .actionFailed(state.value ?? [], AppError.wrapping(error))
      return false
    }
  }
}
