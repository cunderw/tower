import SwiftUI
import TowerCore

/// The service form, for adding a service and for editing one. Adding is
/// presented from the hub's toolbar and from Settings; editing from a service's
/// row, in the hub or in Settings, and from its configuration screen.
///
/// The credential fields are driven by `kind.credentialStyle`, so the form can
/// never show a field the selected service has no use for — there is no "API
/// key" row on an NZBGet, and no password on a Radarr.
struct ServiceFormSheet: View {
  @Bindable var store: ServiceFormStore
  /// Called with the saved instance so the hub can refresh and show it.
  let onSaved: (ServiceInstance) -> Void

  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      Form {
        candidatesSection
        serviceSection
        addressSection
        credentialsSection
        headersSection
        testSection
        if let error = store.saveError {
          Text(error.message)
            .foregroundStyle(.red)
            .accessibilityIdentifier("addService.saveError")
        }
      }
      .task { await store.loadCandidates() }
      .navigationTitle(store.isEditing ? "Edit Service" : "Add Service")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { dismiss() }
            .accessibilityIdentifier("addService.cancel")
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Save") {
            if let saved = store.save() {
              onSaved(saved)
              dismiss()
            }
          }
          .disabled(!store.canSubmit)
          .accessibilityIdentifier("addService.save")
        }
      }
    }
  }

  /// Absent entirely when nothing was recognised, rather than an empty section
  /// explaining that nothing was recognised.
  @ViewBuilder
  private var candidatesSection: some View {
    if !store.candidates.isEmpty {
      Section {
        ForEach(store.candidates) { candidate in
          Button {
            store.apply(candidate)
          } label: {
            HStack {
              Label(candidate.containerName, systemImage: candidate.kind.systemImage)
              Spacer()
              Text(candidate.baseURL.absoluteString)
                .font(.caption)
                .foregroundStyle(.secondary)
            }
          }
          .accessibilityIdentifier("addService.candidate.\(candidate.id)")
        }
      } header: {
        Text("Found on Your Server")
      } footer: {
        // Says plainly what is and is not filled in, so nobody wonders whether
        // Tower went looking for their key. Deliberately not "you still paste
        // the API key or password" — some services need neither, and
        // the point of this line is that Tower never reads a credential from a
        // container, not that one is always required.
        Text("Fills in the address only. Tower never reads a credential from a container.")
      }
    }
  }

  private var serviceSection: some View {
    Section("Service") {
      Picker("Type", selection: $store.kind) {
        ForEach(ServiceKind.allCases, id: \.self) { kind in
          Label(kind.displayName, systemImage: kind.systemImage).tag(kind)
        }
      }
      .accessibilityIdentifier("addService.kind")

      TextField("Name", text: $store.name)
        .accessibilityIdentifier("addService.name")
    }
  }

  private var addressSection: some View {
    Section {
      TextField("http://10.0.0.1:7878", text: $store.urlText)
        .textContentType(.URL)
        .keyboardType(.URL)
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .onChange(of: store.urlText) { _, _ in store.inputChanged() }
        .accessibilityIdentifier("addService.url")
    } header: {
      Text("Address")
    } footer: {
      Text("Include the port, and any path your reverse proxy adds.")
    }
  }

  @ViewBuilder
  private var credentialsSection: some View {
    Section {
      switch store.kind.credentialStyle {
      case .apiKey:
        // `SecureField`, and never rendered back as plain text anywhere — the
        // key goes to the keychain and nowhere else.
        SecureField("API Key", text: $store.apiKey)
          .textInputAutocapitalization(.never)
          .autocorrectionDisabled()
          .onChange(of: store.apiKey) { _, _ in store.inputChanged() }
          .accessibilityIdentifier("addService.apiKey")
      case .usernamePassword:
        TextField("Username", text: $store.username)
          .textContentType(.username)
          .textInputAutocapitalization(.never)
          .autocorrectionDisabled()
          .onChange(of: store.username) { _, _ in store.inputChanged() }
          .accessibilityIdentifier("addService.username")
        SecureField("Password", text: $store.password)
          .textContentType(.password)
          .onChange(of: store.password) { _, _ in store.inputChanged() }
          .accessibilityIdentifier("addService.password")
      }
    } header: {
      Text("Credentials")
    } footer: {
      Text(credentialsFooter)
    }
  }

  private var credentialsFooter: String {
    switch store.kind.credentialStyle {
    case .apiKey:
      "Find the API key in \(store.kind.displayName)'s own settings. It is stored in the iOS keychain."
    case .usernamePassword:
      // The "leave blank" sentence is load-bearing, not reassurance.
      // NZBGet is commonly run without a sign-in (no control username or
      // password), and a footer that only describes the credentialled case
      // reads as a requirement.
      """
      The same credentials you use to sign in to \(store.kind.displayName), \
      or leave both blank if it doesn't ask for one. They are stored in the \
      iOS keychain.
      """
    }
  }

  private var headersSection: some View {
    Section {
      ForEach($store.customHeaders) { $header in
        VStack(alignment: .leading, spacing: 4) {
          TextField("Header", text: $header.field)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
          TextField("Value", text: $header.value)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .font(.caption)
        }
      }
      .onDelete { store.removeHeaders(at: $0) }

      Button("Add Header", systemImage: "plus") { store.addHeader() }
        .accessibilityIdentifier("addService.addHeader")
    } header: {
      Text("Custom Headers")
    } footer: {
      Text("Optional. For reverse proxies that need their own authentication headers.")
    }
  }

  private var testSection: some View {
    Section {
      Button {
        Task { await store.test() }
      } label: {
        if store.isTesting {
          Label("Testing…", systemImage: "progress.indicator")
        } else {
          Label("Test Connection", systemImage: "bolt.horizontal")
        }
      }
      .disabled(!store.canSubmit || store.isTesting)
      .accessibilityIdentifier("addService.test")

      if let result = store.testResult {
        VStack(alignment: .leading, spacing: 4) {
          Label(result.testHeadline, systemImage: result.isReachable ? "checkmark.circle" : "xmark.circle")
            .foregroundStyle(result.isReachable ? .green : .red)
          if let detail = result.testDetail {
            Text(detail)
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        }
        // One VoiceOver stop carrying the whole outcome, not a glyph plus two
        // fragments — and the wording, not the colour, is what says which
        // failure it was.
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("addService.testResult")
      }
    } footer: {
      if let message = store.validationMessage {
        Text(message)
          .accessibilityIdentifier("addService.validation")
      }
    }
  }
}
