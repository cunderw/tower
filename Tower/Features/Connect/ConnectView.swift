import SwiftUI
import TowerCore

struct ConnectView: View {
  @Bindable var store: ConnectStore
  var onConnected: (Server) -> Void
  /// Switches the app into demo mode. Separate from `onConnected` because it
  /// swaps the whole `AppEnvironment`, which only `TowerApp` can do.
  var onTryDemo: () -> Void

  var body: some View {
    NavigationStack {
      Form {
        Section {
          // A shaped hint rather than a working address. iOS renders a real,
          // fully-formed URL placeholder in the accent tint under
          // `.textContentType(.URL)` — the "API key" field below shows what
          // an untinted placeholder looks like — and blue and complete, it
          // reads as a value already entered rather than an empty field. The
          // angle brackets keep it from parsing as a URL at all, which is
          // both what makes it legible as a template and what drops the tint.
          TextField("http://<unraid-ip>:<port>", text: $store.urlText)
            .textContentType(.URL)
            .keyboardType(.URL)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .accessibilityIdentifier("connect.url")

          SecureField("API key", text: $store.apiKey)
            .textContentType(.password)
            .accessibilityIdentifier("connect.apiKey")
        } header: {
          Text("Server")
        } footer: {
          Text("Create an API key in Unraid under Settings ▸ Management Access.")
        }

        if let error = store.state.error {
          Section {
            ContentUnavailableView {
              Label(error.message, systemImage: "exclamationmark.triangle")
            } description: {
              if let suggestion = error.recoverySuggestion {
                Text(suggestion)
              }
            }
            // Without `.combine`, SwiftUI treats ContentUnavailableView's
            // label and description as separate accessibility elements and
            // pushes `.accessibilityIdentifier` down onto BOTH of them —
            // two elements sharing one identifier, unreachable
            // deterministically by a UI test. `.combine` merges them into a
            // single element the identifier can actually attach to.
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("connect.error")
          }
        }

        Section {
          Button {
            Task { await store.connect() }
          } label: {
            if store.state.isLoading {
              ProgressView()
                .frame(maxWidth: .infinity)
            } else {
              Text("Connect")
                .frame(maxWidth: .infinity)
            }
          }
          .disabled(!store.canSubmit)
          .accessibilityIdentifier("connect.submit")
        }

        Section {
          Button("Try the Demo", action: onTryDemo)
            .frame(maxWidth: .infinity)
            .accessibilityIdentifier("connect.demo")
        } footer: {
          Text("Explore Tower with a sample server. Nothing is saved, and no connection is made.")
        }
      }
      .navigationTitle("Connect to Tower")
      .onChange(of: store.state.value) { _, server in
        if let server { onConnected(server) }
      }
    }
  }
}
