import SwiftUI
import TowerCore

/// Search MusicBrainz and add an artist.
struct LidarrAddArtistView: View {
  @Bindable var store: LidarrAddStore
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      Group {
        if store.selected == nil {
          results
        } else {
          configuration
        }
      }
      .navigationTitle(store.selected?.name ?? "Add Artist")
      .navigationBarTitleDisplayMode(.inline)
      .searchable(text: $store.searchText, prompt: "Search by name")
      .onSubmit(of: .search) { Task { await store.search() } }
      .toolbar { toolbar }
      .task { await store.loadPickers() }
    }
  }

  @ToolbarContentBuilder
  private var toolbar: some ToolbarContent {
    ToolbarItem(placement: .cancellationAction) {
      if store.selected == nil {
        Button("Cancel") { dismiss() }
      } else {
        // Back to the results, not out of the sheet: picking the wrong artist
        // is a normal mistake and shouldn't cost the search.
        Button("Back") { store.clearSelection() }
          .accessibilityIdentifier("lidarr.add.back")
      }
    }
    if store.selected != nil {
      ToolbarItem(placement: .confirmationAction) {
        Button("Add") {
          Task { if await store.submit() { dismiss() } }
        }
        .disabled(!store.canSubmit)
        .accessibilityIdentifier("lidarr.add.confirm")
      }
    }
  }

  @ViewBuilder
  private var results: some View {
    switch store.state {
    case .idle:
      ContentUnavailableView(
        "Search for an Artist", systemImage: "music.mic",
        description: Text("Find an artist to add to this Lidarr.")
      )
      .accessibilityIdentifier("lidarr.add.prompt")
    case .loading:
      ProgressView()
    case .failed(let error):
      ContentUnavailableView {
        Label(error.message, systemImage: "exclamationmark.triangle")
      } description: {
        if let suggestion = error.serviceRecoverySuggestion { Text(suggestion) }
      }
      .accessibilityIdentifier("lidarr.add.error")
    case .loaded(let hits), .actionFailed(let hits, _):
      if hits.isEmpty {
        ContentUnavailableView(
          "No Results", systemImage: "music.mic",
          description: Text("Nothing matched “\(store.lastSearchedTerm)”.")
        )
        .accessibilityIdentifier("lidarr.add.empty")
      } else {
        List(hits) { hit in
          Button {
            store.select(hit)
          } label: {
            LidarrLookupRow(hit: hit)
          }
          .buttonStyle(.plain)
          // Already in the library: shown, but not offered again — adding a
          // duplicate is rejected by Lidarr and reads as the app being broken.
          .disabled(hit.isAlreadyAdded)
          .accessibilityIdentifier("lidarr.add.result.\(hit.foreignArtistID)")
        }
      }
    }
  }

  @ViewBuilder
  private var configuration: some View {
    Form {
      Section {
        Picker("Quality profile", selection: $store.qualityProfileID) {
          ForEach(store.qualityProfiles) { profile in
            Text(profile.name).tag(Int?.some(profile.id))
          }
        }
        .accessibilityIdentifier("lidarr.add.qualityProfile")

        // Lidarr's second axis, and the one with no Radarr or Sonarr
        // equivalent: it decides which album types are wanted at all.
        Picker("Metadata profile", selection: $store.metadataProfileID) {
          ForEach(store.metadataProfiles) { profile in
            Text(profile.name).tag(Int?.some(profile.id))
          }
        }
        .accessibilityIdentifier("lidarr.add.metadataProfile")

        Picker("Root folder", selection: $store.rootFolderPath) {
          ForEach(store.rootFolders) { folder in
            Text(folder.path).tag(String?.some(folder.path))
          }
        }
        .accessibilityIdentifier("lidarr.add.rootFolder")
      }

      Section {
        // Without this, Lidarr files an artist whose entire discography is
        // ignored — which looks like the add silently failing.
        Picker("Monitor", selection: $store.monitorOption) {
          ForEach(LidarrMonitorOption.allCases) { option in
            Text(option.displayName).tag(option)
          }
        }
        .accessibilityIdentifier("lidarr.add.monitor")

        Toggle("Monitored", isOn: $store.isMonitored)
          .accessibilityIdentifier("lidarr.add.monitored")
        Toggle("Search on add", isOn: $store.searchOnAdd)
          .accessibilityIdentifier("lidarr.add.searchOnAdd")
      }

      if let error = store.addError {
        Section {
          Text(error.message)
            .font(.caption)
            .foregroundStyle(.red)
            .accessibilityIdentifier("lidarr.add.addError")
        }
      }
    }
    .overlay {
      if store.isSubmitting { ProgressView().controlSize(.large) }
    }
  }
}

struct LidarrLookupRow: View {
  let hit: LidarrArtistLookup

  var body: some View {
    DashboardRow(showsChevron: false) {
      MediaPoster(url: hit.posterURL, fallbackSystemImage: "music.mic")

      VStack(alignment: .leading, spacing: 3) {
        Text(hit.name)
          .font(.body)
          .lineLimit(2)
        HStack(spacing: 6) {
          if let type = hit.artistType { Text(type) }
          if let disambiguation = hit.disambiguation {
            if hit.artistType != nil { Text("·") }
            Text(disambiguation)
          }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(1)

        if hit.isAlreadyAdded {
          // Words, so the disabled row explains itself rather than just
          // looking greyed out.
          Text("Already in your library")
            .font(.caption2)
            .foregroundStyle(.secondary)
        } else if let overview = hit.overview {
          Text(overview)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .lineLimit(2)
        }
      }

      Spacer(minLength: 4)
    }
    .accessibilityElement(children: .combine)
  }
}
