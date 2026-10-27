import Foundation
import Testing
import TowerCore
import TowerData

@testable import Tower

/// The issues list, its thread, and resolve/reopen.
@MainActor
@Suite
struct OverseerrIssuesStoreTests {
  private func issue(
    id: Int, status: IssueStatus = .open, type: IssueType = .audio,
    comments: [OverseerrComment] = []
  ) -> OverseerrIssue {
    OverseerrIssue(
      id: id, type: type, status: status, mediaType: .movie, tmdbID: 700_000 + id,
      createdBy: "Alex", createdAt: Date(timeIntervalSince1970: 1_700_000_000),
      comments: comments, title: "Example")
  }

  private func makeStore(
    _ issues: [OverseerrIssue]
  ) async -> (OverseerrIssuesStore, IssuesStubRepository) {
    let repository = IssuesStubRepository(issues: issues)
    let store = OverseerrIssuesStore(repository: repository)
    await store.load()
    return (store, repository)
  }

  // MARK: - Loading and filter

  @Test func openIssuesLeadBecauseTheScreenExistsToShowWhatIsWrong() async {
    let (store, repository) = await makeStore([
      issue(id: 1), issue(id: 2, status: .resolved),
    ])

    #expect(!store.includeResolved)
    #expect(repository.resolvedRequested == [false])
    #expect(store.state.value?.map(\.id) == [1])
  }

  @Test func showingResolvedIssuesAsksTheServiceForThem() async throws {
    // Filtering locally would hide resolved issues the service never sent.
    let (store, repository) = await makeStore([
      issue(id: 1), issue(id: 2, status: .resolved),
    ])

    store.includeResolved = true
    try await waitUntil { repository.resolvedRequested.contains(true) }

    #expect(store.state.value?.count == 2)
  }

  // MARK: - Empty state

  @Test func anEmptyListIsEmptyRatherThanAbsent() async {
    let (store, _) = await makeStore([])

    #expect(store.isEmpty)
    #expect(store.state.value?.isEmpty == true)
    // Not `.failed` — nothing went wrong, there is simply nothing broken.
    guard case .loaded = store.state else {
      Issue.record("expected .loaded, got \(store.state)")
      return
    }
  }

  // MARK: - Comments

  @Test func aCommentPostsAndAppearsInTheThread() async {
    let (store, repository) = await makeStore([issue(id: 1)])

    let posted = await store.comment(on: store.state.value![0], message: "Still broken.")

    #expect(posted)
    #expect(repository.comments.map(\.message) == ["Still broken."])
    #expect(store.state.value?[0].comments.count == 1)
    #expect(store.state.value?[0].comments.first?.message == "Still broken.")
  }

  @Test func theThreadIsReReadRatherThanAppendedLocally() async {
    // The comment's id, its author as the *server* resolves it, and its
    // timestamp all come from Overseerr. A locally-appended row would show the
    // wrong name for anyone whose display name differs from their login.
    let (store, repository) = await makeStore([issue(id: 1)])

    _ = await store.comment(on: store.state.value![0], message: "Hello")

    #expect(repository.listCalls == 2, "the thread was not re-read after posting")
    #expect(
      store.state.value?[0].comments.first?.author == "Server Resolved Name",
      "the locally-typed author survived instead of the server's")
  }

  @Test func anEmptyCommentIsNotPosted() async {
    let (store, repository) = await makeStore([issue(id: 1)])

    let posted = await store.comment(on: store.state.value![0], message: "   \n ")

    #expect(!posted)
    #expect(repository.comments.isEmpty)
  }

  @Test func aFailedCommentKeepsTheListAndReportsIt() async {
    let (store, repository) = await makeStore([issue(id: 1)])
    repository.failActions = true

    let posted = await store.comment(on: store.state.value![0], message: "Hello")

    #expect(!posted)
    #expect(store.lastActionFailure == 1)
    guard case .actionFailed(let issues, _) = store.state else {
      Issue.record("expected .actionFailed, got \(store.state)")
      return
    }
    #expect(issues.count == 1, "the list was lost to a failed comment")
  }

  // MARK: - Resolve, reversibly

  @Test func resolvingMovesTheIssueAndIsReversible() async throws {
    let (store, repository) = await makeStore([issue(id: 1)])
    // Showing resolved issues, so the row stays visible and its new status can
    // be asserted rather than merely disappearing.
    store.includeResolved = true
    try await waitUntil { repository.resolvedRequested.contains(true) }

    await store.setResolved(true, for: store.state.value![0])
    #expect(repository.statusWrites == [(1, true)].map { StatusWrite(id: $0.0, resolved: $0.1) })
    #expect(store.state.value?[0].status == .resolved)

    await store.setResolved(false, for: store.state.value![0])
    #expect(store.state.value?[0].status == .open, "reopening didn't take")
  }

  @Test func resolvingWhileHidingResolvedIssuesDropsTheRow() async {
    // Which is the correct outcome: it is no longer an open issue.
    let (store, _) = await makeStore([issue(id: 1), issue(id: 2)])

    await store.setResolved(true, for: store.state.value![0])

    #expect(store.state.value?.map(\.id) == [2])
  }

  @Test func resolvingBumpsTheHapticTriggerButALoadDoesNot() async {
    let (store, _) = await makeStore([issue(id: 1)])
    #expect(store.lastActionSuccess == 0)

    await store.setResolved(true, for: store.state.value![0])
    #expect(store.lastActionSuccess == 1)

    await store.refresh()
    #expect(store.lastActionSuccess == 1, "a refresh bumped the haptic trigger")
  }

  @Test func aDoubleTapCannotResolveTwice() async {
    let (store, repository) = await makeStore([issue(id: 1)])
    let target = store.state.value![0]

    async let first = store.setResolved(true, for: target)
    async let second = store.setResolved(true, for: target)
    _ = await (first, second)

    #expect(repository.statusWrites.count == 1, "resolved \(repository.statusWrites.count) times")
  }

  private func waitUntil(
    _ condition: @escaping () -> Bool, timeout: Duration = .seconds(2)
  ) async throws {
    let deadline = ContinuousClock.now + timeout
    while ContinuousClock.now < deadline {
      if condition() { return }
      try await Task.sleep(for: .milliseconds(5))
    }
    Issue.record("condition never became true")
  }
}

struct StatusWrite: Equatable, Sendable {
  let id: Int
  let resolved: Bool
}

// MARK: - Stub

final class IssuesStubRepository: OverseerrRepositoryProtocol, @unchecked Sendable {
  let instance = ServiceInstance(
    kind: .overseerr, name: "Overseerr", baseURL: URL(string: "http://192.0.2.1:5055")!,
    credentials: .apiKey("k"))

  private let lock = NSLock()
  private var stored: [OverseerrIssue]
  private var nextCommentID = 100

  var failActions = false

  private(set) var resolvedRequested: [Bool] = []
  private(set) var listCalls = 0
  private(set) var comments: [(issueID: Int, message: String)] = []
  private(set) var statusWrites: [StatusWrite] = []

  init(issues: [OverseerrIssue]) {
    self.stored = issues
  }

  func issues(includeResolved: Bool) async throws -> [OverseerrIssue] {
    lock.withLock {
      listCalls += 1
      resolvedRequested.append(includeResolved)
      return includeResolved ? stored : stored.filter { $0.status != .resolved }
    }
  }

  func comment(issueID: Int, message: String) async throws {
    if failActions { throw AppError.serverUnreachable }
    lock.withLock {
      comments.append((issueID, message))
      let id = nextCommentID
      nextCommentID += 1
      stored = stored.map { issue in
        guard issue.id == issueID else { return issue }
        return issue.addingComment(
          OverseerrComment(
            id: id, message: message,
            // Deliberately not the caller's name: the server resolves the
            // author, and the test asserts that is what shows.
            author: "Server Resolved Name", createdAt: Date()))
      }
    }
  }

  func setIssueResolved(_ isResolved: Bool, issueID: Int) async throws {
    if failActions { throw AppError.serverUnreachable }
    lock.withLock {
      statusWrites.append(StatusWrite(id: issueID, resolved: isResolved))
      stored = stored.map {
        $0.id == issueID ? $0.settingStatus(isResolved ? .resolved : .open) : $0
      }
    }
  }

  func requests(filter: RequestFilter, page: Int) async throws -> OverseerrRequestPage {
    OverseerrRequestPage(requests: [], page: 1, pages: 1, totalResults: 0)
  }
  func request(id: Int) async throws -> OverseerrRequest { throw AppError.unknown("unused") }
  func approve(requestID: Int) async throws {}
  func decline(requestID: Int) async throws {}
  func search(term: String) async throws -> [OverseerrSearchResult] { [] }
  func seasons(tmdbID: Int) async throws -> [OverseerrSeason] { [] }
  @discardableResult
  func submit(_ request: SubmitRequest) async throws -> OverseerrRequest {
    throw AppError.unknown("unused")
  }
}

extension OverseerrIssue {
  fileprivate func settingStatus(_ status: IssueStatus) -> OverseerrIssue {
    OverseerrIssue(
      id: id, type: type, status: status, mediaType: mediaType, tmdbID: tmdbID,
      createdBy: createdBy, createdAt: createdAt, comments: comments, title: title)
  }

  fileprivate func addingComment(_ comment: OverseerrComment) -> OverseerrIssue {
    OverseerrIssue(
      id: id, type: type, status: status, mediaType: mediaType, tmdbID: tmdbID,
      createdBy: createdBy, createdAt: createdAt, comments: comments + [comment], title: title)
  }
}
