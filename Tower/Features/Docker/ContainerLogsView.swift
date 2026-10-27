import SwiftUI
import TowerCore
import TowerData

/// Route value `ContainerDetailView` pushes to reach the log viewer —
/// deliberately not `Container.ID` itself, which `DockerListView`'s
/// `ListDetailScaffold` already uses to open `ContainerDetailView`;
/// reusing that value type here would make pushing logs indistinguishable
/// from re-navigating to the container's own detail screen. `containerName`
/// rides along only for the navigation title — unlike `ContainerDetailView`,
/// which re-resolves its `Container` from `DockerStore` on every render
/// because its state/status/actions can change while the screen is open,
/// nothing about a container's *name* is expected to change while its log
/// viewer is open, so there's no staleness concern in snapshotting
/// it here.
struct ContainerLogsRoute: Hashable {
  let containerID: Container.ID
  let containerName: String
}

/// Pushed from `ContainerDetailView` via `navigationDestination(for:
/// ContainerLogsRoute.self)`, which `DockerListView` declares on the
/// `ContainerDetailView` inside `ListDetailScaffold`'s detail closure.
///
/// Owns its `ContainerLogsStore` via `@State`, exactly like `RootView` owns
/// `dockerStore`/`dashboardStore`: the store is constructed once, in `init`,
/// and `@State` preserves that one instance across re-renders regardless of
/// how many times this view's `init` runs — which matters here because the
/// `navigationDestination` closure that builds this view re-evaluates
/// whenever `DockerListView`'s own body does (e.g. on every 30-second poll),
/// and a fresh `ContainerLogsStore` on every one of those would silently
/// throw away already-loaded log lines and refetch from scratch.
struct ContainerLogsView: View {
  @State private var store: ContainerLogsStore
  let containerName: String

  init(store: ContainerLogsStore, containerName: String) {
    self._store = State(initialValue: store)
    self.containerName = containerName
  }

  var body: some View {
    content
      .navigationTitle("Logs")
      .navigationBarTitleDisplayMode(.inline)
      .task { await store.load() }
  }

  @ViewBuilder
  private var content: some View {
    switch store.state {
    case .idle, .loading:
      LoadingStateView(title: "Loading logs…", isLoadInFlight: store.isLoadInFlight) {
        store.cancelLoad()
      }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    case .failed(let error):
      // Same shape as `DockerListView`'s error branch — see its doc comment
      // for why the retry button is a sibling of `ContentUnavailableView`
      // rather than passed as its `actions:` closure.
      VStack(spacing: 16) {
        ContentUnavailableView {
          Label(error.message, systemImage: "exclamationmark.triangle")
        } description: {
          if let suggestion = error.recoverySuggestion { Text(suggestion) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("containerLogs.error")

        Button("Try Again") { Task { await store.load() } }
          .accessibilityIdentifier("containerLogs.retry")
      }
    case .loaded(let lines), .actionFailed(let lines, _):
      logList(lines)
    }
  }

  @ViewBuilder
  private func logList(_ lines: [ContainerLogLine]) -> some View {
    // Empty logs are a real state, not an error — a container that has
    // produced no output yet (or ever) renders this instead of an empty
    // `List`, matching `DockerListView`'s identical "zero containers" vs.
    // "search matched nothing" distinction one level up.
    if lines.isEmpty {
      ContentUnavailableView(
        "No Log Output", systemImage: "doc.plaintext",
        description: Text("\(containerName) hasn't produced any log output.")
      )
      .accessibilityIdentifier("containerLogs.empty")
    } else {
      List {
        if case .actionFailed(_, let error) = store.state {
          Text(error.message)
            .font(.caption)
            .foregroundStyle(.red)
        }
        // Unraid sends lines oldest-first, so the affordance that
        // reaches further back in history sits above the oldest line
        // currently on screen, not below the newest.
        if store.hasMore {
          loadMoreRow
        }
        ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
          logRow(line)
        }
      }
      .listStyle(.plain)
      // Enables selection for every `Text` this `List` contains — people
      // copy log lines into bug reports.
      .textSelection(.enabled)
    }
  }

  private var loadMoreRow: some View {
    Button {
      Task { await store.loadMore() }
    } label: {
      HStack {
        Spacer()
        if store.isLoadingMore {
          ProgressView()
        } else {
          Text("Load Earlier Lines")
        }
        Spacer()
      }
    }
    .disabled(store.isLoadingMore)
    .accessibilityIdentifier("containerLogs.loadMoreButton")
  }

  /// One log line: a secondary-styled, monospaced timestamp caption above a
  /// monospaced message — both scale with Dynamic Type like every other
  /// text in the app (checked at AX5). `line.timestamp` is `nil` whenever
  /// the wire value failed to parse; the caption is omitted for that line
  /// rather than shown as a placeholder, but the message underneath always
  /// renders regardless — a line is never dropped for having bad metadata.
  private func logRow(_ line: ContainerLogLine) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      if let timestamp = line.timestamp {
        Text(timestamp, format: .dateTime.hour().minute().second())
          .font(.system(.caption2, design: .monospaced))
          .foregroundStyle(.secondary)
      }
      Text(line.message)
        .font(.system(.footnote, design: .monospaced))
    }
    .padding(.vertical, 2)
  }
}

#Preview("Loaded, with earlier lines available") {
  NavigationStack {
    ContainerLogsView(
      store: .previewFixture(lines: .previewFixture, hasMore: true),
      containerName: "code-server"
    )
  }
}

#Preview("Empty logs") {
  NavigationStack {
    ContainerLogsView(
      store: .previewFixture(lines: [], hasMore: false),
      containerName: "freshrss"
    )
  }
}

#Preview("Failed") {
  NavigationStack {
    ContainerLogsView(
      store: .previewFixture(state: .failed(.serverUnreachable)),
      containerName: "code-server"
    )
  }
}

#Preview("Accessibility Size (AX5)") {
  NavigationStack {
    ContainerLogsView(
      store: .previewFixture(lines: .previewFixture, hasMore: true),
      containerName: "code-server"
    )
  }
  .environment(\.dynamicTypeSize, .accessibility5)
}

extension Array where Element == ContainerLogLine {
  fileprivate static var previewFixture: [ContainerLogLine] {
    [
      ContainerLogLine(
        timestamp: Formatters.parseTimestamp("2026-03-14T18:00:08.828Z"),
        message: "[2026-03-14T18:00:08.828Z] info  HTTP server listening on http://0.0.0.0:8443/"
      ),
      ContainerLogLine(
        timestamp: Formatters.parseTimestamp("2026-03-14T19:00:00.409Z"),
        message: "[2026-03-14T19:00:00.409Z] info  Session server listening on /config/data/code-server-ipc.sock"
      ),
      // Deliberately unparseable — exercises the "still renders the
      // message" rule directly in the preview, not just in a unit test.
      ContainerLogLine(timestamp: nil, message: "a line whose timestamp didn't parse still shows up"),
    ]
  }
}

extension ContainerLogsStore {
  /// Backs every `#Preview` above — none of them reach a live repository,
  /// so `store.load()`/`.loadMore()` never actually run; this only needs to
  /// stand up `state` (and `hasMore`) at whatever value the preview wants to
  /// render. Mirrors `ContainerDetailView`'s `PreviewDockerRepository`, one
  /// level up: that one satisfies the protocol for previews that never fire
  /// a mutation, this one skips the repository/store plumbing entirely for
  /// previews that never fire a fetch.
  fileprivate static func previewFixture(
    lines: [ContainerLogLine], hasMore: Bool
  ) -> ContainerLogsStore {
    previewFixture(state: .loaded(lines), hasMore: hasMore)
  }

  fileprivate static func previewFixture(
    state: Loadable<[ContainerLogLine]>, hasMore: Bool = false
  ) -> ContainerLogsStore {
    let store = ContainerLogsStore(repository: UnreachablePreviewDockerRepository(), containerID: "preview")
    store.state = state
    store.hasMore = hasMore
    return store
  }
}

/// A `DockerRepositoryProtocol` that never actually runs — see
/// `ContainerLogsStore.previewFixture(state:hasMore:)` above. Distinct from
/// `ContainerDetailView`'s own `PreviewDockerRepository`: that type lives in
/// a `private` scope in a different file, and this store only ever calls
/// `logs(id:tail:since:)`, none of the five mutation methods that file's
/// fixture exists to satisfy.
private struct UnreachablePreviewDockerRepository: DockerRepositoryProtocol {
  func containers() async throws -> [Container] { [] }
  func start(id: String) async throws -> ContainerStateUpdate { fatalError("not used in previews") }
  func stop(id: String) async throws -> ContainerStateUpdate { fatalError("not used in previews") }
  func restart(id: String) async throws -> ContainerStateUpdate { fatalError("not used in previews") }
  func pause(id: String) async throws -> ContainerStateUpdate { fatalError("not used in previews") }
  func unpause(id: String) async throws -> ContainerStateUpdate { fatalError("not used in previews") }
  func logs(id: String, tail: Int?, since: String?) async throws -> ContainerLogs {
    fatalError("not used in previews")
  }
}
