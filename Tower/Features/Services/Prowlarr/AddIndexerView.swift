import SwiftUI
import TowerCore

/// Pick a definition, then fill in the form Prowlarr describes.
struct AddIndexerView: View {
  @Bindable var store: AddIndexerStore
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      Group {
        if store.draft == nil {
          definitionPicker
        } else {
          configurationForm
        }
      }
      .navigationTitle(store.draft?.schema.definitionName ?? "Add Indexer")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar { toolbar }
      .task {
        guard store.state.value == nil else { return }
        await store.load()
      }
    }
  }

  @ToolbarContentBuilder
  private var toolbar: some ToolbarContent {
    ToolbarItem(placement: .cancellationAction) {
      if store.draft == nil {
        Button("Cancel") { dismiss() }
      } else {
        // Back to the list rather than out of the sheet: picking the wrong
        // definition is a normal mistake and shouldn't cost the whole flow.
        Button("Back") { store.cancelDraft() }
          .accessibilityIdentifier("prowlarr.add.back")
      }
    }
    if store.draft != nil {
      ToolbarItem(placement: .confirmationAction) {
        Button("Save") {
          Task { if await store.save() { dismiss() } }
        }
        .disabled(!store.canSave)
        .accessibilityIdentifier("prowlarr.add.save")
      }
    }
  }

  // MARK: - Definition picker

  @ViewBuilder
  private var definitionPicker: some View {
    switch store.state {
    case .idle, .loading:
      ProgressView("Loading definitions…")
    case .failed(let error):
      ContentUnavailableView {
        Label(error.message, systemImage: "exclamationmark.triangle")
      } description: {
        if let suggestion = error.serviceRecoverySuggestion { Text(suggestion) }
      }
      .accessibilityIdentifier("prowlarr.add.error")
    case .loaded(let schemas), .actionFailed(let schemas, _):
      List(store.filteredSchemas) { schema in
        Button {
          store.choose(schema)
        } label: {
          VStack(alignment: .leading, spacing: 3) {
            Text(schema.definitionName)
              .font(.body)
            HStack(spacing: 6) {
              Text(schema.privacy.displayName)
              if let label = schema.downloadProtocol.displayName {
                Text("·")
                Text(label)
              }
              if let language = schema.language {
                Text("·")
                Text(language)
              }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            if let description = schema.description {
              Text(description)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            }
          }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("prowlarr.add.definition.\(schema.definitionName)")
      }
      .searchable(text: $store.searchText, prompt: "Search definitions")
      .overlay {
        if schemas.isEmpty {
          ContentUnavailableView(
            "No Definitions", systemImage: "questionmark.folder",
            description: Text("Prowlarr reported no indexer definitions.")
          )
          .accessibilityIdentifier("prowlarr.add.noDefinitions")
        } else if store.filteredSchemas.isEmpty {
          ContentUnavailableView.search
        }
      }
    }
  }

  // MARK: - Generated form

  @ViewBuilder
  private var configurationForm: some View {
    if let draft = store.draft {
      Form {
        Section {
          LabeledContent("Name") {
            TextField(
              "Name", text: Binding(get: { draft.name }, set: { store.setName($0) })
            )
            .multilineTextAlignment(.trailing)
            .accessibilityIdentifier("prowlarr.add.name")
          }
          Toggle(
            "Enabled",
            isOn: Binding(get: { draft.isEnabled }, set: { store.setEnabled($0) })
          )
          .accessibilityIdentifier("prowlarr.add.enabled")
        }

        Section("Configuration") {
          ForEach(store.renderableFields) { field in
            IndexerFieldEditor(field: field) { store.setValue($0, for: field) }
          }
        }

        // **Reported, not dropped.** A required field silently omitted saves an
        // indexer that never works, with nothing on screen explaining why.
        if store.hasUnsupportedFields {
          Section {
            Label(
              "Tower can't show \(store.unsupportedFields.count) setting"
                + "\(store.unsupportedFields.count == 1 ? "" : "s") for this indexer.",
              systemImage: "exclamationmark.triangle")
              .foregroundStyle(.orange)
            ForEach(store.unsupportedFields) { field in
              Text(field.label)
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Text("Save here, then finish setting it up in Prowlarr's web UI.")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
          .accessibilityIdentifier("prowlarr.add.unsupported")
        }

        Section {
          Button("Test") { Task { await store.test() } }
            .disabled(store.isTesting || store.isSaving)
            .accessibilityIdentifier("prowlarr.add.test")

          if let result = store.testResult {
            HStack(alignment: .top, spacing: 6) {
              Image(
                systemName: result.isSuccess ? "checkmark.circle.fill" : "xmark.octagon.fill")
              VStack(alignment: .leading, spacing: 2) {
                Text(result.isSuccess ? "Test passed" : "Test failed")
                // Prowlarr's own words — it explains a wrong cookie better
                // than any rewording here.
                ForEach(result.messages, id: \.self) { message in
                  Text(message).foregroundStyle(.secondary)
                }
              }
            }
            .font(.caption)
            .foregroundStyle(result.isSuccess ? Color.green : Color.red)
            .accessibilityIdentifier("prowlarr.add.testResult")
          }
        }

        if let error = store.saveError {
          Section {
            Text(error.message)
              .font(.caption)
              .foregroundStyle(.red)
              .accessibilityIdentifier("prowlarr.add.saveError")
          }
        }
      }
      .overlay {
        if store.isSaving || store.isTesting { ProgressView().controlSize(.large) }
      }
    }
  }
}

/// Renders one schema field. The whole point of `FieldKind`.
struct IndexerFieldEditor: View {
  let field: IndexerField
  let setValue: (FieldValue) -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      editor
      if let helpText = field.helpText {
        Text(helpText)
          .font(.caption2)
          .foregroundStyle(.secondary)
      }
    }
    .accessibilityIdentifier("prowlarr.field.\(field.name)")
  }

  @ViewBuilder
  private var editor: some View {
    switch field.kind {
    case .textbox, .textArea:
      LabeledContent(field.label) {
        TextField(
          field.label,
          text: Binding(get: { field.value.stringValue }, set: { setValue(.text($0)) })
        )
        .multilineTextAlignment(.trailing)
        .autocorrectionDisabled()
        .textInputAutocapitalization(.never)
      }

    case .password:
      LabeledContent(field.label) {
        // Obscured, and never logged — the same rule the credential handling
        // follows everywhere else in this app.
        SecureField(
          field.label,
          text: Binding(get: { field.value.stringValue }, set: { setValue(.text($0)) })
        )
        .multilineTextAlignment(.trailing)
      }

    case .number:
      LabeledContent(field.label) {
        TextField(
          field.label,
          text: Binding(
            get: { field.value.stringValue },
            set: { setValue(Double($0).map(FieldValue.number) ?? .text($0)) })
        )
        .keyboardType(.numbersAndPunctuation)
        .multilineTextAlignment(.trailing)
      }

    case .checkbox:
      Toggle(
        field.label,
        isOn: Binding(get: { field.value.boolValue }, set: { setValue(.boolean($0)) }))

    case .select:
      Picker(
        field.label,
        selection: Binding(
          get: { field.value.intValue ?? field.options.first?.value ?? 0 },
          set: { setValue(.option($0)) })
      ) {
        ForEach(field.options) { option in
          Text(option.name).tag(option.value)
        }
      }

    case .tag:
      LabeledContent(field.label) {
        // Comma-separated, which is how Prowlarr's own UI presents these.
        TextField(
          "comma, separated",
          text: Binding(
            get: { field.value.stringValue },
            set: { raw in
              let parts = raw.split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
              setValue(parts.isEmpty ? .empty : .list(parts))
            })
        )
        .multilineTextAlignment(.trailing)
        .autocorrectionDisabled()
      }

    case .unknown:
      // Never reached — the store filters these out and reports them
      // separately — but a switch that silently rendered nothing here is
      // exactly the failure this design is avoiding, so it says so.
      Label("\(field.label) isn't supported here", systemImage: "questionmark.circle")
        .foregroundStyle(.orange)
    }
  }
}
