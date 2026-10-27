import Foundation
import Testing
import TowerCore
import TowerData
@testable import Tower

@MainActor
struct NotificationStoreTests {
  // MARK: - The badge

  @Test func theBadgeSurvivesAFailedOverviewFetch() async {
    // The reason `overview` isn't wrapped in `Loadable`: dropping the badge to
    // nothing on a transient failure is a *claim* — that there is nothing unread
    // — and a stale count is closer to the truth than that.
    let repository = StubNotificationRepository(
      overviews: [.success(.twoUnreadAlerts), .failure(.serverUnreachable)]
    )
    let store = NotificationStore(repository: repository)

    await store.refreshOverview()
    #expect(store.overview.badgeCount == 2)

    await store.refreshOverview()
    #expect(store.overview.badgeCount == 2, "a failed poll dropped the badge")
  }

  @Test func theBadgeStartsAtNothingRatherThanZero() async {
    let store = NotificationStore(repository: StubNotificationRepository())
    #expect(store.overview.badgeCount == nil)
  }

  // MARK: - Loading a bucket

  @Test func loadFetchesTheSelectedBucketAndTheCounts() async {
    let repository = StubNotificationRepository(
      overviews: [.success(.twoUnreadAlerts)],
      pages: [.success(NotificationPage(notifications: [.stub(id: "1"), .stub(id: "2")], requestedLimit: 25))]
    )
    let store = NotificationStore(repository: repository)

    await store.load()

    #expect(store.state.value?.map(\.id) == ["1", "2"])
    #expect(store.overview.badgeCount == 2, "opening the sheet should also reconcile the badge")
  }

  @Test func aFullFirstPageLeavesMorePagesAvailable() async {
    let full = (1...25).map { ServerNotification.stub(id: "\($0)") }
    let store = NotificationStore(repository: StubNotificationRepository(
      pages: [.success(NotificationPage(notifications: full, requestedLimit: 25))]
    ))

    await store.load()

    #expect(store.hasMorePages)
  }

  @Test func aShortFirstPageEndsPaging() async {
    let store = NotificationStore(repository: StubNotificationRepository(
      pages: [.success(NotificationPage(notifications: [.stub(id: "1")], requestedLimit: 25))]
    ))

    await store.load()

    #expect(!store.hasMorePages)
  }

  @Test func refreshKeepsPreviousDataOnFailure() async {
    let first = [ServerNotification.stub(id: "1")]
    let store = NotificationStore(repository: StubNotificationRepository(
      pages: [
        .success(NotificationPage(notifications: first, requestedLimit: 25)),
        .failure(.serverUnreachable),
      ]
    ))

    await store.load()
    await store.refresh()

    #expect(store.state.value?.map(\.id) == ["1"])
    #expect(store.state.error != nil)
  }

  // MARK: - Buckets

  @Test func selectingTheOtherBucketReloadsRatherThanKeepingTheOldRows() async {
    // Leaving the previous bucket's rows on screen under the new label is the
    // failure this guards against — which is why the picker writes through
    // `select(_:)` rather than to `selectedKind`.
    let repository = StubNotificationRepository(
      pages: [
        .success(NotificationPage(notifications: [.stub(id: "unread-1")], requestedLimit: 25)),
        .success(NotificationPage(notifications: [.stub(id: "archived-1", kind: .archive)], requestedLimit: 25)),
      ]
    )
    let store = NotificationStore(repository: repository)
    await store.load()

    await store.select(.archive)

    #expect(store.selectedKind == .archive)
    #expect(store.state.value?.map(\.id) == ["archived-1"])
    #expect(repository.requestedKinds == [.unread, .archive])
  }

  @Test func selectingTheBucketAlreadyShowingDoesNotRefetch() async {
    // A segmented control re-reporting its current value must not cost a request.
    let repository = StubNotificationRepository(
      pages: [.success(NotificationPage(notifications: [.stub(id: "1")], requestedLimit: 25))]
    )
    let store = NotificationStore(repository: repository)
    await store.load()

    await store.select(.unread)

    #expect(repository.pageCallCount == 1)
  }

  // MARK: - Paging

  @Test func loadMoreAppendsTheNextPageAtTheRightOffset() async {
    let repository = StubNotificationRepository(
      pages: [
        .success(NotificationPage(notifications: (1...25).map { .stub(id: "\($0)") }, requestedLimit: 25)),
        .success(NotificationPage(notifications: [.stub(id: "26")], requestedLimit: 25)),
      ]
    )
    let store = NotificationStore(repository: repository)
    await store.load()

    await store.loadMore()

    #expect(store.state.value?.count == 26)
    #expect(store.state.value?.last?.id == "26")
    // Offset derived from what's loaded, not a page counter — 25 rows means the
    // next page starts at 25.
    #expect(repository.requestedOffsets == [0, 25])
    #expect(!store.hasMorePages, "a short second page ends paging")
  }

  @Test func loadMoreDropsDuplicatesTheServerRepeats() async {
    // An offset-paged API has no cursor: if a notification arrives (or is
    // archived elsewhere) between requests, the same row can come back on the
    // next page. Appending blindly produces duplicate ids, which `ForEach`
    // renders badly and `List` animates worse.
    let repository = StubNotificationRepository(
      pages: [
        .success(NotificationPage(notifications: (1...25).map { .stub(id: "\($0)") }, requestedLimit: 25)),
        .success(NotificationPage(notifications: [.stub(id: "25"), .stub(id: "26")], requestedLimit: 25)),
      ]
    )
    let store = NotificationStore(repository: repository)
    await store.load()

    await store.loadMore()

    let ids = store.state.value?.map(\.id) ?? []
    #expect(ids.count == Set(ids).count, "duplicate ids survived paging: \(ids)")
    #expect(ids.last == "26")
  }

  @Test func loadMoreDoesNothingOnceTheEndIsReached() async {
    let store = NotificationStore(repository: StubNotificationRepository(
      pages: [.success(NotificationPage(notifications: [.stub(id: "1")], requestedLimit: 25))]
    ))
    await store.load()

    await store.loadMore()

    // A second page was never stubbed; reaching for one would trip the stub's
    // own precondition.
    #expect(store.state.value?.count == 1)
  }

  @Test func aFailedLoadMoreDoesNotDisturbTheRowsAlreadyOnScreen() async {
    // Deliberately not routed through `.actionFailed`: the loaded pages are still
    // valid and still on screen, and a red banner over a working list overstates
    // a failed "load more". `hasMorePages` stays true so the user can scroll again.
    let repository = StubNotificationRepository(
      pages: [
        .success(NotificationPage(notifications: (1...25).map { .stub(id: "\($0)") }, requestedLimit: 25)),
        .failure(.serverUnreachable),
      ]
    )
    let store = NotificationStore(repository: repository)
    await store.load()

    await store.loadMore()

    #expect(store.state.value?.count == 25)
    #expect(store.state.error == nil, "a failed page fetch must not surface as an error over a working list")
    #expect(store.hasMorePages)
  }

  // MARK: - Actions

  @Test func archivingRemovesTheRowFromUnreadAndTakesTheServersNewCounts() async {
    let notification = ServerNotification.stub(id: "1")
    let repository = StubNotificationRepository(
      pages: [.success(NotificationPage(notifications: [notification, .stub(id: "2")], requestedLimit: 25))],
      actions: [.success(.oneUnreadAlert)]
    )
    let store = NotificationStore(repository: repository)
    await store.load()

    await store.perform(.archive, on: notification)

    #expect(store.state.value?.map(\.id) == ["2"], "the archived row stayed in the unread list")
    // The count came from the server, not a local decrement — the badge is a
    // claim about the server's state.
    #expect(store.overview.badgeCount == 1)
    #expect(store.lastActionSuccess == 1)
  }

  @Test func aFailedActionKeepsTheListAndSurfacesTheError() async {
    let notification = ServerNotification.stub(id: "1")
    let repository = StubNotificationRepository(
      pages: [.success(NotificationPage(notifications: [notification], requestedLimit: 25))],
      actions: [.failure(.serverUnreachable)]
    )
    let store = NotificationStore(repository: repository)
    await store.load()

    await store.perform(.delete, on: notification)

    #expect(store.state.value?.map(\.id) == ["1"], "a failed delete removed the row anyway")
    #expect(store.state.error == .serverUnreachable)
    #expect(store.lastActionFailure == 1)
    #expect(store.inFlight.isEmpty)
  }

  @Test func anActionOnARowWithNothingInFlightReachesTheRepository() async {
    let notification = ServerNotification.stub(id: "1")
    let repository = StubNotificationRepository(
      pages: [.success(NotificationPage(notifications: [notification], requestedLimit: 25))],
      actions: [.success(.oneUnreadAlert)]
    )
    let store = NotificationStore(repository: repository)
    await store.load()

    // One action on a row with nothing in flight reaches the repository, and
    // the row leaves the in-flight set when it completes. Only one action is
    // stubbed, so a second repository call would fail the test.
    await store.perform(.archive, on: notification)
    #expect(repository.actionCallCount == 1)
    #expect(store.inFlight.isEmpty)
  }

  @Test func archiveAllEmptiesUnreadAndClearsTheBadge() async {
    let repository = StubNotificationRepository(
      pages: [
        .success(NotificationPage(notifications: [.stub(id: "1"), .stub(id: "2")], requestedLimit: 25)),
        .success(NotificationPage(notifications: [], requestedLimit: 25)),
      ],
      archiveAlls: [.success(.zero)]
    )
    let store = NotificationStore(repository: repository)
    await store.load()

    await store.archiveAll()

    #expect(store.overview.badgeCount == nil)
    #expect(store.state.value?.isEmpty == true)
    #expect(store.lastActionSuccess == 1)
  }

  // MARK: - Derived

  @Test func actionsDependOnTheNotificationsOwnBucketNotTheSelectedOne() async {
    // A row must never be offered an action that contradicts what it is — which is
    // possible while a bucket switch is in flight, or if the server returns a
    // notification whose `type` disagrees with the filter.
    let store = NotificationStore(repository: StubNotificationRepository())

    #expect(store.actions(for: .stub(id: "1", kind: .unread)) == [.archive, .delete])
    #expect(store.actions(for: .stub(id: "2", kind: .archive)) == [.markUnread, .delete])
    // A bucket Tower doesn't recognize: Delete is the only action whose meaning
    // doesn't depend on knowing which bucket it's in.
    #expect(store.actions(for: .stub(id: "3", kind: .unknown)) == [.delete])
  }

  @Test func archiveAllIsOfferedOnlyForANonEmptyUnreadBucket() async {
    let store = NotificationStore(repository: StubNotificationRepository(
      pages: [
        .success(NotificationPage(notifications: [.stub(id: "1")], requestedLimit: 25)),
        .success(NotificationPage(notifications: [.stub(id: "2", kind: .archive)], requestedLimit: 25)),
      ]
    ))
    #expect(!store.canArchiveAll, "offered before anything loaded")

    await store.load()
    #expect(store.canArchiveAll)

    await store.select(.archive)
    #expect(!store.canArchiveAll, "offered while showing the archive")
  }
}

/// Queued outcomes per method — same shape as `DockerStoreTests`' stub. Records
/// the arguments the store passed, because *which* bucket and *which* offset were
/// requested is the behaviour under test for paging and bucket switching.
private final class StubNotificationRepository: NotificationRepositoryProtocol, @unchecked Sendable {
  enum OverviewResult { case success(NotificationOverview), failure(AppError) }
  enum PageResult { case success(NotificationPage), failure(AppError) }
  enum ActionResult { case success(NotificationOverview), failure(AppError) }

  private let lock = NSLock()
  private var overviews: [OverviewResult]
  private var pages: [PageResult]
  private var actions: [ActionResult]
  private var archiveAlls: [ActionResult]
  private var _requestedKinds: [NotificationKind] = []
  private var _requestedOffsets: [Int] = []
  private var _actionCallCount = 0

  var requestedKinds: [NotificationKind] { lock.withLock { _requestedKinds } }
  var requestedOffsets: [Int] { lock.withLock { _requestedOffsets } }
  var pageCallCount: Int { lock.withLock { _requestedKinds.count } }
  var actionCallCount: Int { lock.withLock { _actionCallCount } }

  init(
    overviews: [OverviewResult] = [],
    pages: [PageResult] = [],
    actions: [ActionResult] = [],
    archiveAlls: [ActionResult] = []
  ) {
    self.overviews = overviews
    self.pages = pages
    self.actions = actions
    self.archiveAlls = archiveAlls
  }

  /// `overview()` is called by `load()`/`refresh()`/actions as well as by the
  /// badge poll, so an exhausted queue returns `.zero` rather than tripping a
  /// precondition — tests that care about the counts stub them, and tests that
  /// don't shouldn't have to.
  func overview() async throws -> NotificationOverview {
    let next: OverviewResult? = lock.withLock { overviews.isEmpty ? nil : overviews.removeFirst() }
    switch next {
    case .success(let overview): return overview
    case .failure(let error): throw error
    case nil: return .zero
    }
  }

  func page(kind: NotificationKind, offset: Int, limit: Int) async throws -> NotificationPage {
    let next: PageResult = lock.withLock {
      _requestedKinds.append(kind)
      _requestedOffsets.append(offset)
      precondition(!pages.isEmpty, "page() called more times than results were stubbed")
      return pages.removeFirst()
    }
    switch next {
    case .success(let page): return page
    case .failure(let error): throw error
    }
  }

  func archive(id: String) async throws -> NotificationOverview { try nextAction() }
  func markUnread(id: String) async throws -> NotificationOverview { try nextAction() }
  func delete(id: String, kind: NotificationKind) async throws -> NotificationOverview { try nextAction() }

  func archiveAll() async throws -> NotificationOverview {
    let next: ActionResult = lock.withLock {
      precondition(!archiveAlls.isEmpty, "archiveAll() called more times than results were stubbed")
      return archiveAlls.removeFirst()
    }
    switch next {
    case .success(let overview): return overview
    case .failure(let error): throw error
    }
  }

  private func nextAction() throws -> NotificationOverview {
    let next: ActionResult = lock.withLock {
      _actionCallCount += 1
      precondition(!actions.isEmpty, "an action was called more times than results were stubbed")
      return actions.removeFirst()
    }
    switch next {
    case .success(let overview): return overview
    case .failure(let error): throw error
    }
  }
}

extension NotificationOverview {
  /// Two unread alerts and six archived.
  fileprivate static let twoUnreadAlerts = NotificationOverview(
    unread: NotificationCounts(info: 0, warning: 0, alert: 2, total: 2),
    archive: NotificationCounts(info: 1, warning: 0, alert: 5, total: 6)
  )

  fileprivate static let oneUnreadAlert = NotificationOverview(
    unread: NotificationCounts(info: 0, warning: 0, alert: 1, total: 1),
    archive: NotificationCounts(info: 1, warning: 0, alert: 6, total: 7)
  )
}

extension ServerNotification {
  fileprivate static func stub(id: String, kind: NotificationKind = .unread) -> ServerNotification {
    ServerNotification(
      id: id, title: "Unraid Server Alert", subject: "UPS Alert",
      description: "UPS on tower is running on battery power", importance: .alert, kind: kind,
      linkPath: nil, timestamp: nil
    )
  }
}
