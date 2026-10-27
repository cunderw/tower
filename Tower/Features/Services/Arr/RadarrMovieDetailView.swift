import SwiftUI
import TowerCore

/// One movie: poster header, overview, status, file info, monitor toggle, and
/// delete.
///
/// Resolved from the store by id on every render, so a refresh or a
/// monitor toggle made anywhere reaches this screen.
struct RadarrMovieDetailView: View {
  let store: RadarrLibraryStore
  let movieID: Int

  @Environment(\.dismiss) private var dismiss
  @State private var isConfirmingDelete = false
  @State private var editStore: RadarrEditStore?
  @State private var searchStore: InteractiveSearchStore?
  @State private var deleteFiles = false
  @State private var isWorking = false

  var body: some View {
    Group {
      if let movie = store.state.value?.first(where: { $0.id == movieID }) {
        content(movie)
      } else {
        // Deleted while open — the delete path dismisses, so this is the
        // "removed from another device" case rather than a dead end.
        ContentUnavailableView(
          "Movie Removed", systemImage: "film",
          description: Text("This movie is no longer in the library.")
        )
        .accessibilityIdentifier("radarr.detail.missing")
      }
    }
  }

  private func content(_ movie: RadarrMovie) -> some View {
    List {
      if case .actionFailed(_, let error) = store.state {
        // The library's own error row is behind this screen, out of sight.
        ActionErrorText(error: error, identifier: "radarr.detail.actionError")
      }

      Section {
        HStack(alignment: .top, spacing: 12) {
          MediaPoster(url: movie.posterURL, fallbackSystemImage: "film", width: 92)
          VStack(alignment: .leading, spacing: 6) {
            Text(movie.title)
              .font(.headline)
            HStack(spacing: 6) {
              AvailabilityBadge(state: movie.libraryState)
              if let year = movie.year { Text(String(year)) }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            if let studio = movie.studio {
              Text(studio)
                .font(.caption)
                .foregroundStyle(.secondary)
            }
          }
          Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("radarr.detail.header")
      }

      if let overview = movie.overview {
        Section("Overview") {
          Text(overview)
            .font(.callout)
            .accessibilityIdentifier("radarr.detail.overview")
        }
      }

      Section("Status") {
        Toggle("Monitored", isOn: monitoredBinding(movie))
          .disabled(isWorking)
          .accessibilityIdentifier("radarr.detail.monitored")
        LabeledContent("Availability", value: movie.status.displayName)
        LabeledContent("Minimum availability", value: movie.minimumAvailability.displayName)
        if let profile = store.qualityProfileName(for: movie) {
          LabeledContent("Quality profile", value: profile)
        }
        if let runtime = movie.runtimeMinutes {
          LabeledContent("Runtime", value: "\(runtime) min")
        }
        if let certification = movie.certification {
          LabeledContent("Rating", value: certification)
        }
        if !movie.genres.isEmpty {
          LabeledContent("Genres", value: movie.genres.joined(separator: ", "))
        }
      }

      if let file = movie.file {
        Section("File") {
          LabeledContent("Size", value: Formatters.bytes(file.sizeBytes))
          if let quality = file.quality { LabeledContent("Quality", value: quality) }
          if let resolution = file.resolution { LabeledContent("Resolution", value: resolution) }
          if let video = file.videoCodec { LabeledContent("Video", value: video) }
          if let audio = file.audioCodec {
            LabeledContent(
              "Audio",
              value: file.audioChannels.map { "\(audio) \(String(format: "%.1f", $0))" } ?? audio)
          }
          if !file.languages.isEmpty {
            LabeledContent("Languages", value: file.languages.joined(separator: ", "))
          }
          if let group = file.releaseGroup { LabeledContent("Release group", value: group) }
          if let path = file.relativePath {
            LabeledContent("Path", value: path)
              .font(.caption)
          }
        }
        .accessibilityIdentifier("radarr.detail.file")
      } else {
        Section("File") {
          Text(noFileMessage(movie))
            .foregroundStyle(.secondary)
            .accessibilityIdentifier("radarr.detail.noFile")
        }
      }

      Section("Search") {
        Button("Automatic Search", systemImage: "sparkle.magnifyingglass") {
          Task {
            isWorking = true
            defer { isWorking = false }
            await store.runAutomaticSearch(for: movie)
          }
        }
        .disabled(isWorking)
        .accessibilityIdentifier("radarr.detail.automaticSearch")

        Button("Interactive Search", systemImage: "list.bullet.rectangle") {
          searchStore = .movie(movie, repository: store.repository)
        }
        .disabled(isWorking)
        .accessibilityIdentifier("radarr.detail.interactiveSearch")
      }

      Section {
        Button("Delete Movie", systemImage: "trash", role: .destructive) {
          deleteFiles = false
          isConfirmingDelete = true
        }
        .disabled(isWorking)
        .accessibilityIdentifier("radarr.detail.delete")
      }
    }
    .navigationTitle(movie.title)
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        Button("Edit", systemImage: "pencil") {
          editStore = RadarrEditStore(movie: movie, library: store)
        }
        .disabled(isWorking)
        .accessibilityIdentifier("radarr.detail.edit")
      }
    }
    .sheet(item: $editStore) { edit in
      RadarrEditSheet(store: edit) {}
    }
    .sheet(item: $searchStore) { search in
      InteractiveSearchView(store: search)
    }
    .sensoryFeedback(.success, trigger: store.lastActionSuccess)
    .sensoryFeedback(.error, trigger: store.lastActionFailure)
    .refreshable { await store.refresh() }
    .confirmationDialog(
      "Delete \(movie.title)?",
      isPresented: $isConfirmingDelete,
      titleVisibility: .visible
    ) {
      // Two destructive choices, spelled out rather than hidden behind a
      // toggle: removing the film from Radarr and deleting the file it points
      // at are different decisions, and only one of them is recoverable.
      Button("Remove from Radarr", role: .destructive) {
        performDelete(movie, deleteFiles: false)
      }
      .accessibilityIdentifier("radarr.detail.confirmDelete")

      if movie.hasFile {
        Button("Remove and Delete File", role: .destructive) {
          performDelete(movie, deleteFiles: true)
        }
        .accessibilityIdentifier("radarr.detail.confirmDeleteFiles")
      }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text(movie.hasFile
        ? "Removing keeps the file on disk. Deleting the file cannot be undone."
        : "This removes the movie from Radarr.")
    }
    .accessibilityIdentifier("radarr.detail")
  }

  /// What the File section says when no details arrived. Derived from
  /// `fileSection` rather than availability, so it cannot contradict the
  /// "Downloaded" badge above it. Radarr does send `movieFile` on its
  /// list endpoint; this covers a response that leaves it out.
  private func noFileMessage(_ movie: RadarrMovie) -> String {
    switch movie.fileSection {
    case .details, .onDiskWithoutDetails: "On disk. Radarr sent no details for the file."
    case .missing: "No file on disk."
    case .notYetAvailable: "Not released yet."
    }
  }

  private func monitoredBinding(_ movie: RadarrMovie) -> Binding<Bool> {
    Binding(
      get: { movie.isMonitored },
      set: { newValue in
        Task {
          isWorking = true
          defer { isWorking = false }
          await store.setMonitored(newValue, for: movie)
        }
      }
    )
  }

  private func performDelete(_ movie: RadarrMovie, deleteFiles: Bool) {
    Task {
      isWorking = true
      defer { isWorking = false }
      await store.delete(movie, deleteFiles: deleteFiles)
      // Only leave the screen if the delete actually happened — a failure keeps
      // the movie, and the error row at the top of this screen explains why.
      if store.state.value?.contains(where: { $0.id == movie.id }) != true {
        dismiss()
      }
    }
  }
}
