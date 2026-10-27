import SwiftUI
import TowerCore

/// An artist: their albums, the monitor toggle, and search.
struct LidarrArtistDetailView: View {
  @Bindable var store: LidarrLibraryStore
  let artistID: Int

  @State private var isConfirmingDelete = false
  @State private var searchTarget: LidarrSearchTarget?

  private var artist: LidarrArtist? { store.artist(id: artistID) }

  var body: some View {
    Group {
      if let artist {
        content(artist)
      } else {
        ContentUnavailableView(
          "Artist Not Found", systemImage: "questionmark.folder",
          description: Text("It may have been removed from this Lidarr.")
        )
        .accessibilityIdentifier("lidarr.detail.missing")
      }
    }
    .navigationTitle(artist?.name ?? "Artist")
    .navigationBarTitleDisplayMode(.inline)
    .task { await store.loadAlbums(artistID: artistID) }
    .sheet(item: $searchTarget) { target in
      LidarrInteractiveSearchView(store: store, target: target)
    }
  }

  private func content(_ artist: LidarrArtist) -> some View {
    List {
      if case .actionFailed(_, let error) = store.state {
        ActionErrorText(error: error, identifier: "lidarr.detail.actionError")
      }

      Section {
        // The switch, not the row: tapping a `Toggle` row does nothing in this
        // app — only the switch at its trailing edge responds.
        Toggle(
          "Monitored",
          isOn: Binding(
            get: { artist.isMonitored },
            // Named, not `$0`: inside the nested `Task` that shorthand would
            // bind to the Task's own closure, not to the new value.
            set: { newValue in
              Task { await store.setArtistMonitored(newValue, for: artist) }
            }))
          .accessibilityIdentifier("lidarr.detail.monitored")

        if let statistics = artist.statistics {
          LabeledContent("Albums", value: String(statistics.albumCount))
          LabeledContent(
            "Tracks", value: "\(statistics.trackFileCount) of \(statistics.trackCount)")
          if statistics.sizeOnDiskBytes > 0 {
            LabeledContent("Size", value: Formatters.bytes(statistics.sizeOnDiskBytes))
          }
        }
        LabeledContent("Status", value: artist.status.displayName)
        if let type = artist.artistType {
          LabeledContent("Type", value: type)
        }
      }

      if let overview = artist.overview {
        Section("Overview") {
          Text(overview).font(.callout)
        }
      }

      Section("Albums") {
        albumRows(artist)
      }

      Section {
        Button("Search All Albums", systemImage: "magnifyingglass") {
          Task { await store.runAutomaticSearch(artist: artist) }
        }
        .accessibilityIdentifier("lidarr.detail.automaticSearch")

        Button("Interactive Search", systemImage: "list.bullet.rectangle") {
          searchTarget = .artist(artist)
        }
        .accessibilityIdentifier("lidarr.detail.interactiveSearch")

        Button("Delete Artist", systemImage: "trash", role: .destructive) {
          isConfirmingDelete = true
        }
        .accessibilityIdentifier("lidarr.detail.delete")
      }
    }
    .accessibilityIdentifier("lidarr.detail")
    .confirmationDialog(
      "Delete \(artist.name)?", isPresented: $isConfirmingDelete, titleVisibility: .visible
    ) {
      // Two destructive choices spelled out, as everywhere else in this app:
      // removing the artist and erasing their music are different decisions.
      Button("Remove from Lidarr", role: .destructive) {
        Task { await store.delete(artist, deleteFiles: false) }
      }
      .accessibilityIdentifier("lidarr.detail.confirmDelete")

      Button("Remove and Delete Files", role: .destructive) {
        Task { await store.delete(artist, deleteFiles: true) }
      }
      .accessibilityIdentifier("lidarr.detail.confirmDeleteFiles")

      Button("Cancel", role: .cancel) {}
    } message: {
      Text("Removing leaves the music on disk. Deleting the files erases it.")
    }
    .refreshable { await store.loadAlbums(artistID: artistID, force: true) }
  }

  @ViewBuilder
  private func albumRows(_ artist: LidarrArtist) -> some View {
    switch store.albums(for: artistID) {
    case .idle, .loading:
      ProgressView()
    case .failed(let error):
      Text(error.message)
        .font(.caption)
        .foregroundStyle(.red)
        .accessibilityIdentifier("lidarr.detail.albumsError")
    case .loaded(let albums), .actionFailed(let albums, _):
      if albums.isEmpty {
        Text("No albums.")
          .foregroundStyle(.secondary)
          .accessibilityIdentifier("lidarr.detail.noAlbums")
      }
      ForEach(albums) { album in
        NavigationLink(value: LidarrAlbumRoute(artistID: artistID, albumID: album.id)) {
          LidarrAlbumRow(album: album)
        }
        .swipeActions(edge: .leading) {
          Button(album.isMonitored ? "Unmonitor" : "Monitor", systemImage: "bookmark") {
            Task { await store.setAlbumMonitored(!album.isMonitored, album: album) }
          }
          .tint(album.isMonitored ? .secondary : .accentColor)
          .accessibilityIdentifier("lidarr.album.monitor.\(album.id)")
        }
      }
    }
  }
}

struct LidarrAlbumRow: View {
  let album: LidarrAlbum

  var body: some View {
    VStack(alignment: .leading, spacing: 3) {
      Text(album.displayTitle)
        .font(.callout)
        .lineLimit(2)
      HStack(spacing: 6) {
        LidarrStateBadge(state: album.libraryState)
        if let year = album.year { Text(String(year)) }
        if let type = album.albumType {
          Text("·")
          Text(type)
        }
        if let summary = album.statistics?.trackSummary {
          Text("·")
          Text(summary)
        }
      }
      .font(.caption)
      .foregroundStyle(.secondary)
      .lineLimit(1)

      if !album.isMonitored || !album.isReleased {
        HStack(spacing: 6) {
          // An unreleased album is not "missing" — saying so stops the user
          // going after something that does not exist yet.
          if !album.isReleased { Text("Not released") }
          if !album.isMonitored {
            if !album.isReleased { Text("·") }
            Text("Unmonitored")
          }
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
      }
    }
    .accessibilityElement(children: .combine)
    .accessibilityIdentifier("lidarr.album.\(album.id)")
  }
}

/// An album: its tracks, their file state, and search.
struct LidarrAlbumDetailView: View {
  @Bindable var store: LidarrLibraryStore
  let artistID: Int
  let albumID: Int

  @State private var searchTarget: LidarrSearchTarget?

  private var album: LidarrAlbum? { store.album(id: albumID, artistID: artistID) }

  var body: some View {
    Group {
      if let album {
        content(album)
      } else {
        ContentUnavailableView(
          "Album Not Found", systemImage: "questionmark.folder",
          description: Text("It may have been removed from this Lidarr.")
        )
        .accessibilityIdentifier("lidarr.album.detail.missing")
      }
    }
    .navigationTitle(album?.title ?? "Album")
    .navigationBarTitleDisplayMode(.inline)
    .task { await store.loadTracks(albumID: albumID) }
    .sheet(item: $searchTarget) { target in
      LidarrInteractiveSearchView(store: store, target: target)
    }
  }

  private func content(_ album: LidarrAlbum) -> some View {
    List {
      if case .actionFailed(_, let error) = store.state {
        ActionErrorText(error: error, identifier: "lidarr.album.detail.actionError")
      }

      Section {
        Toggle(
          "Monitored",
          isOn: Binding(
            get: { album.isMonitored },
            set: { newValue in
              Task { await store.setAlbumMonitored(newValue, album: album) }
            }))
          .accessibilityIdentifier("lidarr.album.detail.monitored")

        if let year = album.year { LabeledContent("Released", value: String(year)) }
        if let type = album.albumType { LabeledContent("Type", value: type) }
        if !album.secondaryTypes.isEmpty {
          LabeledContent("Also", value: album.secondaryTypes.joined(separator: ", "))
        }
        if let statistics = album.statistics {
          if let summary = statistics.trackSummary {
            LabeledContent("Tracks", value: summary)
          }
          if statistics.sizeOnDiskBytes > 0 {
            LabeledContent("Size", value: Formatters.bytes(statistics.sizeOnDiskBytes))
          }
        }
      }

      Section("Tracks") { trackRows }

      Section {
        Button("Search This Album", systemImage: "magnifyingglass") {
          Task { await store.runAutomaticSearch(album: album) }
        }
        // An unreleased album has nothing to find, so the search is offered
        // but disabled rather than silently doing nothing.
        .disabled(!album.isReleased)
        .accessibilityIdentifier("lidarr.album.detail.automaticSearch")

        Button("Interactive Search", systemImage: "list.bullet.rectangle") {
          searchTarget = .album(album)
        }
        .disabled(!album.isReleased)
        .accessibilityIdentifier("lidarr.album.detail.interactiveSearch")
      } footer: {
        if !album.isReleased {
          Text("This album hasn't been released yet.")
        }
      }
    }
    .accessibilityIdentifier("lidarr.album.detail")
    .refreshable { await store.loadTracks(albumID: albumID, force: true) }
  }

  @ViewBuilder
  private var trackRows: some View {
    switch store.tracks(for: albumID) {
    case .idle, .loading:
      ProgressView()
    case .failed(let error):
      Text(error.message)
        .font(.caption)
        .foregroundStyle(.red)
        .accessibilityIdentifier("lidarr.album.detail.tracksError")
    case .loaded(let tracks), .actionFailed(let tracks, _):
      if tracks.isEmpty {
        Text("No tracks.")
          .foregroundStyle(.secondary)
          .accessibilityIdentifier("lidarr.album.detail.noTracks")
      }
      ForEach(tracks) { track in
        HStack(spacing: 8) {
          if let number = track.trackNumber {
            Text(number)
              .font(.caption.monospacedDigit())
              .foregroundStyle(.secondary)
              .frame(minWidth: 28, alignment: .leading)
          }
          VStack(alignment: .leading, spacing: 2) {
            Text(track.title)
              .font(.callout)
              .lineLimit(2)
            HStack(spacing: 6) {
              // The file state in words, which is the fact worth reading here.
              Text(track.hasFile ? "On disk" : "Missing")
                .foregroundStyle(track.hasFile ? Color.secondary : Color.orange)
              if let duration = track.durationMilliseconds, duration > 0 {
                Text("·")
                Text(Formatters.duration(seconds: duration / 1_000))
              }
              if track.isExplicit {
                Text("·")
                Text("Explicit")
              }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
          }
          Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("lidarr.track.\(track.id)")
      }
    }
  }
}

/// What an interactive search is for — the two levels Lidarr offers.
enum LidarrSearchTarget: Identifiable {
  case artist(LidarrArtist)
  case album(LidarrAlbum)

  var id: String {
    switch self {
    case .artist(let artist): "artist-\(artist.id)"
    case .album(let album): "album-\(album.id)"
    }
  }

  var title: String {
    switch self {
    case .artist(let artist): artist.name
    case .album(let album): album.displayTitle
    }
  }
}

/// Interactive search at artist or album level.
///
/// The releases and the grab are the shared `ArrRelease` shape, so this reuses
/// `InteractiveSearchStore` rather than repeating its sorting, its rejection
/// handling, and its confirm-before-grab.
struct LidarrInteractiveSearchView: View {
  let store: LidarrLibraryStore
  let target: LidarrSearchTarget

  @State private var searchStore: InteractiveSearchStore?

  var body: some View {
    NavigationStack {
      Group {
        if let searchStore {
          InteractiveSearchView(store: searchStore)
        } else {
          ProgressView()
        }
      }
      .navigationTitle(target.title)
      .navigationBarTitleDisplayMode(.inline)
    }
    .task {
      guard searchStore == nil else { return }
      // Built once and held, not created in `body`: a store rebuilt on every
      // render resets its `Loadable` and restarts the search forever.
      let scope: InteractiveSearchScope =
        switch target {
        case .artist(let artist): .artist(id: artist.id, title: artist.name)
        case .album(let album): .album(id: album.id, title: album.displayTitle)
        }
      searchStore = InteractiveSearchStore(
        scope: scope,
        fetch: { [store, target] in
          switch target {
          case .artist(let artist): try await store.repository.releases(artistID: artist.id)
          case .album(let album): try await store.repository.releases(albumID: album.id)
          }
        },
        grab: { [store] release in try await store.repository.grab(release) })
    }
  }
}
