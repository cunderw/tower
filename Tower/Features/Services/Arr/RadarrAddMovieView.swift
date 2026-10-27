import SwiftUI
import TowerCore

/// Add a movie: search, pick a result, configure, add.
struct RadarrAddMovieView: View {
  @Bindable var store: RadarrAddStore

  @Environment(\.dismiss) private var dismiss
  @State private var selection: RadarrMovieLookup?
  /// Bumped on a successful add, which is what fires the haptic.
  @State private var addedCount = 0

  var body: some View {
    NavigationStack {
      content
        .navigationTitle("Add Movie")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $store.searchText, prompt: "Search by name")
        .onSubmit(of: .search) { Task { await store.search() } }
        .toolbar {
          ToolbarItem(placement: .cancellationAction) {
            Button("Cancel") { dismiss() }
              .accessibilityIdentifier("radarr.add.cancel")
          }
        }
        .sheet(item: $selection) { lookup in
          RadarrConfigureAddSheet(store: store, lookup: lookup) {
            addedCount += 1
            selection = nil
            dismiss()
          }
        }
        // The confirmation that something happened — the same
        // `.sensoryFeedback` the Docker and VM action rows use.
        .sensoryFeedback(.success, trigger: addedCount)
    }
  }

  @ViewBuilder
  private var content: some View {
    switch store.results {
    case .idle:
      ContentUnavailableView(
        "Search Radarr", systemImage: "magnifyingglass",
        description: Text("Find a film by name, then choose where it goes.")
      )
      .accessibilityIdentifier("radarr.add.prompt")
    case .loading:
      ProgressView("Searching…")
        .accessibilityIdentifier("radarr.add.searching")
    case .failed(let error):
      ContentUnavailableView {
        Label(error.message, systemImage: "exclamationmark.triangle")
      } description: {
        if let suggestion = error.serviceRecoverySuggestion { Text(suggestion) }
      }
      .accessibilityIdentifier("radarr.add.error")
    case .loaded(let results), .actionFailed(let results, _):
      if results.isEmpty {
        ContentUnavailableView.search
      } else {
        List(results) { result in
          Button {
            // An already-added film opens nothing: adding it twice is an error
            // Radarr would reject, and the row says so instead.
            guard !result.isAlreadyAdded else { return }
            selection = result
          } label: {
            RadarrLookupRow(lookup: result)
          }
          .buttonStyle(.plain)
          .disabled(result.isAlreadyAdded)
        }
      }
    }
  }
}

struct RadarrLookupRow: View {
  let lookup: RadarrMovieLookup

  var body: some View {
    DashboardRow(showsChevron: false) {
      MediaPoster(url: lookup.posterURL, fallbackSystemImage: "film")
      VStack(alignment: .leading, spacing: 3) {
        Text(lookup.title)
          .font(.body)
        HStack(spacing: 6) {
          if let year = lookup.year { Text(String(year)) }
          if let studio = lookup.studio {
            Text("·")
            Text(studio)
          }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        if lookup.isAlreadyAdded {
          Text("Already added")
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
      }
      Spacer(minLength: 4)
    }
    .accessibilityElement(children: .combine)
    .accessibilityIdentifier("radarr.add.result.\(lookup.tmdbID)")
  }
}

/// Where the film goes, and what Radarr should do about it.
struct RadarrConfigureAddSheet: View {
  @Bindable var store: RadarrAddStore
  let lookup: RadarrMovieLookup
  let onAdded: () -> Void

  @Environment(\.dismiss) private var dismiss
  @State private var qualityProfileID: Int?
  @State private var rootFolderPath: String?
  @State private var minimumAvailability: MovieAvailability = .released
  @State private var isMonitored = true
  @State private var searchOnAdd = true
  @State private var tagIDs: [Int] = []

  var body: some View {
    NavigationStack {
      Form {
        Section {
          RadarrLookupRow(lookup: lookup)
        }

        Section("Where") {
          Picker("Root folder", selection: $rootFolderPath) {
            ForEach(store.options.rootFolders) { folder in
              Text(folder.path).tag(Optional(folder.path))
            }
          }
          .accessibilityIdentifier("radarr.add.rootFolder")

          Picker("Quality profile", selection: $qualityProfileID) {
            ForEach(store.options.qualityProfiles) { profile in
              Text(profile.name).tag(Optional(profile.id))
            }
          }
          .accessibilityIdentifier("radarr.add.qualityProfile")
        }

        Section("Options") {
          Toggle("Monitored", isOn: $isMonitored)
            .accessibilityIdentifier("radarr.add.monitored")
          Picker("Minimum availability", selection: $minimumAvailability) {
            ForEach(MovieAvailability.selectableForMinimumAvailability, id: \.self) { option in
              Text(option.displayName).tag(option)
            }
          }
          .accessibilityIdentifier("radarr.add.minimumAvailability")
          Toggle("Search on add", isOn: $searchOnAdd)
            .accessibilityIdentifier("radarr.add.searchOnAdd")
        }

        if !store.options.tags.isEmpty {
          Section("Tags") {
            ForEach(store.options.tags) { tag in
              TagToggle(tag: tag, selection: $tagIDs)
            }
          }
        }

        if let error = store.addError {
          Text(error.message)
            .foregroundStyle(.red)
            .accessibilityIdentifier("radarr.add.saveError")
        }
      }
      .navigationTitle("Add \(lookup.title)")
      .navigationBarTitleDisplayMode(.inline)
      .task {
        await store.options.load()
        // Defaults come from the service, never from a constant.
        qualityProfileID = qualityProfileID ?? store.options.qualityProfiles.first?.id
        rootFolderPath = rootFolderPath ?? store.options.rootFolders.first?.path
      }
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Add") { performAdd() }
            .disabled(!canAdd || store.isAdding)
            .accessibilityIdentifier("radarr.add.confirm")
        }
      }
    }
  }

  private var canAdd: Bool {
    qualityProfileID != nil && rootFolderPath?.isEmpty == false
  }

  private func performAdd() {
    guard let qualityProfileID, let rootFolderPath else { return }
    Task {
      let request = RadarrAddMovieRequest(
        lookup: lookup,
        qualityProfileID: qualityProfileID,
        rootFolderPath: rootFolderPath,
        minimumAvailability: minimumAvailability,
        isMonitored: isMonitored,
        searchOnAdd: searchOnAdd,
        tagIDs: tagIDs)
      if await store.add(request) != nil {
        onAdded()
      }
    }
  }
}
