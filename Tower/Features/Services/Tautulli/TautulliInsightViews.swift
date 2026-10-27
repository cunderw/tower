import SwiftUI
import TowerCore
import TowerData

/// Tautulli's history, users, and libraries sections.

// MARK: - History

/// Watch history, with filters that compose.
///
/// **Every filter is sent to Tautulli**, never applied to the page on screen.
/// Tautulli narrows in SQL against the whole database; filtering the hundred
/// rows already fetched would silently search only those hundred and read as
/// a broken search on any server with real history.
struct TautulliHistorySection: View {
  @Bindable var store: TautulliActivityStore

  /// Plex's own media types, plus "any". Tautulli's `media_type` takes these
  /// verbatim.
  private static let mediaTypes: [(label: String, value: String?)] = [
    ("All media", nil), ("Movies", "movie"), ("Episodes", "episode"), ("Music", "track"),
  ]

  var body: some View {
    VStack(spacing: 0) {
      filterBar
      list
    }
    // On the section rather than the list, so a search that matches nothing
    // keeps the field that clears it.
    .searchable(text: searchBinding, prompt: "Search history")
  }

  @ViewBuilder
  private var filterBar: some View {
    HStack(spacing: 8) {
      Menu {
        Picker("Media", selection: mediaBinding) {
          ForEach(Self.mediaTypes, id: \.label) { type in
            Text(type.label).tag(type.value)
          }
        }
      } label: {
        Label(mediaLabel, systemImage: "line.3.horizontal.decrease.circle")
          .font(.caption)
      }
      .accessibilityIdentifier("tautulli.history.mediaFilter")

      // Shown only when a user filter is on, because it is set by drilling
      // into a user rather than picked here — and it has to be removable
      // from the list it is narrowing.
      if let userID = store.historyFilter.userID {
        Button {
          store.historyFilter.userID = nil
        } label: {
          Label(store.userName(id: userID) ?? "One user", systemImage: "xmark.circle.fill")
            .font(.caption)
        }
        .buttonStyle(.borderless)
        .accessibilityIdentifier("tautulli.history.userFilter")
      }

      Spacer(minLength: 0)
    }
    .padding(.horizontal)
    .padding(.bottom, 4)
  }

  private var mediaBinding: Binding<String?> {
    Binding(
      get: { store.historyFilter.mediaType },
      set: { store.historyFilter.mediaType = $0 })
  }

  private var mediaLabel: String {
    Self.mediaTypes.first { $0.value == store.historyFilter.mediaType }?.label ?? "All media"
  }

  @ViewBuilder
  private var list: some View {
    switch store.history {
    case .idle, .loading:
      ProgressView()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    case .failed(let error):
      ContentUnavailableView {
        Label(error.message, systemImage: "exclamationmark.triangle")
      } description: {
        if let suggestion = error.serviceRecoverySuggestion { Text(suggestion) }
      }
      .accessibilityIdentifier("tautulli.history.error")
    case .loaded(let page), .actionFailed(let page, _):
      if page.records.isEmpty {
        // Which of the two nothings this is matters: a filter that matched
        // nothing is fixable, an empty database is not.
        ContentUnavailableView(
          store.isHistoryFiltered ? "No Matches" : "No History",
          systemImage: store.isHistoryFiltered ? "line.3.horizontal.decrease.circle" : "clock",
          description: Text(
            store.isHistoryFiltered
              ? "Nothing in Tautulli's history matches these filters."
              : "Tautulli hasn't recorded anything watched yet.")
        )
        .accessibilityIdentifier("tautulli.history.empty")
      } else {
        List {
          // "100 of 1,204" — the page is a page, and saying so stops the
          // count reading as the whole library's history.
          Text(countSummary(page))
            .font(.caption)
            .foregroundStyle(.secondary)
            .accessibilityIdentifier("tautulli.history.count")

          ForEach(page.records) { record in
            HistoryRow(record: record)
          }
        }
        .refreshable { await store.reloadHistory() }
      }
    }
  }

  private var searchBinding: Binding<String> {
    Binding(
      get: { store.historyFilter.search ?? "" },
      set: { store.historyFilter.search = $0.isEmpty ? nil : $0 })
  }

  private func countSummary(_ page: TautulliHistoryPage) -> String {
    let shown = page.records.count
    if store.isHistoryFiltered {
      return "\(shown) of \(page.filteredCount) matching · \(page.totalCount) total"
    }
    return shown < page.totalCount ? "\(shown) of \(page.totalCount)" : "\(shown) plays"
  }
}

struct HistoryRow: View {
  let record: TautulliHistoryRecord

  var body: some View {
    VStack(alignment: .leading, spacing: 3) {
      Text(record.title)
        .font(.callout)
        .lineLimit(2)
      if let subtitle = record.subtitle {
        Text(subtitle)
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      HStack(spacing: 6) {
        Text(record.user)
        if let player = record.player {
          Text("·")
          Text(player)
        }
        if record.decision != .unknown {
          Text("·")
          Text(record.decision.displayName)
        }
      }
      .font(.caption2)
      .foregroundStyle(.secondary)
      .lineLimit(1)

      HStack(spacing: 6) {
        Text(record.watchStatus.displayName)
          .foregroundStyle(record.watchStatus == .watched ? Color.green : Color.secondary)
        if record.watchStatus != .watched {
          Text("·")
          Text("\(record.percentComplete)%")
        }
        if record.playDurationSeconds > 0 {
          Text("·")
          // Through the shared formatter, so a play reads the same as an
          // uptime or a parity check.
          Text(Formatters.duration(seconds: record.playDurationSeconds))
        }
        if let date = record.date {
          Text("·")
          Text(date, format: .relative(presentation: .named))
        }
      }
      .font(.caption2)
      .foregroundStyle(.secondary)
      .lineLimit(1)
    }
    .accessibilityElement(children: .combine)
    .accessibilityIdentifier("tautulli.history.\(record.id)")
  }
}

// MARK: - Users

struct TautulliUsersSection: View {
  @Bindable var store: TautulliActivityStore

  var body: some View {
    LoadableList(state: store.users, emptyTitle: "No Users", identifier: "tautulli.users") {
      users in
      ForEach(users) { user in
        NavigationLink {
          TautulliUserDetailView(store: store, user: user)
        } label: {
          UserRow(user: user)
        }
      }
    }
    .refreshable { await store.loadUsers(force: true) }
  }
}

struct UserRow: View {
  let user: TautulliUser

  var body: some View {
    VStack(alignment: .leading, spacing: 3) {
      HStack(spacing: 6) {
        Text(user.name)
          .font(.callout)
        if !user.isActive {
          Text("Inactive")
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
      }
      HStack(spacing: 6) {
        Text("\(user.plays) play\(user.plays == 1 ? "" : "s")")
        if user.totalTimeSeconds > 0 {
          Text("·")
          Text(Formatters.duration(seconds: user.totalTimeSeconds))
        }
        if let lastSeen = user.lastSeen {
          Text("·")
          Text(lastSeen, format: .relative(presentation: .named))
        } else {
          Text("·")
          // A user who has never watched anything has no last-seen date, and
          // 1970 is what a naive epoch conversion would show instead.
          Text("Never seen")
        }
      }
      .font(.caption2)
      .foregroundStyle(.secondary)
      .lineLimit(1)

      if let lastPlayed = user.lastPlayed {
        Text(lastPlayed)
          .font(.caption2)
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }
    }
    .accessibilityElement(children: .combine)
    .accessibilityIdentifier("tautulli.user.\(user.id)")
  }
}

/// One user: their stats, and their history.
struct TautulliUserDetailView: View {
  @Bindable var store: TautulliActivityStore
  let user: TautulliUser

  @State private var history: Loadable<TautulliHistoryPage> = .idle

  var body: some View {
    List {
      Section("Stats") {
        LabeledContent("Plays", value: String(user.plays))
        LabeledContent(
          "Watch time", value: Formatters.duration(seconds: user.totalTimeSeconds))
        LabeledContent("Last seen") {
          if let lastSeen = user.lastSeen {
            Text(lastSeen, format: .relative(presentation: .named))
          } else {
            Text("Never")
          }
        }
        if let platform = user.platform {
          LabeledContent("Platform", value: platform)
        }
        if let player = user.player {
          LabeledContent("Player", value: player)
        }
      }

      Section("History") {
        switch history {
        case .idle, .loading:
          ProgressView()
        case .failed(let error):
          Text(error.message)
            .font(.caption)
            .foregroundStyle(.red)
            .accessibilityIdentifier("tautulli.user.history.error")
        case .loaded(let page), .actionFailed(let page, _):
          if page.records.isEmpty {
            Text("Nothing watched yet.")
              .foregroundStyle(.secondary)
              .accessibilityIdentifier("tautulli.user.history.empty")
          }
          ForEach(page.records) { record in
            HistoryRow(record: record)
          }
        }
      }
    }
    .navigationTitle(user.name)
    .navigationBarTitleDisplayMode(.inline)
    // Fetched with a `user_id` filter rather than sliced out of the list's
    // page: this user's hundredth play may be nowhere near the newest hundred.
    .task {
      guard history.value == nil else { return }
      history = .loading
      history = await store.history(for: user)
    }
    .toolbar {
      ToolbarItem(placement: .primaryAction) {
        Button("Filter History", systemImage: "line.3.horizontal.decrease.circle") {
          store.historyFilter.userID = user.id
        }
        .accessibilityIdentifier("tautulli.user.filterHistory")
      }
    }
  }
}

// MARK: - Libraries

struct TautulliLibrariesSection: View {
  @Bindable var store: TautulliActivityStore

  var body: some View {
    LoadableList(
      state: store.libraries, emptyTitle: "No Libraries", identifier: "tautulli.libraries"
    ) { libraries in
      ForEach(libraries) { library in
        LibraryRow(library: library)
      }
    }
    .refreshable { await store.loadLibraries(force: true) }
  }
}

struct LibraryRow: View {
  let library: TautulliLibrary

  var body: some View {
    VStack(alignment: .leading, spacing: 3) {
      HStack {
        Text(library.name)
          .font(.callout)
        Spacer(minLength: 8)
        Text(library.typeDisplayName)
          .font(.caption2)
          .foregroundStyle(.secondary)
      }
      Text(contents)
        .font(.caption2)
        .foregroundStyle(.secondary)
        .lineLimit(1)
      HStack(spacing: 6) {
        Text("\(library.plays) play\(library.plays == 1 ? "" : "s")")
        if library.totalTimeSeconds > 0 {
          Text("·")
          Text(Formatters.duration(seconds: library.totalTimeSeconds))
        }
        if let lastAccessed = library.lastAccessed {
          Text("·")
          Text(lastAccessed, format: .relative(presentation: .named))
        }
      }
      .font(.caption2)
      .foregroundStyle(.secondary)
      .lineLimit(1)
    }
    .accessibilityElement(children: .combine)
    .accessibilityIdentifier("tautulli.library.\(library.id)")
  }

  /// Counts spelled for the library's own type: a show library's interesting
  /// number is its episode count, not its show count alone.
  private var contents: String {
    switch (library.type ?? "").lowercased() {
    case "show":
      var parts = ["\(library.count) shows"]
      if let seasons = library.parentCount { parts.append("\(seasons) seasons") }
      if let episodes = library.childCount { parts.append("\(episodes) episodes") }
      return parts.joined(separator: " · ")
    case "artist":
      var parts = ["\(library.count) artists"]
      if let albums = library.parentCount { parts.append("\(albums) albums") }
      if let tracks = library.childCount { parts.append("\(tracks) tracks") }
      return parts.joined(separator: " · ")
    case "movie":
      return "\(library.count) film\(library.count == 1 ? "" : "s")"
    default:
      return "\(library.count) item\(library.count == 1 ? "" : "s")"
    }
  }
}
