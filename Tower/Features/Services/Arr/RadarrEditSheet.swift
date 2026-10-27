import SwiftUI
import TowerCore

/// Edit one movie: monitored, quality profile, minimum availability, root
/// folder, tags. Every picker is fed from the instance itself.
struct RadarrEditSheet: View {
  @Bindable var store: RadarrEditStore
  let onSaved: () -> Void

  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      Form {
        Section {
          Toggle("Monitored", isOn: $store.edit.isMonitored)
            .accessibilityIdentifier("radarr.edit.monitored")
        }

        Section("Quality") {
          Picker("Quality profile", selection: $store.edit.qualityProfileID) {
            ForEach(store.options.qualityProfiles) { profile in
              Text(profile.name).tag(profile.id)
            }
          }
          .accessibilityIdentifier("radarr.edit.qualityProfile")

          Picker("Minimum availability", selection: $store.edit.minimumAvailability) {
            ForEach(MovieAvailability.selectableForMinimumAvailability, id: \.self) { option in
              Text(option.displayName).tag(option)
            }
          }
          .accessibilityIdentifier("radarr.edit.minimumAvailability")
        }

        Section("Location") {
          Picker("Root folder", selection: rootFolderBinding) {
            ForEach(store.options.rootFolders) { folder in
              Text(folder.path).tag(folder.path)
            }
          }
          .accessibilityIdentifier("radarr.edit.rootFolder")
        }

        if !store.options.tags.isEmpty {
          Section("Tags") {
            ForEach(store.options.tags) { tag in
              TagToggle(tag: tag, selection: $store.edit.tagIDs)
            }
          }
        }

        if let error = store.options.error {
          Text(error.message)
            .font(.caption)
            .foregroundStyle(.red)
            .accessibilityIdentifier("radarr.edit.optionsError")
        }
        if let error = store.saveError {
          Text(error.message)
            .foregroundStyle(.red)
            .accessibilityIdentifier("radarr.edit.saveError")
        }
      }
      .navigationTitle(store.movie.title)
      .navigationBarTitleDisplayMode(.inline)
      .task { await store.options.load() }
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { dismiss() }
            .accessibilityIdentifier("radarr.edit.cancel")
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Save") {
            Task {
              if await store.save() {
                onSaved()
                dismiss()
              }
            }
          }
          .disabled(!store.hasChanges || store.isSaving)
          .accessibilityIdentifier("radarr.edit.save")
        }
      }
    }
  }

  /// Root folder is optional on the model (a movie may predate one), but the
  /// picker needs a concrete selection — the movie's own folder, falling back
  /// to the first one the service offers.
  private var rootFolderBinding: Binding<String> {
    Binding(
      get: {
        store.edit.rootFolderPath ?? store.options.rootFolders.first?.path ?? ""
      },
      set: { store.edit.rootFolderPath = $0 }
    )
  }
}

/// One tag, toggled in or out of a selection.
struct TagToggle: View {
  let tag: ArrTag
  @Binding var selection: [Int]

  var body: some View {
    Button {
      if let index = selection.firstIndex(of: tag.id) {
        selection.remove(at: index)
      } else {
        selection.append(tag.id)
      }
    } label: {
      HStack {
        Text(tag.label)
        Spacer()
        if selection.contains(tag.id) {
          Image(systemName: "checkmark")
            .foregroundStyle(.tint)
        }
      }
    }
    .buttonStyle(.plain)
    // The checkmark is a glyph; the state has to be spoken too.
    .accessibilityElement(children: .combine)
    .accessibilityLabel(selection.contains(tag.id) ? "\(tag.label), selected" : tag.label)
    .accessibilityIdentifier("arr.tag.\(tag.id)")
  }
}
