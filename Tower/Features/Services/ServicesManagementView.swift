import SwiftUI
import TowerCore

/// Settings → Services: every configured instance, including the disabled ones
/// the hub hides, with the same edit / disable / delete / reorder actions.
///
/// The hub is where services are *used*, so it lists only what is switched on.
/// This is where they are *managed*, so it lists everything — otherwise
/// disabling a service from the hub would make it unreachable from the UI, and
/// the "keeps its configuration" half of disable would be a promise with no way
/// to collect on it.
struct ServicesManagementView: View {
  let store: ServicesStore

  @State private var formStore: ServiceFormStore?
  @State private var pendingDeletion: ServiceInstance?

  var body: some View {
    List {
      ForEach(store.instances) { instance in
        row(instance)
          .modifier(
            ServiceInstanceActions(
              instance: instance,
              onEdit: { formStore = store.makeEditStore(for: instance) },
              onToggleEnabled: { Task { await store.setEnabled(!instance.isEnabled, for: instance) } },
              onDelete: { pendingDeletion = instance }
            )
          )
      }
      .onMove { store.move(store.instances.map(\.id), from: $0, to: $1) }
    }
    .overlay {
      if store.instances.isEmpty {
        ContentUnavailableView(
          "No Services", systemImage: "square.stack.3d.up",
          description: Text("Services you add appear here.")
        )
        .accessibilityIdentifier("manageServices.empty")
      }
    }
    .navigationTitle("Services")
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        EditButton()
          .accessibilityIdentifier("manageServices.edit")
      }
      ToolbarItem(placement: .topBarTrailing) {
        Button("Add Service", systemImage: "plus") { formStore = store.makeServiceFormStore() }
          .accessibilityIdentifier("manageServices.add")
      }
    }
    .sheet(item: $formStore) { form in
      ServiceFormSheet(store: form) { saved in
        Task { await store.adopt(saved) }
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
      .accessibilityElement(children: .combine)
      .accessibilityIdentifier("manageServices.confirmDelete")
      Button("Cancel", role: .cancel) { pendingDeletion = nil }
    } message: {
      Text("Its address and credentials are removed from the keychain. This can't be undone.")
    }
  }

  private func row(_ instance: ServiceInstance) -> some View {
    HStack {
      Label(instance.name, systemImage: instance.kind.systemImage)
      Spacer()
      // Disabled is a state a user has to be able to see here, since it is the
      // reason the row is missing from the hub.
      Text(instance.isEnabled ? instance.kind.displayName : "Disabled")
        .font(.caption)
        .foregroundStyle(.secondary)
    }
    .accessibilityElement(children: .combine)
    .accessibilityLabel(
      "\(instance.name), \(instance.kind.displayName)\(instance.isEnabled ? "" : ", disabled")")
    .accessibilityIdentifier("manageServices.row.\(instance.id.uuidString)")
  }
}
