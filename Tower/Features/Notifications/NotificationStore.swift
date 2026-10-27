import Foundation
import Observation
import TowerCore
import TowerData

/// One action a notification row can trigger.
enum NotificationAction: Sendable, Hashable {
  case archive
  case markUnread
  case delete

  var title: String {
    switch self {
    case .archive: "Archive"
    case .markUnread: "Mark Unread"
    case .delete: "Delete"
    }
  }

  /// One glyph per action, so the swipe and the context menu agree.
  var systemImage: String {
    switch self {
    case .archive: "archivebox"
    case .markUnread: "envelope.badge"
    case .delete: "trash"
    }
  }
}

/// Backs the toolbar bell's badge and the notification sheet.
///
/// **Two pieces of state with different lifetimes**, which is why this store
/// doesn't look like `DockerStore`:
///
/// - `overview` drives the badge and must stay current whether or not the sheet
///   is open, so it is refreshed by the shell's own poll (`RootView`) and is
///   *not* part of `state`. Wrapping it in `Loadable` would mean a failed
///   overview fetch blanks a badge that was previously correct; instead a
///   failure leaves the last known counts alone, because a stale count is
///   closer to the truth than no count.
/// - `state` is the currently-selected bucket's accumulated pages, and only
///   matters while the sheet is open.
@MainActor
@Observable
final class NotificationStore: LoadingStore {
  /// The selected bucket's notifications, accumulated across pages.
  var state: Loadable<[ServerNotification]> = .idle

  /// The one line `LoadingStore` needs per store — see `LoadTracker` for why it
  /// can't live in the protocol extension.
  let loads = LoadTracker()
  /// Which bucket the sheet is showing. Changing it resets paging and reloads —
  /// see `select(_:)`, which the view calls rather than writing this directly.
  private(set) var selectedKind: NotificationKind = .unread
  /// The badge's source. Never `Loadable`: see the type's doc comment.
  private(set) var overview: NotificationOverview = .zero
  /// Notification IDs with an action in flight.
  var inFlight: Set<ServerNotification.ID> = []
  /// Whether the current bucket has more pages. `false` once a short page comes
  /// back — the only end signal this API offers.
  private(set) var hasMorePages = true
  /// True while a `loadMore()` is running, so the view can show a footer spinner
  /// and avoid firing a second page request on the same scroll.
  private(set) var isLoadingMore = false
  private(set) var lastActionSuccess = 0
  private(set) var lastActionFailure = 0

  /// How many notifications to request per page. Small enough that the first
  /// page renders immediately on a slow LAN, large enough that a typical box's
  /// unread bucket arrives in one request.
  static let pageSize = 25

  private let repository: any NotificationRepositoryProtocol

  init(repository: any NotificationRepositoryProtocol) {
    self.repository = repository
  }

  // MARK: - Badge

  /// Refreshes only the counts. Cheap enough for the shell to poll whichever
  /// tab is showing, and deliberately silent on failure: the badge keeps its
  /// last known value rather than dropping to nothing, because "no badge" is a
  /// claim that there is nothing unread.
  func refreshOverview() async {
    guard let refreshed = try? await repository.overview() else { return }
    overview = refreshed
  }

  // MARK: - The sheet's list

  /// First load of the selected bucket. Resets paging.
  func load() async {
    hasMorePages = true
    await load { [self, selectedKind] in
      let page = try await repository.page(kind: selectedKind, offset: 0, limit: Self.pageSize)
      hasMorePages = !page.isLastPage
      return page.notifications
    }
    // The counts and the list are separate queries, so opening the sheet is also
    // the moment to make sure the badge agrees with what's on screen.
    await refreshOverview()
  }

  /// Pull-to-refresh: never passes through `.loading`, so a transient failure
  /// doesn't blank a list the user is reading.
  func refresh() async {
    guard state.value != nil else { return await load() }
    await mutate { [selectedKind] in
      let page = try await repository.page(kind: selectedKind, offset: 0, limit: Self.pageSize)
      hasMorePages = !page.isLastPage
      return page.notifications
    }
    await refreshOverview()
  }

  /// Switches buckets. A no-op when already showing that one, so a segmented
  /// control that re-reports its current value doesn't refetch.
  func select(_ kind: NotificationKind) async {
    guard kind != selectedKind else { return }
    selectedKind = kind
    state = .idle
    hasMorePages = true
    await load()
  }

  /// Fetches the next page and appends it.
  ///
  /// Guards on `isLoadingMore` *and* `hasMorePages` before awaiting: a scroll
  /// gesture fires this repeatedly, and without the first guard each fire would
  /// request the same offset again and append duplicates. Offset is derived from
  /// what is already loaded rather than a page counter, so a duplicate call
  /// can't skip a page.
  ///
  /// A failure here is deliberately *not* routed through `.actionFailed`: the
  /// pages already loaded are still valid and still on screen, and turning a
  /// failed "load more" into a red banner over a working list overstates it. It
  /// leaves `hasMorePages` true, so the user can simply scroll again.
  func loadMore() async {
    guard hasMorePages, !isLoadingMore, let loaded = state.value else { return }
    isLoadingMore = true
    defer { isLoadingMore = false }

    guard let page = try? await repository.page(
      kind: selectedKind, offset: loaded.count, limit: Self.pageSize
    ) else { return }

    hasMorePages = !page.isLastPage
    // Filtered against what's already loaded: the server's list can shift between
    // requests (a notification arrives, another is archived elsewhere), and an
    // offset-paged API has no cursor to protect against that. Appending blindly
    // would produce duplicate rows with duplicate ids, which `ForEach` renders
    // badly and `List` animates worse.
    let existing = Set(loaded.map(\.id))
    state = .loaded(loaded + page.notifications.filter { !existing.contains($0.id) })
  }

  // MARK: - Actions

  /// Runs one action against a notification, going through `mutate` so a failure
  /// preserves the list and surfaces the message.
  ///
  /// The acted-on notification is removed from the current bucket's list on
  /// success, because that is what happened: archiving moves it out of unread,
  /// marking unread moves it out of the archive, and deleting removes it
  /// entirely. The overview comes back from the repository rather than being
  /// decremented locally — the badge is a claim about the server, and a local
  /// count drifts the first time Unraid's own web UI archives something.
  func perform(_ action: NotificationAction, on notification: ServerNotification) async {
    guard !inFlight.contains(notification.id) else { return }
    inFlight.insert(notification.id)

    var succeeded = false
    await mutate {
      let refreshed = try await run(action, on: notification)
      succeeded = true
      overview = refreshed
      guard let loaded = state.value else {
        throw AppError.unknown("No notifications loaded.")
      }
      return loaded.filter { $0.id != notification.id }
    }

    inFlight.remove(notification.id)
    if succeeded {
      lastActionSuccess += 1
    } else {
      lastActionFailure += 1
    }
  }

  /// Archives every unread notification, then reloads whichever bucket is on
  /// screen — both change: unread empties and the archive grows.
  func archiveAll() async {
    var succeeded = false
    await mutate {
      overview = try await repository.archiveAll()
      succeeded = true
      let page = try await repository.page(kind: selectedKind, offset: 0, limit: Self.pageSize)
      hasMorePages = !page.isLastPage
      return page.notifications
    }
    if succeeded {
      lastActionSuccess += 1
    } else {
      lastActionFailure += 1
    }
  }

  private func run(
    _ action: NotificationAction, on notification: ServerNotification
  ) async throws -> NotificationOverview {
    switch action {
    case .archive: try await repository.archive(id: notification.id)
    case .markUnread: try await repository.markUnread(id: notification.id)
    case .delete: try await repository.delete(id: notification.id, kind: notification.kind)
    }
  }

  // MARK: - Derived

  /// Which actions a notification in the current bucket can be offered.
  ///
  /// Archive and Mark Unread are inverses, and exactly one applies per bucket;
  /// Delete applies to both. Derived from the notification's own `kind` rather
  /// than `selectedKind`, so a row can't be offered an action that contradicts
  /// what it actually is.
  func actions(for notification: ServerNotification) -> [NotificationAction] {
    switch notification.kind {
    case .unread: [.archive, .delete]
    case .archive: [.markUnread, .delete]
    // A bucket Tower doesn't recognize: Delete is the only action whose meaning
    // doesn't depend on knowing which bucket it's in.
    case .unknown: [.delete]
    }
  }

  /// Whether anything at all is in the currently-selected bucket. Distinct from
  /// `state.value?.isEmpty` only in that it is false before the first load, so
  /// the view doesn't flash an empty state while loading.
  var isEmpty: Bool {
    state.value?.isEmpty ?? false
  }

  /// True when the sheet should offer "Archive All" — only in the unread bucket,
  /// and only when there is something to archive.
  var canArchiveAll: Bool {
    selectedKind == .unread && !(state.value?.isEmpty ?? true)
  }
}
