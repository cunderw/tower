import SwiftUI
import TowerCore

/// A Sonarr instance: the same shell, the series library in its Library
/// section.
struct SonarrServiceView: View {
  let instance: ServiceInstance
  @Bindable var store: SonarrLibraryStore
  var downloadClients: DownloadClientNavigator?

  @State private var addStore: SonarrAddStore?
  /// Set when a history row is tapped — the shell owns no navigation stack, so
  /// the drill-in opens the series as a sheet rather than pushing onto a stack
  /// the section doesn't have.
  @State private var historySeriesID: Int?

  var body: some View {
    ArrShellView(
      instance: instance,
      arr: store.repository,
      openMedia: { seriesID in
        guard store.series(id: seriesID) != nil else { return }
        historySeriesID = seriesID
      },
      downloadClients: downloadClients
    ) {
      library
        .task {
          await store.appeared()
        }
    }
    .sheet(item: Binding(
      get: { historySeriesID.map(HistoryTargetID.init) },
      set: { historySeriesID = $0?.id }
    )) { identifier in
      NavigationStack {
        SonarrSeriesDetailView(store: store, seriesID: identifier.id)
      }
    }
    // The haptics for every action in this library, at the root and not on
    // the screens pushed above it: series, season and episode all watch the
    // same counters, so a modifier on each would play once per stacked
    // screen. The root stays alive under every push and under the history
    // sheet.
    .sensoryFeedback(.success, trigger: store.lastActionSuccess)
    .sensoryFeedback(.error, trigger: store.lastActionFailure)
  }

  @ViewBuilder
  private var library: some View {
    switch store.state {
    case .idle, .loading:
      LoadingStateView(title: "Loading library…", isLoadInFlight: store.isLoadInFlight) {
        store.cancelLoad()
      }
    case .failed(let error):
      VStack(spacing: 16) {
        ContentUnavailableView {
          Label(error.message, systemImage: "exclamationmark.triangle")
        } description: {
          if let suggestion = error.serviceRecoverySuggestion { Text(suggestion) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("sonarr.library.error")

        Button("Try Again") { Task { await store.load() } }
          .accessibilityIdentifier("sonarr.library.retry")
      }
    case .loaded(let series), .actionFailed(let series, _):
      list(series)
    }
  }

  private func list(_ series: [SonarrSeries]) -> some View {
    List {
      if case .actionFailed(_, let error) = store.state {
        Text(error.message)
          .font(.caption)
          .foregroundStyle(.red)
          .accessibilityIdentifier("sonarr.library.refreshError")
      }
      ForEach(store.filteredSeries) { show in
        NavigationLink(value: show.id) {
          SonarrSeriesRow(series: show)
        }
      }
    }
    .navigationDestination(for: Int.self) { seriesID in
      // Identifier, not value.
      SonarrSeriesDetailView(store: store, seriesID: seriesID)
    }
    .searchable(text: $store.searchText, prompt: "Search series")
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        Button("Add Series", systemImage: "plus") { addStore = SonarrAddStore(library: store) }
          .accessibilityIdentifier("sonarr.library.add")
      }
      ToolbarItem(placement: .topBarTrailing) {
        Menu("Sort and Filter", systemImage: "line.3.horizontal.decrease.circle") {
          Picker("Sort", selection: $store.sort) {
            ForEach(SonarrSort.allCases) { option in
              Text(option.displayName).tag(option)
            }
          }
          Picker("Show", selection: $store.filter) {
            ForEach(SonarrFilter.allCases) { option in
              Text(option.displayName).tag(option)
            }
          }
        }
        .accessibilityIdentifier("sonarr.library.options")
      }
    }
    .overlay {
      if series.isEmpty {
        ContentUnavailableView(
          "No Series", systemImage: "tv",
          description: Text("This Sonarr has nothing in its library yet.")
        )
        .accessibilityIdentifier("sonarr.library.empty")
      } else if store.isFilteredToNothing {
        ContentUnavailableView(
          "No Matches", systemImage: "line.3.horizontal.decrease.circle",
          description: Text("No series match that filter.")
        )
        .accessibilityIdentifier("sonarr.library.noFilterMatch")
      } else if store.filteredSeries.isEmpty {
        ContentUnavailableView.search
      }
    }
    .refreshable { await store.refresh() }
    .sheet(item: $addStore) { add in
      SonarrAddSeriesView(store: add)
    }
  }
}
