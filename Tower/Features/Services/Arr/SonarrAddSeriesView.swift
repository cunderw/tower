import SwiftUI
import TowerCore

/// Add a series: search, pick a result, configure, add.
struct SonarrAddSeriesView: View {
  @Bindable var store: SonarrAddStore

  @Environment(\.dismiss) private var dismiss
  @State private var selection: SonarrSeriesLookup?
  @State private var addedCount = 0

  var body: some View {
    NavigationStack {
      content
        .navigationTitle("Add Series")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $store.searchText, prompt: "Search by name")
        .onSubmit(of: .search) { Task { await store.search() } }
        .toolbar {
          ToolbarItem(placement: .cancellationAction) {
            Button("Cancel") { dismiss() }
              .accessibilityIdentifier("sonarr.add.cancel")
          }
        }
        .sheet(item: $selection) { lookup in
          SonarrConfigureAddSheet(store: store, lookup: lookup) {
            addedCount += 1
            selection = nil
            dismiss()
          }
        }
        .sensoryFeedback(.success, trigger: addedCount)
    }
  }

  @ViewBuilder
  private var content: some View {
    switch store.results {
    case .idle:
      ContentUnavailableView(
        "Search Sonarr", systemImage: "magnifyingglass",
        description: Text("Find a series by name, then choose where it goes.")
      )
      .accessibilityIdentifier("sonarr.add.prompt")
    case .loading:
      ProgressView("Searching…")
        .accessibilityIdentifier("sonarr.add.searching")
    case .failed(let error):
      ContentUnavailableView {
        Label(error.message, systemImage: "exclamationmark.triangle")
      } description: {
        if let suggestion = error.serviceRecoverySuggestion { Text(suggestion) }
      }
      .accessibilityIdentifier("sonarr.add.error")
    case .loaded(let results), .actionFailed(let results, _):
      if results.isEmpty {
        ContentUnavailableView.search
      } else {
        List(results) { result in
          Button {
            guard !result.isAlreadyAdded else { return }
            selection = result
          } label: {
            SonarrLookupRow(lookup: result)
          }
          .buttonStyle(.plain)
          .disabled(result.isAlreadyAdded)
        }
      }
    }
  }
}

struct SonarrLookupRow: View {
  let lookup: SonarrSeriesLookup

  var body: some View {
    DashboardRow(showsChevron: false) {
      MediaPoster(url: lookup.posterURL, fallbackSystemImage: "tv")
      VStack(alignment: .leading, spacing: 3) {
        Text(lookup.title)
          .font(.body)
        HStack(spacing: 6) {
          if let year = lookup.year { Text(String(year)) }
          if let network = lookup.network {
            Text("·")
            Text(network)
          }
          Text("·")
          Text(lookup.status.displayName)
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
    .accessibilityIdentifier("sonarr.add.result.\(lookup.tvdbID)")
  }
}

/// Where the series goes, how it is numbered, and which episodes Sonarr should
/// monitor.
struct SonarrConfigureAddSheet: View {
  @Bindable var store: SonarrAddStore
  let lookup: SonarrSeriesLookup
  let onAdded: () -> Void

  @Environment(\.dismiss) private var dismiss
  @State private var qualityProfileID: Int?
  @State private var rootFolderPath: String?
  @State private var seriesType: SeriesType = .standard
  @State private var monitorOption: SeriesMonitorOption = .all
  @State private var usesSeasonFolders = true
  @State private var searchOnAdd = true
  @State private var tagIDs: [Int] = []

  var body: some View {
    NavigationStack {
      Form {
        Section {
          SonarrLookupRow(lookup: lookup)
        }

        Section("Where") {
          Picker("Root folder", selection: $rootFolderPath) {
            ForEach(store.options.rootFolders) { folder in
              Text(folder.path).tag(Optional(folder.path))
            }
          }
          .accessibilityIdentifier("sonarr.add.rootFolder")

          Picker("Quality profile", selection: $qualityProfileID) {
            ForEach(store.options.qualityProfiles) { profile in
              Text(profile.name).tag(Optional(profile.id))
            }
          }
          .accessibilityIdentifier("sonarr.add.qualityProfile")

          Toggle("Season folders", isOn: $usesSeasonFolders)
            .accessibilityIdentifier("sonarr.add.seasonFolders")
        }

        Section("Options") {
          // Sonarr's own vocabulary, not a paraphrase: `firstSeason` and
          // `missing` mean specific things to it, and renaming them would make
          // the picker mean something slightly different from what it does.
          Picker("Monitor", selection: $monitorOption) {
            ForEach(SeriesMonitorOption.allCases, id: \.self) { option in
              Text(option.displayName).tag(option)
            }
          }
          .accessibilityIdentifier("sonarr.add.monitor")

          Picker("Series type", selection: $seriesType) {
            ForEach(SeriesType.allCases, id: \.self) { type in
              Text(type.displayName).tag(type)
            }
          }
          .accessibilityIdentifier("sonarr.add.seriesType")

          Toggle("Search on add", isOn: $searchOnAdd)
            .accessibilityIdentifier("sonarr.add.searchOnAdd")
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
            .accessibilityIdentifier("sonarr.add.saveError")
        }
      }
      .navigationTitle("Add \(lookup.title)")
      .navigationBarTitleDisplayMode(.inline)
      .task {
        await store.options.load()
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
            .accessibilityIdentifier("sonarr.add.confirm")
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
      let request = SonarrAddSeriesRequest(
        lookup: lookup,
        qualityProfileID: qualityProfileID,
        rootFolderPath: rootFolderPath,
        seriesType: seriesType,
        monitorOption: monitorOption,
        usesSeasonFolders: usesSeasonFolders,
        searchOnAdd: searchOnAdd,
        tagIDs: tagIDs)
      if await store.add(request) != nil {
        onAdded()
      }
    }
  }
}
