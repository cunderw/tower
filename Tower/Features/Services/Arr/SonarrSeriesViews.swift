import SwiftUI
import TowerCore

/// One row in the Sonarr library.
struct SonarrSeriesRow: View {
  let series: SonarrSeries

  var body: some View {
    DashboardRow(showsChevron: false) {
      MediaPoster(url: series.posterURL, fallbackSystemImage: "tv")

      VStack(alignment: .leading, spacing: 3) {
        Text(series.title)
          .font(.body)
          .lineLimit(2)

        HStack(spacing: 6) {
          Text(progressText)
          if let network = series.network {
            Text("·")
            Text(network)
          }
          Text("·")
          Text(series.status.displayName)
        }
        .font(.caption)
        .foregroundStyle(.secondary)

        HStack(spacing: 6) {
          if series.sizeOnDiskBytes > 0 {
            Text(Formatters.bytes(series.sizeOnDiskBytes))
          }
          if !series.isMonitored {
            if series.sizeOnDiskBytes > 0 { Text("·") }
            Text("Unmonitored")
          }
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
      }

      Spacer(minLength: 4)
    }
    .accessibilityElement(children: .combine)
    .accessibilityLabel(accessibilityLabel)
    .accessibilityIdentifier("sonarr.row.\(series.id)")
  }

  /// "16 of 17" — episodes on disk out of episodes that have *aired*. Counting
  /// unaired episodes would show a fully up-to-date continuing series as
  /// permanently incomplete.
  private var progressText: String {
    guard let statistics = series.statistics, statistics.episodeCount > 0 else {
      return "No episodes"
    }
    return series.isComplete
      ? "Complete"
      : "\(statistics.episodeFileCount) of \(statistics.episodeCount)"
  }

  private var accessibilityLabel: String {
    var parts = [series.title, progressText]
    if let network = series.network { parts.append(network) }
    parts.append(series.status.displayName)
    if series.sizeOnDiskBytes > 0 { parts.append(Formatters.bytes(series.sizeOnDiskBytes)) }
    if !series.isMonitored { parts.append("Unmonitored") }
    return parts.joined(separator: ", ")
  }
}

/// One series: poster header, overview, and its seasons.
struct SonarrSeriesDetailView: View {
  let store: SonarrLibraryStore
  let seriesID: Int

  @State private var isWorking = false

  var body: some View {
    Group {
      if let series = store.series(id: seriesID) {
        content(series)
      } else {
        ContentUnavailableView(
          "Series Removed", systemImage: "tv",
          description: Text("This series is no longer in the library.")
        )
        .accessibilityIdentifier("sonarr.detail.missing")
      }
    }
  }

  private func content(_ series: SonarrSeries) -> some View {
    List {
      if case .actionFailed(_, let error) = store.state {
        ActionErrorText(error: error, identifier: "sonarr.detail.actionError")
      }

      Section {
        HStack(alignment: .top, spacing: 12) {
          MediaPoster(url: series.posterURL, fallbackSystemImage: "tv", width: 92)
          VStack(alignment: .leading, spacing: 6) {
            Text(series.title)
              .font(.headline)
            Text(series.status.displayName)
              .font(.subheadline)
              .foregroundStyle(.secondary)
            if let network = series.network {
              Text(network)
                .font(.caption)
                .foregroundStyle(.secondary)
            }
          }
          Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("sonarr.detail.header")
      }

      if let overview = series.overview {
        Section("Overview") {
          Text(overview).font(.callout)
        }
      }

      Section("Status") {
        Toggle("Monitored", isOn: seriesMonitoredBinding(series))
          .disabled(isWorking)
          .accessibilityIdentifier("sonarr.detail.monitored")
        LabeledContent("Type", value: series.seriesType.displayName)
        if let statistics = series.statistics {
          LabeledContent(
            "Episodes",
            value: "\(statistics.episodeFileCount) of \(statistics.episodeCount) aired")
          LabeledContent("Size", value: Formatters.bytes(series.sizeOnDiskBytes))
        }
        if let next = series.nextAiring {
          LabeledContent("Next episode", value: next.formatted(date: .abbreviated, time: .shortened))
        }
      }

      Section("Seasons") {
        ForEach(series.seasons) { season in
          NavigationLink(value: SonarrSeasonRoute(seriesID: series.id, season: season.seasonNumber)) {
            SonarrSeasonRow(season: season)
          }
        }
      }

      Section("Search") {
        Button("Search Series", systemImage: "sparkle.magnifyingglass") {
          Task {
            isWorking = true
            defer { isWorking = false }
            await store.runAutomaticSearch(series: series)
          }
        }
        .disabled(isWorking)
        .accessibilityIdentifier("sonarr.detail.search")
      }
    }
    .navigationTitle(series.title)
    .navigationBarTitleDisplayMode(.inline)
    .navigationDestination(for: SonarrSeasonRoute.self) { route in
      SonarrSeasonView(store: store, seriesID: route.seriesID, seasonNumber: route.season)
    }
    .navigationDestination(for: SonarrEpisodeRoute.self) { route in
      SonarrEpisodeDetailView(store: store, seriesID: route.seriesID, episodeID: route.episodeID)
    }
    .task { await store.loadEpisodes(seriesID: seriesID) }
    .refreshable { await store.refresh() }
    .accessibilityIdentifier("sonarr.detail")
  }

  private func seriesMonitoredBinding(_ series: SonarrSeries) -> Binding<Bool> {
    Binding(
      get: { series.isMonitored },
      set: { newValue in
        Task {
          isWorking = true
          defer { isWorking = false }
          await store.setSeriesMonitored(newValue, for: series)
        }
      }
    )
  }
}

/// Routes, so the three levels push by identifier rather than by value
/// and each screen re-resolves from the store.
struct SonarrSeasonRoute: Hashable {
  let seriesID: Int
  let season: Int
}

struct SonarrEpisodeRoute: Hashable {
  let seriesID: Int
  let episodeID: Int
}

struct SonarrSeasonRow: View {
  let season: SonarrSeason

  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(season.displayName)
      HStack(spacing: 6) {
        Text(season.isComplete ? "Complete" : "\(season.episodeFileCount) of \(season.episodeCount)")
        if season.sizeOnDiskBytes > 0 {
          Text("·")
          Text(Formatters.bytes(season.sizeOnDiskBytes))
        }
        if !season.isMonitored {
          Text("·")
          Text("Unmonitored")
        }
      }
      .font(.caption)
      .foregroundStyle(.secondary)
    }
    .accessibilityElement(children: .combine)
    .accessibilityIdentifier("sonarr.season.\(season.seasonNumber)")
  }
}
