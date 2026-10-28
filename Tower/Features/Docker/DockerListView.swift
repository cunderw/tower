import SwiftUI
import TowerCore

/// The Docker tab's screen: a searchable list of containers backed by a
/// `DockerStore`. Mirrors `DashboardView`'s state switch, `.refreshable`,
/// and `.pollingRefresh(isActive:)` — see that file's doc comment for why
/// each exists.
struct DockerListView: View {
  @Bindable var store: DockerStore
  @Binding var isShowingSettings: Bool
  /// Presented by the toolbar bell, which every tab carries.
  @Binding var isShowingNotifications: Bool
  /// The bell's badge, `nil` when nothing is unread. Passed down rather than read
  /// from a store here: `RootView` owns the one `NotificationStore`, and a tab
  /// that doesn't otherwise care about notifications shouldn't have to know it
  /// exists.
  let unreadCount: Int?
  /// Whether the Docker tab is the one currently on screen — drives
  /// `.pollingRefresh`, so a backgrounded tab costs nothing rather than
  /// polling unseen. Matches `DashboardView.isSelected`.
  let isSelected: Bool

  /// The selected container. **Owned by `RootView`**: the cross-link from a
  /// service opens a container, and that means something above both tabs has
  /// to be able to set it. Held outside `ListDetailScaffold`, so it survives
  /// the width class changing under it.
  ///
  /// An identifier rather than a `Container`. The compact layout tracks it
  /// too, not only the split one.
  @Binding var selection: Container.ID?
  /// The service configured against a container, when one matches.
  var linkedService: (Container) -> ServiceInstance? = { _ in nil }
  /// Opens that service's screen, in the Services tab.
  var openService: (ServiceInstance) -> Void = { _ in }

  var body: some View {
    ListDetailScaffold(
      selection: $selection,
      placeholder: ListDetailPlaceholder(
        title: "No Container Selected",
        systemImage: "shippingbox",
        description: "Pick a container from the list to see its status, ports, and actions.",
        identifier: "docker.noSelection"
      )
    ) { isSplit in
      content(isSplit: isSplit)
        .navigationTitle("Docker")
        .searchable(text: $store.searchText, prompt: "Search containers")
        .modifier(
          TowerToolbarModifier(
            isShowingNotifications: $isShowingNotifications,
            isShowingSettings: $isShowingSettings,
            unreadCount: unreadCount
          )
        )
    } detail: { containerID in
      // Identifier, not value. `ContainerDetailView` re-resolves
      // the container from `store` on every render, so this closure doesn't
      // need to (and can't, without reaching back into the store itself)
      // capture anything beyond which container it is. Mirrors
      // `DashboardView`'s `navigationDestination(for: ArrayDisk.ID.self)`.
      ContainerDetailView(
        store: store, containerID: containerID, linkedService: linkedService,
        openService: openService)
        // `ContainerLogsRoute`, not `Container.ID` again — see its own doc
        // comment for why reusing the destination above would be
        // ambiguous. `store.makeLogsStore(containerID:)` is safe to call
        // inline here even though this closure re-runs on every poll:
        // `ContainerLogsView` owns the resulting store via `@State`, which
        // only actually installs it the first time this destination's
        // identity is seen — see that view's own doc comment.
        //
        // Declared on the detail view rather than beside the list: that puts
        // it inside the detail column's stack on iPad and inside the single
        // stack on iPhone, which is where the push happens in each layout.
        .navigationDestination(for: ContainerLogsRoute.self) { route in
          ContainerLogsView(
            store: store.makeLogsStore(containerID: route.containerID),
            containerName: route.containerName
          )
        }
    }
    // Interval omitted — see `Duration.towerPoll`.
    .pollingRefresh(isActive: isSelected) { await store.refresh() }
  }

  @ViewBuilder
  private func content(isSplit: Bool) -> some View {
    switch store.state {
    case .idle, .loading:
      LoadingStateView(title: "Loading containers…", isLoadInFlight: store.isLoadInFlight) {
        store.cancelLoad()
      }
    case .failed(let error):
      // Same shape as `DashboardView`'s error branch — see its doc comment
      // for why the retry button is a sibling of `ContentUnavailableView`
      // rather than passed as its `actions:` closure.
      VStack(spacing: 16) {
        if case .serviceUnavailable = error {
          // The Docker service is off. Its own state, worded like
          // `VMListView`'s `vms.unavailable`, not the generic error screen:
          // nothing went wrong that the user needs to diagnose, and not "No
          // Containers", which would be a claim about a server Tower cannot
          // read. A failure, not an empty list, because `Docker.containers`
          // is non-null and the server can only say this by throwing.
          ContentUnavailableView(
            "Docker Unavailable",
            systemImage: "shippingbox",
            description: Text("This server isn't reporting Docker containers. The Docker service may be disabled or stopped.")
          )
          .accessibilityIdentifier("docker.unavailable")
        } else {
          ContentUnavailableView {
            Label(error.message, systemImage: "exclamationmark.triangle")
          } description: {
            if let suggestion = error.recoverySuggestion { Text(suggestion) }
          }
          .accessibilityElement(children: .combine)
          .accessibilityIdentifier("docker.error")
        }

        Button("Try Again") { Task { await store.load() } }
          .accessibilityIdentifier("docker.retry")
      }
    case .loaded(let containers), .actionFailed(let containers, _):
      containerList(containers, isSplit: isSplit)
    }
  }

  @ViewBuilder
  private func containerList(_ containers: [Container], isSplit: Bool) -> some View {
    // Always a `List`, even when it ends up empty: `.refreshable` below
    // needs a scrollable container underneath it to produce a working pull
    // gesture at all — a bare `ContentUnavailableView` outside a `List`/
    // `ScrollView` has nothing for the gesture to attach to. Matches
    // `DashboardView`, which keeps `.refreshable` on the whole loaded
    // branch regardless of whether the cards inside are empty, so a server
    // with genuinely zero containers still gets a manual refresh gesture
    // rather than being stuck until the next poll.
    // `selection:` only in the split layout — passing the binding on iPhone
    // too puts the `List` in selection mode, where it *consumes* the row tap
    // and the `NavigationLink` inside never pushes. That is not a crash and
    // not a slow screen: the tap simply does nothing.
    List(selection: isSplit ? $selection : nil) {
      // `.actionFailed` exists so a failed poll/refresh keeps showing the
      // last good list *and* surfaces the error — silently swallowing it
      // here would defeat the entire point of the case.
      if case .actionFailed(_, let error) = store.state {
        Text(error.message)
          .font(.caption)
          .foregroundStyle(.red)
      }
      ForEach(store.filteredContainers) { container in
        // Carries the identifier, not the `Container` value itself.
        // The scaffold's `detail` closure re-resolves this container
        // from the store on every render, so a poll (or an action fired from
        // the detail screen) reaches it instead of freezing it at today's
        // snapshot. `listDetailRow` is what turns this into a pushing
        // `NavigationLink` on iPhone and a selectable row on iPad; the row's
        // own `.swipeActions`/`.contextMenu`/`.confirmationDialog` stay
        // attached inside `ContainerRow`'s body and are unaffected either way.
        ContainerRow(
          container: container,
          isInFlight: store.inFlight.contains(container.id)
        ) { action in
          Task { await store.perform(action, on: container) }
        }
        .listDetailRow(id: container.id, isSplit: isSplit)
      }
    }
    // Only a real, user-triggered mutation buzzes — `store.perform(_:on:)`
    // is the only place that bumps either counter, never `load()`/
    // `refresh()`, so a background poll (or pull-to-refresh) stays silent.
    .sensoryFeedback(.success, trigger: store.lastActionSuccess)
    .sensoryFeedback(.error, trigger: store.lastActionFailure)
    .overlay {
      // Two distinct empty states, deliberately not conflated: a server
      // with zero containers reads differently from a search that matched
      // nothing. Telling a user with 24 containers "you have none" because
      // their query for "audio" matched zero of them would be a lie about
      // their server.
      if containers.isEmpty {
        ContentUnavailableView(
          "No Containers", systemImage: "shippingbox",
          description: Text("This server has no Docker containers.")
        )
        .accessibilityIdentifier("docker.empty")
      } else if store.filteredContainers.isEmpty {
        // `.search` (no explicit text) reads the query straight out of this
        // view's own `.searchable` environment — the same pattern used in
        // Apple's own reference examples for a searchable `List`.
        ContentUnavailableView.search
      }
    }
    .refreshable { await store.refresh() }
  }
}

// No `#Preview` here, matching `DashboardView`: previewing a store-backed
// top-level screen needs a full repository fixture for little benefit over
// the sub-views (`ContainerRow`, `StateDot`) that already preview on their
// own — see their files for those.
