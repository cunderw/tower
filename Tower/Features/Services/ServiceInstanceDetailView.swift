import SwiftUI
import TowerCore

/// What a hub row pushes when the repository factory returns no client for the
/// service's kind.
///
/// Every kind has a live and a demo client, so the shipping app does not reach
/// this screen. The UI-test factory builds only Radarr and Sonarr, so the other
/// kinds land here in UI tests. It is a real screen rather than a stub: it shows
/// the record the user configured and the live result of the health check.
/// Resolved from the store by id on every render, so an edit or a re-check while
/// it is open is reflected here.
struct ServiceInstanceDetailView: View {
  let store: ServicesStore
  let instanceID: UUID

  @State private var editStore: ServiceFormStore?

  var body: some View {
    Group {
      if let instance = store.instance(id: instanceID) {
        content(for: instance)
      } else {
        // The instance was deleted while its detail was open.
        ContentUnavailableView(
          "Service Removed", systemImage: "trash",
          description: Text("This service is no longer configured.")
        )
        .accessibilityIdentifier("services.detail.missing")
      }
    }
  }

  @ViewBuilder
  private func content(for instance: ServiceInstance) -> some View {
    List {
      Section("Status") {
        LabeledContent("State") {
          Text(store.status(for: instance)?.summary ?? "Checking…")
            .foregroundStyle(store.status(for: instance)?.isProblem == true ? .red : .secondary)
        }
        .accessibilityIdentifier("services.detail.status")

        if let suggestion = store.status(for: instance)?.error?.serviceRecoverySuggestion {
          Text(suggestion)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }

      Section("Configuration") {
        LabeledContent("Service", value: instance.kind.displayName)
        LabeledContent("Address", value: instance.baseURL.absoluteString)
        // Never the credential itself, not even masked in a way that leaks its
        // length — the keychain is where it lives and the edit sheet is
        // the only place it is ever shown.
        LabeledContent("Authentication", value: authenticationSummary(instance))
      }
    }
    .navigationTitle(instance.name)
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        // Also on the row's swipe and context menu, but a screen showing a
        // service's configuration should be able to change it without sending
        // the user back to the list to find the gesture.
        Button("Edit", systemImage: "pencil") { editStore = store.makeEditStore(for: instance) }
          .accessibilityIdentifier("services.detail.edit")
      }
    }
    .sheet(item: $editStore) { form in
      ServiceFormSheet(store: form) { saved in
        Task { await store.adopt(saved) }
      }
    }
    .refreshable { await store.refreshStatuses() }
    .accessibilityIdentifier("services.detail")
  }

  private func authenticationSummary(_ instance: ServiceInstance) -> String {
    switch instance.credentials {
    case .apiKey: "API key"
    case .usernamePassword(let username, _): "Username \(username)"
    }
  }
}
