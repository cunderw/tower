import SwiftUI
import TowerCore

/// The Shares tab: a searchable list of user shares backed by a `ShareStore`.
/// Mirrors `DockerListView`'s state switch, `.refreshable`, and
/// `.pollingRefresh(isActive:)`.
///
/// Two empty states, not three: `shares` is a non-null list in the schema, so
/// there is no "unavailable" case here the way `vms.domains` has one.
struct ShareListView: View {
  @Bindable var store: ShareStore
  @Binding var isShowingSettings: Bool
  /// Presented by the toolbar bell, which every tab carries.
  @Binding var isShowingNotifications: Bool
  /// The bell's badge, `nil` when nothing is unread. Passed down rather than read
  /// from a store here: `RootView` owns the one `NotificationStore`, and a tab
  /// that doesn't otherwise care about notifications shouldn't have to know it
  /// exists.
  let unreadCount: Int?
  /// Whether the Shares tab is the one currently on screen — drives
  /// `.pollingRefresh`, so a backgrounded tab costs nothing.
  let isSelected: Bool

  /// The split layout's selected share — see `DockerListView.selection` for why
  /// it lives on the list view rather than inside the scaffold.
  @State private var selection: Share.ID?

  var body: some View {
    ListDetailScaffold(
      selection: $selection,
      placeholder: ListDetailPlaceholder(
        title: "No Share Selected",
        systemImage: "folder",
        description: "Pick a share from the list to see its allocation settings and disks.",
        identifier: "shares.noSelection"
      )
    ) { isSplit in
      content(isSplit: isSplit)
        .navigationTitle("Shares")
        .searchable(text: $store.searchText, prompt: "Search shares")
        .modifier(
          TowerToolbarModifier(
            isShowingNotifications: $isShowingNotifications,
            isShowingSettings: $isShowingSettings,
            unreadCount: unreadCount
          )
        )
    } detail: { shareID in
      // Identifier, not value.
      ShareDetailView(store: store, shareID: shareID)
    }
    // Interval omitted — `Duration.towerPoll`, shared with every polling screen.
    .pollingRefresh(isActive: isSelected) { await store.refresh() }
  }

  @ViewBuilder
  private func content(isSplit: Bool) -> some View {
    switch store.state {
    case .idle, .loading:
      LoadingStateView(title: "Loading shares…", isLoadInFlight: store.isLoadInFlight) {
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
        .accessibilityIdentifier("shares.error")

        Button("Try Again") { Task { await store.load() } }
          .accessibilityIdentifier("shares.retry")
      }
    case .loaded(let shares), .actionFailed(let shares, _):
      shareList(shares, isSplit: isSplit)
    }
  }

  @ViewBuilder
  private func shareList(_ shares: [Share], isSplit: Bool) -> some View {
    // Always a `List`, even when empty: `.refreshable` needs a scrollable
    // container underneath it to produce a working pull gesture at all.
    // `selection:` only in the split layout — see `DockerListView` for why
    // passing it on iPhone stops the rows below from pushing at all.
    List(selection: isSplit ? $selection : nil) {
      // A failed poll keeps the last good list *and* surfaces the error.
      if case .actionFailed(_, let error) = store.state {
        Text(error.message)
          .font(.caption)
          .foregroundStyle(.red)
          .accessibilityIdentifier("shares.refreshError")
      }
      ForEach(store.filteredShares) { share in
        ShareRow(share: share)
          .listDetailRow(id: share.id, isSplit: isSplit)
      }
    }
    // No `.sensoryFeedback` here, unlike the Docker and VMs lists: nothing on
    // this screen mutates anything, so there is no user action to confirm
    // haptically. A buzz on a background poll would be noise.
    .overlay {
      // Two distinct empty states: a server with no shares reads differently
      // from a search that matched nothing.
      if shares.isEmpty {
        ContentUnavailableView(
          "No Shares", systemImage: "folder",
          description: Text("This server has no user shares.")
        )
        .accessibilityIdentifier("shares.empty")
      } else if store.filteredShares.isEmpty {
        ContentUnavailableView.search
      }
    }
    .refreshable { await store.refresh() }
  }
}

// No `#Preview` here, matching every other top-level screen: it would need a
// full repository fixture for little benefit over `ShareRow`, which previews on
// its own.
