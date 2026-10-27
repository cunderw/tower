import SwiftUI
import TowerCore
import TowerData

/// A Lidarr instance: the shared *arr shell, with the artist library in its
/// Library section.
///
/// **Queue, Calendar, History, and More are not written here.** They are
/// `ArrShellView`'s, built from `ArrClientCore` — which is the whole point of
/// the shell being generic over the library and nothing else.
struct LidarrServiceView: View {
  let instance: ServiceInstance
  @Bindable var store: LidarrLibraryStore
  var downloadClients: DownloadClientNavigator?

  @State private var addStore: LidarrAddStore?

  var body: some View {
    ArrShellView(
      instance: instance,
      arr: store.repository,
      downloadClients: downloadClients
    ) {
      library
        // On the section, not inside its loaded branch — otherwise nothing
        // starts the load and the library sits on its spinner forever.
        .task {
          await store.appeared()
        }
    }
    // The haptics for every action in this library, at the root and not on
    // the screens pushed above it: the artist and album screens watch the same
    // counters, so a modifier on each would play once per stacked screen. The
    // root stays alive under every push.
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
        .accessibilityIdentifier("lidarr.library.error")
        Button("Try Again") { Task { await store.load() } }
          .accessibilityIdentifier("lidarr.library.retry")
      }
    case .loaded(let artists), .actionFailed(let artists, _):
      list(artists)
    }
  }

  private func list(_ artists: [LidarrArtist]) -> some View {
    List {
      if case .actionFailed(_, let error) = store.state {
        Text(error.message)
          .font(.caption)
          .foregroundStyle(.red)
          .accessibilityIdentifier("lidarr.library.refreshError")
      }
      ForEach(store.filteredArtists) { artist in
        NavigationLink(value: artist.id) {
          LidarrArtistRow(
            artist: artist, metadataProfile: store.metadataProfileName(for: artist))
        }
      }
    }
    .navigationDestination(for: Int.self) { artistID in
      // Identifier, not value.
      LidarrArtistDetailView(store: store, artistID: artistID)
    }
    .navigationDestination(for: LidarrAlbumRoute.self) { route in
      LidarrAlbumDetailView(store: store, artistID: route.artistID, albumID: route.albumID)
    }
    .searchable(text: $store.searchText, prompt: "Search artists")
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        Button("Add Artist", systemImage: "plus") {
          addStore = LidarrAddStore(library: store)
        }
        .accessibilityIdentifier("lidarr.library.add")
      }
      ToolbarItem(placement: .topBarTrailing) {
        Menu("Sort and Filter", systemImage: "line.3.horizontal.decrease.circle") {
          Picker("Sort", selection: $store.sort) {
            ForEach(LidarrSort.allCases) { option in
              Text(option.displayName).tag(option)
            }
          }
          Picker("Show", selection: $store.filter) {
            ForEach(LidarrFilter.allCases) { option in
              Text(option.displayName).tag(option)
            }
          }
        }
        .accessibilityIdentifier("lidarr.library.options")
      }
    }
    .overlay {
      // Three empty states: an empty library, a filter that matched nothing,
      // and a search that matched nothing are three different things to say.
      if artists.isEmpty {
        ContentUnavailableView(
          "No Artists", systemImage: "music.mic",
          description: Text("This Lidarr has nothing in its library yet.")
        )
        .accessibilityIdentifier("lidarr.library.empty")
      } else if store.isFilteredToNothing {
        ContentUnavailableView(
          "No Matches", systemImage: "line.3.horizontal.decrease.circle",
          description: Text("No artists are \(store.filter.displayName.lowercased()).")
        )
        .accessibilityIdentifier("lidarr.library.noFilterMatch")
      } else if store.filteredArtists.isEmpty {
        ContentUnavailableView.search
      }
    }
    .refreshable { await store.refresh() }
    .task { await store.loadMetadataProfiles() }
    .sheet(item: $addStore) { add in
      LidarrAddArtistView(store: add)
    }
  }
}

/// Albums route by artist *and* album id: an album screen needs its artist to
/// find the album in the store, and a bare `Int` would collide with the
/// artist destination in the same stack.
struct LidarrAlbumRoute: Hashable {
  let artistID: Int
  let albumID: Int
}

/// One artist in the library.
struct LidarrArtistRow: View {
  let artist: LidarrArtist
  let metadataProfile: String?

  var body: some View {
    DashboardRow(showsChevron: false) {
      MediaPoster(url: artist.posterURL, fallbackSystemImage: "music.mic")

      VStack(alignment: .leading, spacing: 3) {
        Text(artist.displayName)
          .font(.body)
          .lineLimit(2)

        HStack(spacing: 6) {
          LidarrStateBadge(state: artist.libraryState)
          if let statistics = artist.statistics {
            Text(Formatters.count(statistics.albumCount, "album"))
          }
          if let metadataProfile {
            Text("·")
            Text(metadataProfile)
          }
        }
        .font(.caption)
        .foregroundStyle(.secondary)

        HStack(spacing: 6) {
          if let statistics = artist.statistics, statistics.sizeOnDiskBytes > 0 {
            Text(Formatters.bytes(statistics.sizeOnDiskBytes))
          }
          if !artist.isMonitored {
            if artist.statistics?.sizeOnDiskBytes ?? 0 > 0 { Text("·") }
            // Words, not just a dimmed row: colour is never the only signal.
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
    .accessibilityIdentifier("lidarr.row.\(artist.id)")
  }

  private var accessibilityLabel: String {
    var parts = [artist.displayName, artist.libraryState.displayName]
    if let statistics = artist.statistics {
      parts.append(Formatters.count(statistics.albumCount, "album"))
      if statistics.sizeOnDiskBytes > 0 {
        parts.append(Formatters.bytes(statistics.sizeOnDiskBytes))
      }
    }
    if let metadataProfile { parts.append(metadataProfile) }
    if !artist.isMonitored { parts.append("Unmonitored") }
    return parts.joined(separator: ", ")
  }
}

/// The three-way state, as a word plus a tint — never a tint alone.
struct LidarrStateBadge: View {
  let state: LidarrLibraryState

  var body: some View {
    Text(state.displayName)
      .font(.caption2.weight(.medium))
      .padding(.horizontal, 6)
      .padding(.vertical, 2)
      .background(tint.opacity(0.15), in: Capsule())
      .foregroundStyle(tint)
  }

  private var tint: Color {
    switch state {
    case .complete: .green
    case .partial: .orange
    case .missing: .secondary
    }
  }
}
