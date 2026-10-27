import SwiftUI
import TowerCore

/// One log file's contents: monospaced, scrolled to the end, with a "load more"
/// that reaches further back.
struct LogFileView: View {
  @State var store: LogViewerStore

  /// The id of the last line, for the initial scroll-to-bottom. Lines are
  /// identified by index because log lines repeat verbatim all the time — two
  /// identical daemon messages are not the same row.
  private static let bottomAnchor = "log.bottom"

  var body: some View {
    content
      .navigationTitle(store.file.name)
      .navigationBarTitleDisplayMode(.inline)
      .task { await store.load() }
  }

  @ViewBuilder
  private var content: some View {
    switch store.state {
    case .idle, .loading:
      LoadingStateView(title: "Loading \(store.file.name)…", isLoadInFlight: store.isLoadInFlight) {
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
        .accessibilityIdentifier("logFile.error")

        Button("Try Again") { Task { await store.load() } }
          .accessibilityIdentifier("logFile.retry")
      }
    case .loaded(let contents), .actionFailed(let contents, _):
      if contents.lines.isEmpty {
        // A real state, not a failure: Unraid keeps several log files at
        // 0 bytes. The list already labels them "Empty"; this is what happens if
        // someone opens one anyway.
        ContentUnavailableView(
          "Empty Log", systemImage: "doc.plaintext",
          description: Text("\(store.file.name) has no contents.")
        )
        .accessibilityIdentifier("logFile.empty")
      } else {
        lines(contents)
      }
    }
  }

  private func lines(_ contents: LogFileContents) -> some View {
    ScrollViewReader { proxy in
      ScrollView {
        VStack(alignment: .leading, spacing: 2) {
          if contents.isTruncated {
            loadMoreButton(contents)
          }
          // Indexed rather than keyed by content: log lines repeat verbatim
          // constantly, and two identical messages are two different rows.
          ForEach(Array(contents.lines.enumerated()), id: \.offset) { _, line in
            Text(line)
              .font(.system(.caption, design: .monospaced))
              .textSelection(.enabled)
              .frame(maxWidth: .infinity, alignment: .leading)
          }
          // A zero-height anchor to scroll to, rather than scrolling to the last
          // line — which would leave that line at the *top* of the viewport.
          Color.clear
            .frame(height: 1)
            .id(Self.bottomAnchor)
        }
        .padding(.horizontal)
      }
      .accessibilityIdentifier("logFile.contents")
      .onAppear {
        // A log is read newest-first, and the newest lines are at the end.
        proxy.scrollTo(Self.bottomAnchor, anchor: .bottom)
      }
      .refreshable { await store.refresh() }
      .safeAreaInset(edge: .bottom) { lineCountFooter(contents) }
    }
  }

  private func loadMoreButton(_ contents: LogFileContents) -> some View {
    Button {
      Task { await store.loadMore() }
    } label: {
      if store.isLoadingMore {
        ProgressView()
          .controlSize(.small)
      } else {
        // Says what it will do, in the file's own terms — "Load Earlier Lines"
        // rather than "Load more", because in a log "more" is ambiguous about
        // which direction.
        Label("Load Earlier Lines", systemImage: "arrow.up")
          .font(.caption)
      }
    }
    .disabled(store.isLoadingMore)
    .frame(maxWidth: .infinity)
    .padding(.vertical, 8)
    .accessibilityIdentifier("logFile.loadMore")
  }

  /// "Showing 200 of 1,482 lines", or just the count when it's the whole file.
  /// The distinction matters: someone searching a log needs to know they are
  /// looking at a tail rather than the file.
  private func lineCountFooter(_ contents: LogFileContents) -> some View {
    Text(
      contents.isTruncated
        ? "Showing last \(contents.lines.count) of \(contents.totalLines) lines"
        : "\(contents.totalLines) lines"
    )
    .font(.caption2)
    .foregroundStyle(.secondary)
    .frame(maxWidth: .infinity)
    .padding(.vertical, 6)
    .background(.bar)
    .accessibilityIdentifier("logFile.lineCount")
  }
}
