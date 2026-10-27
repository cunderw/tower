import SwiftUI
import TowerCore

/// The VMs tab: a searchable list of libvirt domains backed by a `VMStore`.
/// Mirrors `DockerListView`'s state switch, `.refreshable`, and
/// `.pollingRefresh(isActive:)` — see that file for why each exists.
///
/// The one structural difference: **three** unavailable/empty states rather
/// than two. `vms.domains` is nullable, and "the VM manager isn't reporting"
/// must not render as "you have no VMs" — see `content` below.
struct VMListView: View {
  @Bindable var store: VMStore
  @Binding var isShowingSettings: Bool
  /// Presented by the toolbar bell, which every tab carries.
  @Binding var isShowingNotifications: Bool
  /// The bell's badge, `nil` when nothing is unread. Passed down rather than read
  /// from a store here: `RootView` owns the one `NotificationStore`, and a tab
  /// that doesn't otherwise care about notifications shouldn't have to know it
  /// exists.
  let unreadCount: Int?
  /// Whether the VMs tab is the one currently on screen — drives
  /// `.pollingRefresh`, so a backgrounded tab costs nothing.
  let isSelected: Bool

  /// The split layout's selected domain — see `DockerListView.selection` for
  /// why it lives on the list view rather than inside the scaffold.
  @State private var selection: VMDomain.ID?

  var body: some View {
    ListDetailScaffold(
      selection: $selection,
      placeholder: ListDetailPlaceholder(
        title: "No VM Selected",
        systemImage: "desktopcomputer",
        description: "Pick a virtual machine from the list to see its state and actions.",
        identifier: "vms.noSelection"
      )
    ) { isSplit in
      content(isSplit: isSplit)
        .navigationTitle("VMs")
        .searchable(text: $store.searchText, prompt: "Search VMs")
        .modifier(
          TowerToolbarModifier(
            isShowingNotifications: $isShowingNotifications,
            isShowingSettings: $isShowingSettings,
            unreadCount: unreadCount
          )
        )
    } detail: { domainID in
      // Identifier, not value. `VMDetailView` re-resolves
      // the domain from `store` on every render, so an action fired from
      // the detail screen itself reaches it.
      VMDetailView(store: store, domainID: domainID)
    }
    // Interval omitted — `Duration.towerPoll`, shared with every other polling
    // screen.
    .pollingRefresh(isActive: isSelected) { await store.refresh() }
  }

  @ViewBuilder
  private func content(isSplit: Bool) -> some View {
    switch store.state {
    case .idle, .loading:
      LoadingStateView(title: "Loading VMs…", isLoadInFlight: store.isLoadInFlight) {
        store.cancelLoad()
      }
    case .failed(let error):
      // Same shape as `DockerListView`'s error branch — the retry button is a
      // sibling of `ContentUnavailableView` rather than its `actions:` closure
      // so the combined accessibility element doesn't swallow it.
      VStack(spacing: 16) {
        ContentUnavailableView {
          Label(error.message, systemImage: "exclamationmark.triangle")
        } description: {
          if let suggestion = error.recoverySuggestion { Text(suggestion) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("vms.error")

        Button("Try Again") { Task { await store.load() } }
          .accessibilityIdentifier("vms.retry")
      }
    case .loaded, .actionFailed:
      domainList(isSplit: isSplit)
    }
  }

  @ViewBuilder
  private func domainList(isSplit: Bool) -> some View {
    // Always a `List`, even when it ends up empty: `.refreshable` needs a
    // scrollable container underneath it to produce a working pull gesture at
    // all. Matches `DockerListView`.
    // `selection:` only in the split layout — see `DockerListView` for why
    // passing it on iPhone stops the rows below from pushing at all.
    List(selection: isSplit ? $selection : nil) {
      // `.actionFailed` exists so a failed action or poll keeps the last good
      // list on screen *and* surfaces the error. This is where a refused
      // action ("Unraid refused this VM action.") lands.
      if case .actionFailed(_, let error) = store.state {
        Text(error.message)
          .font(.caption)
          .foregroundStyle(.red)
          .accessibilityIdentifier("vms.actionError")
      }
      ForEach(store.filteredDomains) { domain in
        VMRow(
          domain: domain,
          isInFlight: store.inFlight.contains(domain.id)
        ) { action in
          Task { await store.perform(action, on: domain) }
        }
        .listDetailRow(id: domain.id, isSplit: isSplit)
      }
    }
    // Only a real, user-triggered action buzzes — `store.perform(_:on:)` is
    // the only place either counter moves, so a background poll stays silent.
    .sensoryFeedback(.success, trigger: store.lastActionSuccess)
    .sensoryFeedback(.error, trigger: store.lastActionFailure)
    .overlay {
      // Three states, deliberately not conflated:
      //
      // 1. `isUnavailable` — the server returned `null` for `vms.domains`.
      //    The VM manager is off or erroring. Telling this user "you have no
      //    VMs" would be a claim about their server Tower cannot make, and is
      //    the same collapse the dashboard avoids for a null VM count.
      // 2. `isEmpty` — a healthy server with no VMs defined.
      // 3. Neither, but the search matched nothing.
      if store.isUnavailable {
        ContentUnavailableView(
          "VMs Unavailable",
          systemImage: "desktopcomputer.trianglebadge.exclamationmark",
          description: Text("This server isn't reporting virtual machines. The VM manager may be disabled or stopped.")
        )
        .accessibilityIdentifier("vms.unavailable")
      } else if store.isEmpty {
        ContentUnavailableView(
          "No VMs",
          systemImage: "desktopcomputer",
          description: Text("This server has no virtual machines.")
        )
        .accessibilityIdentifier("vms.empty")
      } else if store.filteredDomains.isEmpty {
        // `.search` with no explicit text reads the query out of this view's
        // own `.searchable` environment.
        ContentUnavailableView.search
      }
    }
    .refreshable { await store.refresh() }
  }
}

// No `#Preview` here, matching `DashboardView`/`DockerListView`: previewing a
// store-backed top-level screen needs a full repository fixture for little
// benefit over `VMRow`, which previews on its own.
