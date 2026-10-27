import SwiftUI
import TowerCore
import TowerData

/// The sheet the toolbar bell opens: an unread/archive segmented control over a
/// list of notifications, with swipe actions and paging.
///
/// A sheet rather than a tab — notifications are something you check
/// and dismiss, not a place you navigate to, and the bell is reachable from every
/// tab.
struct NotificationSheet: View {
  let store: NotificationStore
  /// The server, for resolving a notification's relative `linkPath`. See
  /// `resolvedLink(for:)`.
  let server: Server

  @Environment(\.dismiss) private var dismiss
  /// The notification awaiting a delete confirmation. Deleting is the one
  /// irreversible action here.
  @State private var pendingDeletion: ServerNotification?
  /// Whether "Archive All" is awaiting confirmation — bulk, though reversible one
  /// at a time.
  @State private var isConfirmingArchiveAll = false

  var body: some View {
    NavigationStack {
      content
        .navigationTitle("Notifications")
        .toolbar {
          ToolbarItem(placement: .topBarLeading) {
            Button("Done") { dismiss() }
              .accessibilityIdentifier("notifications.done")
          }
          ToolbarItem(placement: .topBarTrailing) {
            if store.canArchiveAll {
              Button("Archive All") { isConfirmingArchiveAll = true }
                .accessibilityIdentifier("notifications.archiveAll")
            }
          }
        }
        .safeAreaInset(edge: .top) { bucketPicker }
    }
    // The list is only fetched while this sheet exists, unlike the badge's
    // counts, which one shell-level poll in `RootView` keeps current.
    .task { await store.load() }
    .sensoryFeedback(.success, trigger: store.lastActionSuccess)
    .sensoryFeedback(.error, trigger: store.lastActionFailure)
    .confirmationDialog(
      "Delete this notification?",
      isPresented: isPresentingDeletion,
      titleVisibility: .visible,
      presenting: pendingDeletion
    ) { notification in
      Button("Delete", role: .destructive) {
        Task { await store.perform(.delete, on: notification) }
      }
      Button("Cancel", role: .cancel) {}
    } message: { _ in
      Text("This can't be undone. Archiving keeps it and hides it from the unread list.")
    }
    .confirmationDialog(
      "Archive all unread notifications?",
      isPresented: $isConfirmingArchiveAll,
      titleVisibility: .visible
    ) {
      Button("Archive All") { Task { await store.archiveAll() } }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text("They move to the archive, where you can mark any of them unread again.")
    }
  }

  /// Outside the `List` (via `safeAreaInset`) rather than as a list row, so it
  /// stays put while the list scrolls — a bucket switcher that scrolls away is a
  /// switcher you have to hunt for.
  private var bucketPicker: some View {
    Picker("Bucket", selection: bucketSelection) {
      Text("Unread").tag(NotificationKind.unread)
      Text("Archive").tag(NotificationKind.archive)
    }
    .pickerStyle(.segmented)
    .padding(.horizontal)
    .padding(.bottom, 8)
    .background(.bar)
    .accessibilityIdentifier("notifications.bucketPicker")
  }

  /// The picker writes through `store.select(_:)` rather than to `selectedKind`
  /// directly: switching buckets resets paging and reloads, and a plain binding
  /// would leave the old bucket's rows on screen under the new label.
  private var bucketSelection: Binding<NotificationKind> {
    Binding(
      get: { store.selectedKind },
      set: { kind in Task { await store.select(kind) } }
    )
  }

  private var isPresentingDeletion: Binding<Bool> {
    Binding(
      get: { pendingDeletion != nil },
      set: { isPresented in if !isPresented { pendingDeletion = nil } }
    )
  }

  @ViewBuilder
  private var content: some View {
    switch store.state {
    case .idle, .loading:
      LoadingStateView(title: "Loading notifications…", isLoadInFlight: store.isLoadInFlight) {
        store.cancelLoad()
      }
    case .failed(let error):
      VStack(spacing: 16) {
        ContentUnavailableView {
          Label(error.message, systemImage: "exclamationmark.triangle")
        } description: {
          if let suggestion = error.recoverySuggestion { Text(suggestion) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("notifications.error")

        Button("Try Again") { Task { await store.load() } }
          .accessibilityIdentifier("notifications.retry")
      }
    case .loaded, .actionFailed:
      notificationList
    }
  }

  @ViewBuilder
  private var notificationList: some View {
    List {
      if case .actionFailed(_, let error) = store.state {
        Text(error.message)
          .font(.caption)
          .foregroundStyle(.red)
          .accessibilityIdentifier("notifications.actionError")
      }

      ForEach(store.state.value ?? []) { notification in
        row(notification)
      }

      if store.hasMorePages, !(store.state.value ?? []).isEmpty {
        // A row rather than a button: it appears as the user reaches the bottom
        // and fetches on appearance, which is what "paginate on scroll" means
        // here. `store.loadMore()` guards against the repeated firing that
        // `onAppear` produces.
        HStack {
          Spacer()
          ProgressView()
            .controlSize(.small)
          Spacer()
        }
        .accessibilityIdentifier("notifications.loadingMore")
        .onAppear { Task { await store.loadMore() } }
      }
    }
    .overlay {
      if store.isEmpty {
        emptyState
      }
    }
    .refreshable { await store.refresh() }
  }

  /// Two different sentences, because "nothing unread" and "nothing archived" are
  /// different facts — and neither is "you have no notifications".
  @ViewBuilder
  private var emptyState: some View {
    switch store.selectedKind {
    case .unread:
      ContentUnavailableView(
        "No Unread Notifications", systemImage: "bell.slash",
        description: Text("Anything you've archived is under Archive.")
      )
      .accessibilityIdentifier("notifications.emptyUnread")
    case .archive, .unknown:
      ContentUnavailableView(
        "Nothing Archived", systemImage: "archivebox",
        description: Text("Notifications you archive are kept here.")
      )
      .accessibilityIdentifier("notifications.emptyArchive")
    }
  }

  @ViewBuilder
  private func row(_ notification: ServerNotification) -> some View {
    let isInFlight = store.inFlight.contains(notification.id)
    NotificationRow(notification: notification, isInFlight: isInFlight)
      .swipeActions(edge: .trailing, allowsFullSwipe: false) {
        // `allowsFullSwipe: false` deliberately: the trailing edge's first action
        // is Delete, and a full swipe would delete without the confirmation this
        // sheet insists on.
        Button(role: .destructive) {
          pendingDeletion = notification
        } label: {
          Label("Delete", systemImage: "trash")
        }
        .disabled(isInFlight)
        // Identified because "Delete" and "Archive" are not unique labels on this
        // screen — the bucket picker has an "Archive" button of its own, and a UI
        // test matching by label taps the picker instead, switching buckets while
        // looking exactly like a successful swipe action.
        .accessibilityIdentifier("notifications.swipe.delete")
      }
      .swipeActions(edge: .leading, allowsFullSwipe: true) {
        // Archive (or its inverse) is reversible, so a full swipe is fine here.
        if let action = store.actions(for: notification).first(where: { $0 != .delete }) {
          Button {
            Task { await store.perform(action, on: notification) }
          } label: {
            Label(action.title, systemImage: action.systemImage)
          }
          .tint(.accentColor)
          .disabled(isInFlight)
          // See the trailing swipe's identifier above: label matching is
          // ambiguous against the bucket picker.
          .accessibilityIdentifier("notifications.swipe.\(action == .archive ? "archive" : "markUnread")")
        }
      }
      .contextMenu {
        ForEach(store.actions(for: notification), id: \.self) { action in
          Button(role: action == .delete ? .destructive : nil) {
            if action == .delete {
              pendingDeletion = notification
            } else {
              Task { await store.perform(action, on: notification) }
            }
          } label: {
            Label(action.title, systemImage: action.systemImage)
          }
          .disabled(isInFlight)
        }
        if let link = resolvedLink(for: notification) {
          Link(destination: link) {
            Label("Open in Unraid", systemImage: "safari")
          }
        }
      }
  }

  /// Resolves a notification's **relative** `linkPath` against the server's base
  /// URL.
  ///
  /// Unraid sends `"/Settings/UPSsettings"`. `URL(string:)` on that succeeds and
  /// produces a *relative* URL that opens nothing, which is why the domain model
  /// carries the raw path and this resolution happens here, where `Server` is in
  /// scope. Anything that doesn't resolve yields `nil` and the affordance
  /// disappears, rather than offering a link that does nothing.
  private func resolvedLink(for notification: ServerNotification) -> URL? {
    guard let path = notification.linkPath else { return nil }
    return URL(string: path, relativeTo: server.url)?.absoluteURL
  }
}
