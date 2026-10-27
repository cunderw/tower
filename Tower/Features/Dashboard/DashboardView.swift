import Foundation
import SwiftUI
import TowerCore

/// The Dashboard tab's screen: array capacity, system metrics, services, and
/// disk lists, backed by a `DashboardStore`.
///
/// `isShowingSettings` backs `RootView`'s settings gear:
/// `.modifier(TowerToolbarModifier(...))` is applied here, directly alongside
/// `.navigationTitle` inside this view's own `NavigationStack` — see
/// `TowerToolbarModifier`'s doc comment for why it can't just be chained
/// onto `DashboardView(...)` from `RootView` instead.
struct DashboardView: View {
  @Bindable var store: DashboardStore
  /// Drives the tab bar from `ServicesCard`'s rows. A one-way closure, not a
  /// `Binding<TowerTab>`: this view only ever *sets* the selection (tapping
  /// "Docker" while looking at Dashboard), it never needs to read the
  /// current tab, so a closure is the narrower, more honest interface.
  let onSelectTab: (TowerTab) -> Void
  @Binding var isShowingSettings: Bool
  /// Presented by the toolbar bell, which every tab carries.
  @Binding var isShowingNotifications: Bool
  /// The bell's badge, `nil` when nothing is unread. Passed down rather than read
  /// from a store here: `RootView` owns the one `NotificationStore`, and a tab
  /// that doesn't otherwise care about notifications shouldn't have to know it
  /// exists.
  let unreadCount: Int?
  /// Whether the Dashboard tab is the one currently on screen — drives
  /// `.pollingRefresh`, so a backgrounded tab (this one hidden behind
  /// Docker/VMs/Shares) costs nothing rather than polling unseen.
  let isSelected: Bool

  var body: some View {
    NavigationStack {
      content
        .navigationTitle("Dashboard")
        // Identifier, not value. `DiskDetailView` re-resolves the
        // disk from `store` on every render, so this destination doesn't
        // need to (and can't, without reaching back into the store itself)
        // capture anything beyond which disk it is.
        .navigationDestination(for: ArrayDisk.ID.self) { diskID in
          DiskDetailView(store: store, diskID: diskID)
        }
        .modifier(
          TowerToolbarModifier(
            isShowingNotifications: $isShowingNotifications,
            isShowingSettings: $isShowingSettings,
            unreadCount: unreadCount
          )
        )
    }
    // Interval omitted — `pollingRefresh`'s default is `Duration.towerPoll`,
    // which is where the `#if DEBUG` `UITEST_POLL_INTERVAL_MS` override
    // lives, shared with every other polling screen.
    .pollingRefresh(isActive: isSelected) { await store.refresh() }
  }

  @ViewBuilder
  private var content: some View {
    switch store.state {
    case .idle, .loading:
      LoadingStateView(title: "Loading dashboard…", isLoadInFlight: store.isLoadInFlight) {
        store.cancelLoad()
      }
    case .failed(let error):
      VStack(spacing: 16) {
        // The "Try Again" button is deliberately *not* passed as
        // `ContentUnavailableView`'s `actions:` closure: that would put it
        // inside the same view subtree `.accessibilityElement(children:
        // .combine)` below merges into one element, making the button
        // unreachable as its own tappable, identifiable element. Keeping it
        // a sibling — same shape as `ConnectView`'s separate error card and
        // submit button — lets each carry its own identifier.
        ContentUnavailableView {
          Label(error.message, systemImage: "exclamationmark.triangle")
        } description: {
          if let suggestion = error.recoverySuggestion { Text(suggestion) }
        }
        // Without `.combine`, SwiftUI treats `ContentUnavailableView`'s label
        // and description as separate accessibility elements and pushes
        // `.accessibilityIdentifier` down onto both of them — two elements
        // sharing one identifier, unreachable deterministically by a UI
        // test. `.combine` merges them into a single element the identifier
        // can actually attach to. Matches `ConnectView`'s `connect.error`.
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("dashboard.error")

        Button("Try Again") { Task { await store.load() } }
          .accessibilityIdentifier("dashboard.retry")
      }
    case .loaded(let snapshot), .actionFailed(let snapshot, _):
      ScrollView {
        VStack(spacing: 16) {
          // `.actionFailed` exists so a failed poll/refresh keeps showing
          // the last good snapshot *and* surfaces the error — silently
          // swallowing it here would defeat the entire point of the case.
          if case .actionFailed(_, let error) = store.state {
            Text(error.message)
              .font(.caption)
              .foregroundStyle(.red)
              .frame(maxWidth: .infinity, alignment: .leading)
          }
          ArrayHeroCard(snapshot: snapshot)
          SystemMetricsCard(system: snapshot.array.system)
          ServicesCard(counts: snapshot.services, onSelect: onSelectTab)
          // Each group is skipped entirely when empty — `DiskListCard` has
          // no "no disks" state of its own to fall back on, and a card with
          // a header but zero rows would be its own small lie about what the
          // array looks like.
          if !snapshot.array.disks.isEmpty {
            DiskListCard(title: "Data Disks", disks: snapshot.array.disks)
          }
          if !snapshot.array.parities.isEmpty {
            DiskListCard(title: "Parity", disks: snapshot.array.parities)
          }
          if !snapshot.array.caches.isEmpty {
            DiskListCard(title: "Cache", disks: snapshot.array.caches)
          }
        }
        .padding(16)
      }
      .background(Color(.systemGroupedBackground).ignoresSafeArea())
      .refreshable { await store.refresh() }
    }
  }
}
