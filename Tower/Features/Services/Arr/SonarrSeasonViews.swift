import SwiftUI
import TowerCore

/// One season: its episodes, with monitoring at season and episode level.
struct SonarrSeasonView: View {
  let store: SonarrLibraryStore
  let seriesID: Int
  let seasonNumber: Int

  @State private var isWorking = false

  var body: some View {
    List {
      if case .actionFailed(_, let error) = store.state {
        ActionErrorText(error: error, identifier: "sonarr.season.actionError")
      }

      if let season {
        Section {
          Toggle("Monitor season", isOn: seasonMonitoredBinding(season))
            .disabled(isWorking)
            .accessibilityIdentifier("sonarr.season.monitored")
          Button("Search Season", systemImage: "sparkle.magnifyingglass") {
            Task {
              isWorking = true
              defer { isWorking = false }
              await store.runAutomaticSearch(seriesID: seriesID, seasonNumber: seasonNumber)
            }
          }
          .disabled(isWorking)
          .accessibilityIdentifier("sonarr.season.search")
        }
      }

      Section("Episodes") {
        episodeContent
      }
    }
    .navigationTitle(season?.displayName ?? "Season \(seasonNumber)")
    .navigationBarTitleDisplayMode(.inline)
    .task { await store.loadEpisodes(seriesID: seriesID) }
    .refreshable { await store.loadEpisodes(seriesID: seriesID, force: true) }
    .accessibilityIdentifier("sonarr.season")
  }

  private var season: SonarrSeason? {
    store.series(id: seriesID)?.seasons.first { $0.seasonNumber == seasonNumber }
  }

  @ViewBuilder
  private var episodeContent: some View {
    switch store.episodes(for: seriesID) {
    case .idle, .loading:
      ProgressView()
        .accessibilityIdentifier("sonarr.season.loading")
    case .failed(let error):
      Text(error.message)
        .foregroundStyle(.red)
        .accessibilityIdentifier("sonarr.season.error")
    case .loaded, .actionFailed:
      let episodes = store.episodes(seriesID: seriesID, season: seasonNumber)
      if episodes.isEmpty {
        Text("No episodes in this season.")
          .foregroundStyle(.secondary)
          .accessibilityIdentifier("sonarr.season.empty")
      } else {
        ForEach(episodes) { episode in
          NavigationLink(
            value: SonarrEpisodeRoute(seriesID: seriesID, episodeID: episode.id)
          ) {
            SonarrEpisodeRow(episode: episode)
          }
        }
      }
    }
  }

  private func seasonMonitoredBinding(_ season: SonarrSeason) -> Binding<Bool> {
    Binding(
      get: { season.isMonitored },
      set: { newValue in
        Task {
          isWorking = true
          defer { isWorking = false }
          await store.setSeasonMonitored(
            newValue, seriesID: seriesID, seasonNumber: seasonNumber)
        }
      }
    )
  }
}

struct SonarrEpisodeRow: View {
  let episode: SonarrEpisode

  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      Text("\(episode.episodeCode) · \(episode.title)")
        .lineLimit(2)
      HStack(spacing: 6) {
        Text(stateText)
        if let air = episode.airDate {
          Text("·")
          Text(air.formatted(date: .abbreviated, time: .omitted))
        }
        if !episode.isMonitored {
          Text("·")
          Text("Unmonitored")
        }
      }
      .font(.caption)
      .foregroundStyle(.secondary)
    }
    .accessibilityElement(children: .combine)
    // Monitoring is in the label as well as the visible text: it is on the row
    // for a reason, and a spoken label that omits it tells a VoiceOver user
    // less than the screen does.
    .accessibilityLabel(accessibilityLabel)
    .accessibilityIdentifier("sonarr.episode.\(episode.id)")
  }

  private var accessibilityLabel: String {
    var parts = [episode.episodeCode, episode.title, stateText]
    if !episode.isMonitored { parts.append("Unmonitored") }
    return parts.joined(separator: ", ")
  }

  /// Downloaded, missing, or simply not out yet — the same three-way
  /// distinction the Radarr library makes, and for the same reason: only one of
  /// them is worth searching for.
  private var stateText: String {
    if episode.hasFile { return "Downloaded" }
    return episode.hasAired ? "Missing" : "Unaired"
  }
}

/// One episode: file and quality info, monitoring, and both searches.
struct SonarrEpisodeDetailView: View {
  let store: SonarrLibraryStore
  let seriesID: Int
  let episodeID: Int

  @State private var isWorking = false
  @State private var searchStore: InteractiveSearchStore?

  var body: some View {
    Group {
      if let episode {
        content(episode)
      } else {
        ContentUnavailableView(
          "Episode Removed", systemImage: "tv",
          description: Text("This episode is no longer listed.")
        )
      }
    }
  }

  private var episode: SonarrEpisode? {
    store.episodes(for: seriesID).value?.first { $0.id == episodeID }
  }

  private func content(_ episode: SonarrEpisode) -> some View {
    List {
      if case .actionFailed(_, let error) = store.state {
        ActionErrorText(error: error, identifier: "sonarr.episode.actionError")
      }

      Section {
        VStack(alignment: .leading, spacing: 4) {
          Text(episode.title)
            .font(.headline)
          Text(episode.episodeCode)
            .font(.subheadline)
            .foregroundStyle(.secondary)
          if let air = episode.airDate {
            Text(air.formatted(date: .long, time: .shortened))
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("sonarr.episode.header")
      }

      if let overview = episode.overview {
        Section("Overview") {
          Text(overview).font(.callout)
        }
      }

      Section("Status") {
        Toggle("Monitored", isOn: monitoredBinding(episode))
          .disabled(isWorking)
          .accessibilityIdentifier("sonarr.episode.monitored")
        LabeledContent("On disk", value: episode.hasFile ? "Yes" : "No")
        if let runtime = episode.runtimeMinutes {
          LabeledContent("Runtime", value: "\(runtime) min")
        }
      }

      if let file = episode.file {
        Section("File") {
          LabeledContent("Size", value: Formatters.bytes(file.sizeBytes))
          if let quality = file.quality { LabeledContent("Quality", value: quality) }
          if let resolution = file.resolution { LabeledContent("Resolution", value: resolution) }
          if let video = file.videoCodec { LabeledContent("Video", value: video) }
          if let audio = file.audioCodec { LabeledContent("Audio", value: audio) }
          if !file.languages.isEmpty {
            LabeledContent("Languages", value: file.languages.joined(separator: ", "))
          }
        }
        .accessibilityIdentifier("sonarr.episode.file")
      } else {
        Section("File") {
          Text(noFileMessage(episode))
            .foregroundStyle(.secondary)
            .accessibilityIdentifier("sonarr.episode.noFile")
        }
      }

      Section("Search") {
        Button("Automatic Search", systemImage: "sparkle.magnifyingglass") {
          Task {
            isWorking = true
            defer { isWorking = false }
            await store.runAutomaticSearch(episode: episode)
          }
        }
        .disabled(isWorking)
        .accessibilityIdentifier("sonarr.episode.automaticSearch")

        Button("Interactive Search", systemImage: "list.bullet.rectangle") {
          searchStore = .episode(episode, repository: store.repository)
        }
        .disabled(isWorking)
        .accessibilityIdentifier("sonarr.episode.interactiveSearch")
      }
    }
    .navigationTitle(episode.episodeCode)
    .navigationBarTitleDisplayMode(.inline)
    .sheet(item: $searchStore) { search in
      InteractiveSearchView(store: search)
    }
    .accessibilityIdentifier("sonarr.episode.detail")
  }

  /// What the File section says when no details arrived. Derived from
  /// `fileSection` rather than the air date, so it cannot contradict the "On
  /// disk" row or the "Downloaded" status label above it — Sonarr can
  /// report a file it sends no details for, and calling that "no file on disk"
  /// invites re-downloading something the array already holds.
  private func noFileMessage(_ episode: SonarrEpisode) -> String {
    switch episode.fileSection {
    case .details, .onDiskWithoutDetails: "On disk. Sonarr sent no details for the file."
    case .missing: "No file on disk."
    case .notYetAvailable: "Hasn't aired yet."
    }
  }

  private func monitoredBinding(_ episode: SonarrEpisode) -> Binding<Bool> {
    Binding(
      get: { episode.isMonitored },
      set: { newValue in
        Task {
          isWorking = true
          defer { isWorking = false }
          await store.setEpisodeMonitored(newValue, episode: episode)
        }
      }
    )
  }
}
