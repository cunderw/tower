import SwiftUI
import TowerCore

/// The server's log files, pushed from Settings.
struct LogFileListView: View {
  let store: LogFileStore

  var body: some View {
    content
      .navigationTitle("Logs")
      .task { await store.load() }
  }

  @ViewBuilder
  private var content: some View {
    switch store.state {
    case .idle, .loading:
      LoadingStateView(title: "Loading logs…", isLoadInFlight: store.isLoadInFlight) {
        store.cancelLoad()
      }
    case .failed(let error):
      VStack(spacing: 16) {
        ContentUnavailableView {
          Label(error.message, systemImage: "exclamationmark.triangle")
        } description: {
          if let suggestion = error.recoverySuggestion { Text(suggestion) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("logs.error")

        Button("Try Again") { Task { await store.load() } }
          .accessibilityIdentifier("logs.retry")
      }
    case .loaded(let files), .actionFailed(let files, _):
      fileList(files)
    }
  }

  @ViewBuilder
  private func fileList(_ files: [LogFile]) -> some View {
    List {
      if case .actionFailed(_, let error) = store.state {
        Text(error.message)
          .font(.caption)
          .foregroundStyle(.red)
      }
      ForEach(files) { file in
        // A **view-based** link, not `NavigationLink(value:)` with a
        // `navigationDestination(for:)`. Two reasons:
        //
        // 1. It has to work from here. This screen is itself pushed by a
        //    view-based link from `SettingsSheet`, and a
        //    `navigationDestination(for:)` declared inside such a view does not
        //    reliably register with the enclosing stack, and the tap navigates
        //    nowhere.
        // 2. The push-an-identifier rule doesn't apply. It exists because a pushed
        //    *snapshot* goes stale while the screen is open (a container's state
        //    changes under it, a disk's temperature moves). A log file's name and
        //    path don't change, and the viewer's actual content comes from its own
        //    store, which re-requests. Resolving from `LogFileStore` instead would
        //    make the viewer break if a refresh dropped the file from the list
        //    while someone was reading it.
        //
        // Building the viewer store in the closure is safe even though this
        // re-runs on every render: `LogFileView` holds it in `@State`, which only
        // installs the first time — the same pattern `ContainerLogsView` uses.
        NavigationLink {
          LogFileView(store: store.makeViewerStore(for: file))
        } label: {
          row(file)
        }
      }
    }
    .overlay {
      if files.isEmpty {
        ContentUnavailableView(
          "No Logs", systemImage: "doc.plaintext",
          description: Text("This server reported no log files.")
        )
        .accessibilityIdentifier("logs.empty")
      }
    }
    .refreshable { await store.refresh() }
  }

  private func row(_ file: LogFile) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(file.name)
        .font(.body)
      Text(subtitle(for: file))
        .font(.caption)
        .foregroundStyle(.secondary)
    }
    .accessibilityElement(children: .combine)
    .accessibilityIdentifier("logs.row.\(file.name)")
  }

  /// "51 KB · 2 hours ago", or "Empty" for a 0-byte file — Unraid keeps several
  /// empty log files, and saying so up front beats opening one to a blank screen.
  private func subtitle(for file: LogFile) -> String {
    var parts: [String] = []
    parts.append(file.isEmpty ? "Empty" : Formatters.bytes(Int64(file.sizeBytes)))
    if let modifiedAt = file.modifiedAt {
      parts.append(modifiedAt.formatted(.relative(presentation: .named)))
    }
    return parts.joined(separator: " · ")
  }
}
