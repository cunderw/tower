import SwiftUI
import TowerCore

/// The Services tab root: configured instances grouped by category, each with a
/// live status line, pushing that instance's screen.
///
/// Uses the same `ListDetailScaffold` as Docker/VMs/Shares, so iPad gets the
/// list-plus-detail layout for free and iPhone keeps the push-based stack.
struct ServicesHubView: View {
  let store: ServicesStore
  /// Builds the repository for an instance — how a row knows whether it can
  /// open a service shell or only the configuration screen.
  let makeRepository: ServiceRepositoryFactory
  /// Keeps each service's store alive across navigation — forwarded to
  /// the detail rather than owned here, because the hub is itself rebuilt.
  let serviceStores: ServiceStoreRegistry
  /// The Docker container running an instance, when one matches.
  var containerRunning: (ServiceInstance) -> Container? = { _ in nil }
  /// Opens that container's screen, in the Docker tab.
  var openContainer: (Container) -> Void = { _ in }
  /// Makes sure the container list has been fetched at least once.
  ///
  /// Without this the cross-link only appeared **after** the user had visited
  /// the Docker tab, because that is what loads the list the match is made
  /// against — a link that works or not depending on where you have been is
  /// worse than one that is simply absent. Costs one query, on a screen that
  /// already fans out a status check per configured service.
  var ensureContainersLoaded: () async -> Void = {}
  @Binding var isShowingSettings: Bool
  @Binding var isShowingNotifications: Bool
  let unreadCount: Int?
  /// Whether this tab is on screen — the status re-check follows tab selection
  /// rather than running for a tab nobody is looking at.
  let isSelected: Bool

  /// **Owned by `RootView`**, so a container's "open this service" link can
  /// set it.
  @Binding var selection: UUID?
  /// Built fresh for each presentation, so a cancelled add leaves no half-typed
  /// key sitting in memory behind the hub.
  @State private var addServiceStore: ServiceFormStore?
  /// The instance a delete confirmation is pending for. Held rather than a
  /// bare `Bool` so the dialog can name what it is about to remove — a
  /// confirmation that doesn't say *which* service is barely a confirmation.
  @State private var pendingDeletion: ServiceInstance?

  var body: some View {
    ListDetailScaffold(
      selection: $selection,
      placeholder: ListDetailPlaceholder(
        title: "No Service Selected",
        systemImage: "square.stack.3d.up",
        description: "Pick a service to see its status.",
        identifier: "services.noSelection"
      )
    ) { isSplit in
      content(isSplit: isSplit)
        .navigationTitle("Services")
        .modifier(
          TowerToolbarModifier(
            isShowingNotifications: $isShowingNotifications,
            isShowingSettings: $isShowingSettings,
            unreadCount: unreadCount
          )
        )
        .toolbar {
          ToolbarItem(placement: .topBarLeading) {
            Button("Add Service", systemImage: "plus") { presentAddService() }
              .accessibilityIdentifier("services.add")
          }
        }
    } detail: { instanceID in
      // Identifier, not value. The instance is re-resolved from the
      // store on every render, so an edit or a re-check reaches this screen.
      if let instance = store.instance(id: instanceID) {
        ArrServiceScreen(
          instance: instance, servicesStore: store, makeRepository: makeRepository,
          serviceStores: serviceStores)
      } else {
        ContentUnavailableView(
          "Service Removed", systemImage: "trash",
          description: Text("This service is no longer configured.")
        )
        .accessibilityIdentifier("services.detail.missing")
      }
    }
    .sheet(item: $addServiceStore) { addStore in
      ServiceFormSheet(store: addStore) { saved in
        Task { await store.adopt(saved) }
      }
    }
    // A first load on appear, then a re-check whenever the tab comes back into
    // view. Not `.pollingRefresh`: this is N remote calls across N services, and
    // repeating them on a timer would put the whole media stack under a poll
    // Tower's own dashboard doesn't justify.
    .task(id: isSelected) {
      guard isSelected else { return }
      await ensureContainersLoaded()
      await store.load()
    }
  }

  private func presentAddService() {
    addServiceStore = store.makeServiceFormStore()
  }

  @ViewBuilder
  private func content(isSplit: Bool) -> some View {
    List(selection: isSplit ? $selection : nil) {
      if let error = store.directoryError {
        // The keychain read failed — not the same thing as a service being
        // down, and the only case where the list itself can't be trusted.
        Text(error.message)
          .font(.caption)
          .foregroundStyle(.red)
          .accessibilityIdentifier("services.directoryError")
      }
      ForEach(store.groups) { group in
        Section(group.category.displayName) {
          ForEach(group.instances) { instance in
            ServiceInstanceRow(instance: instance, status: store.status(for: instance))
              .listDetailRow(id: instance.id, isSplit: isSplit)
              .modifier(
                ServiceInstanceActions(
                  instance: instance,
                  onEdit: { addServiceStore = store.makeEditStore(for: instance) },
                  onToggleEnabled: { Task { await store.setEnabled(!instance.isEnabled, for: instance) } },
                  onDelete: { pendingDeletion = instance },
                  // Absent unless a container actually matches — see the
                  // modifier's note on why no link beats a wrong one.
                  onOpenContainer: containerRunning(instance).map { container in
                    { openContainer(container) }
                  }
                )
              )
          }
          .onMove { store.move(group.instances.map(\.id), from: $0, to: $1) }
        }
      }
    }
    .overlay {
      if store.isEmpty {
        ContentUnavailableView {
          Label("No Services", systemImage: "square.stack.3d.up")
        } description: {
          Text("Add Radarr, Sonarr, NZBGet, and the rest of your media stack to manage them from Tower.")
        } actions: {
          // No identifier of its own: `ContentUnavailableView` propagates the
          // container's identifier over every child, so one set here would be
          // overwritten by `services.empty` below and a test querying it would
          // never match (CLAUDE.md, "`ContentUnavailableView` overwrites its
          // children's identifiers"). The button
          // is addressed as *the button* carrying `services.empty`.
          Button("Add Service") { presentAddService() }
        }
        .accessibilityIdentifier("services.empty")
      }
    }
    .refreshable { await store.load() }
    .toolbar {
      // Reordering is a list-edit affordance, so it goes where every other
      // list in iOS puts it rather than behind a bespoke control.
      ToolbarItem(placement: .topBarTrailing) {
        EditButton()
          .accessibilityIdentifier("services.edit")
      }
    }
    .confirmationDialog(
      pendingDeletion.map { "Delete \($0.name)?" } ?? "Delete Service?",
      isPresented: Binding(get: { pendingDeletion != nil }, set: { if !$0 { pendingDeletion = nil } }),
      titleVisibility: .visible
    ) {
      Button("Delete", role: .destructive) {
        if let pendingDeletion { store.delete(pendingDeletion) }
        pendingDeletion = nil
      }
      // `.combine` for the same reason `SettingsSheet`'s sign-out button needs
      // it: without it the button surfaces as two nodes sharing one identifier.
      .accessibilityElement(children: .combine)
      .accessibilityIdentifier("services.confirmDelete")
      Button("Cancel", role: .cancel) { pendingDeletion = nil }
    } message: {
      Text("Its address and credentials are removed from the keychain. This can't be undone.")
    }
  }
}

/// Swipe actions and the context menu for one service row, applied as a
/// modifier so the hub and Settings → Services offer exactly the same set —
/// "findable in both places" meaning the same actions, not two lists that have
/// drifted apart.
struct ServiceInstanceActions: ViewModifier {
  let instance: ServiceInstance
  let onEdit: () -> Void
  let onToggleEnabled: () -> Void
  let onDelete: () -> Void
  /// Opens the Docker container running this service. **`nil` when
  /// there is no match** — no Unraid server attached, the container list
  /// unavailable, or an address that does not correspond to any container —
  /// and the action is then absent rather than present-and-inert.
  ///
  /// Lives on this shared modifier rather than on a service screen because
  /// there is no per-service detail screen every kind reaches: `ArrServiceScreen`
  /// resolves each kind to its own shell, and `ServiceInstanceDetailView` is
  /// only the fallback for a kind with no client. The row is the one place every
  /// kind has in common, and it is already where the other three actions live.
  var onOpenContainer: (() -> Void)?

  func body(content: Content) -> some View {
    content
      .swipeActions(edge: .trailing) {
        Button("Delete", systemImage: "trash", role: .destructive, action: onDelete)
          .accessibilityIdentifier("services.row.\(instance.id.uuidString).delete")
      }
      .swipeActions(edge: .leading) {
        Button(
          instance.isEnabled ? "Disable" : "Enable",
          systemImage: instance.isEnabled ? "pause.circle" : "play.circle",
          action: onToggleEnabled
        )
        .tint(instance.isEnabled ? .orange : .green)
        .accessibilityIdentifier("services.row.\(instance.id.uuidString).toggle")
        if let onOpenContainer {
          Button("Container", systemImage: "shippingbox", action: onOpenContainer)
            .tint(.blue)
            .accessibilityIdentifier("services.row.\(instance.id.uuidString).container")
        }
      }
      .contextMenu {
        // The same three actions, reachable without a swipe — the discoverable
        // path, and the only one on a row that is already open in the split
        // layout's detail column.
        Button("Edit", systemImage: "pencil", action: onEdit)
        Button(
          instance.isEnabled ? "Disable" : "Enable",
          systemImage: instance.isEnabled ? "pause.circle" : "play.circle",
          action: onToggleEnabled
        )
        Button("Delete", systemImage: "trash", role: .destructive, action: onDelete)
        if let onOpenContainer {
          Button("Open Container", systemImage: "shippingbox", action: onOpenContainer)
        }
      }
  }
}
