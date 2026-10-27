import SwiftUI
import TowerCore

/// A Radarr instance: the shared shell, with the movie library in its Library
/// section.
struct RadarrServiceView: View {
  let instance: ServiceInstance
  @Bindable var store: RadarrLibraryStore
  /// Lets the queue section open the download client fetching a row.
  var downloadClients: DownloadClientNavigator?

  @State private var addStore: RadarrAddStore?
  /// Set when a history row is tapped — the shell has no navigation stack of
  /// its own, so the drill-in opens the movie as a sheet rather than pushing
  /// onto a stack the section doesn't own.
  @State private var historyMovieID: Int?

  var body: some View {
    ArrShellView(
      instance: instance,
      arr: store.repository,
      openMedia: { movieID in
        guard store.state.value?.contains(where: { $0.id == movieID }) == true else { return }
        historyMovieID = movieID
      },
      downloadClients: downloadClients
    ) {
      library
        // **On the section, not inside its loaded branch.** The list only
        // exists once the load has finished, so a `.task` there never starts
        // and the library sits on its spinner forever. Here it fires when the
        // Library section is built, which is
        // also what keeps the other four sections from fetching anything.
        .task {
          await store.appeared()
        }
    }
    .sheet(item: Binding(
      get: { historyMovieID.map(HistoryTargetID.init) },
      set: { historyMovieID = $0?.id }
    )) { identifier in
      NavigationStack {
        RadarrMovieDetailView(store: store, movieID: identifier.id)
      }
    }
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
        .accessibilityIdentifier("radarr.library.error")

        Button("Try Again") { Task { await store.load() } }
          .accessibilityIdentifier("radarr.library.retry")
      }
    case .loaded(let movies), .actionFailed(let movies, _):
      list(movies)
    }
  }

  private func list(_ movies: [RadarrMovie]) -> some View {
    List {
      if case .actionFailed(_, let error) = store.state {
        // A failed delete or monitor toggle keeps the library on screen and
        // says what went wrong, rather than blanking the list.
        Text(error.message)
          .font(.caption)
          .foregroundStyle(.red)
          .accessibilityIdentifier("radarr.library.refreshError")
      }
      ForEach(store.filteredMovies) { movie in
        NavigationLink(value: movie.id) {
          RadarrMovieRow(movie: movie, qualityProfile: store.qualityProfileName(for: movie))
        }
      }
    }
    .navigationDestination(for: Int.self) { movieID in
      // Identifier, not value.
      RadarrMovieDetailView(store: store, movieID: movieID)
    }
    .searchable(text: $store.searchText, prompt: "Search movies")
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        Button("Add Movie", systemImage: "plus") { addStore = RadarrAddStore(library: store) }
          .accessibilityIdentifier("radarr.library.add")
      }
      ToolbarItem(placement: .topBarTrailing) {
        Menu("Sort and Filter", systemImage: "line.3.horizontal.decrease.circle") {
          Picker("Sort", selection: $store.sort) {
            ForEach(RadarrSort.allCases) { option in
              Text(option.displayName).tag(option)
            }
          }
          Picker("Show", selection: $store.filter) {
            ForEach(RadarrFilter.allCases) { option in
              Text(option.displayName).tag(option)
            }
          }
        }
        .accessibilityIdentifier("radarr.library.options")
      }
    }
    .overlay {
      // Three empty states, not one: an empty library, a filter that matched
      // nothing, and a search that matched nothing are three different things
      // to tell someone.
      if movies.isEmpty {
        ContentUnavailableView(
          "No Movies", systemImage: "film",
          description: Text("This Radarr has nothing in its library yet.")
        )
        .accessibilityIdentifier("radarr.library.empty")
      } else if store.isFilteredToNothing {
        ContentUnavailableView(
          "No Matches", systemImage: "line.3.horizontal.decrease.circle",
          description: Text("No movies are \(store.filter.displayName.lowercased()).")
        )
        .accessibilityIdentifier("radarr.library.noFilterMatch")
      } else if store.filteredMovies.isEmpty {
        ContentUnavailableView.search
      }
    }
    .refreshable { await store.refresh() }
    .task { await store.loadQualityProfiles() }
    .sheet(item: $addStore) { add in
      RadarrAddMovieView(store: add)
    }
  }
}

/// A movie or series id as a sheet item — `.sheet(item:)` needs
/// `Identifiable`, and a bare `Int` isn't.
struct HistoryTargetID: Identifiable {
  let id: Int
}
