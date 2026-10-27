import Foundation
import Observation
import TowerCore
import TowerData

/// The list of the server's log files.
///
/// Read-only and unpolled, unlike the tab stores: a list of log files changes on
/// the order of minutes, the sheet it lives in is short-lived, and re-requesting
/// dozens of file stats behind a Settings screen nobody is looking at would be waste.
/// Pull-to-refresh is the manual lever.
@MainActor
@Observable
final class LogFileStore: LoadingStore {
  var state: Loadable<[LogFile]> = .idle

  /// The one line `LoadingStore` needs per store — see `LoadTracker` for why it
  /// can't live in the protocol extension.
  let loads = LoadTracker()

  private let repository: any LogRepositoryProtocol

  init(repository: any LogRepositoryProtocol) {
    self.repository = repository
  }

  func load() async {
    await load { [self] in try await repository.logFiles() }
  }

  /// Pull-to-refresh. Keeps the last good list on a failure rather than blanking
  /// a screen someone is reading.
  func refresh() async {
    guard state.value != nil else { return await load() }
    await mutate { try await repository.logFiles() }
  }

  /// Builds a viewer store for one file, sharing this store's repository — the
  /// same factory shape `DockerStore.makeLogsStore(containerID:)` uses, and for the
  /// same reason: `repository` stays private and callers don't need to know what
  /// backs it.
  func makeViewerStore(for file: LogFile) -> LogViewerStore {
    LogViewerStore(repository: repository, file: file)
  }
}

/// One log file's contents, with a "load more" that reaches further back.
@MainActor
@Observable
final class LogViewerStore: LoadingStore {
  var state: Loadable<LogFileContents> = .idle

  /// See `LoadTracker`.
  let loads = LoadTracker()
  /// The file this viewer is showing. Held so the view can title itself and so
  /// `loadMore()` knows what to re-request.
  let file: LogFile
  /// How many lines the next request will ask for. Raised by `loadMore()`.
  private(set) var requestedLines = LogViewerStore.initialLines
  private(set) var isLoadingMore = false

  /// Enough to fill a screen several times over without pulling a 51 KB
  /// `docker.log` in one request.
  static let initialLines = 200
  /// Each "load more" quadruples the window rather than adding a fixed page.
  ///
  /// The API has no cursor and no offset for this query — `lines` counts back from
  /// the end — so reaching further means re-requesting a *larger* tail, and every
  /// step re-downloads everything already shown. Growing by a fixed factor keeps
  /// the number of round trips logarithmic in how far back someone scrolls, where
  /// a fixed increment would make it linear with each request bigger than the
  /// last. Same constraint `ContainerLogsStore` documents for the `tail` of
  /// `logs(id:tail:since:)`.
  static let growthFactor = 4

  private let repository: any LogRepositoryProtocol

  init(repository: any LogRepositoryProtocol, file: LogFile) {
    self.repository = repository
    self.file = file
  }

  func load() async {
    await load { [self, file, requestedLines] in
      try await repository.logFile(path: file.path, lines: requestedLines)
    }
  }

  /// Re-requests with a larger window. A no-op when everything is already on
  /// screen, so a button that can't do anything is never offered.
  func loadMore() async {
    guard let contents = state.value, contents.isTruncated, !isLoadingMore else { return }
    isLoadingMore = true
    defer { isLoadingMore = false }

    let widened = requestedLines * Self.growthFactor
    // The window is only widened once the larger request *succeeds*: raising it
    // first would leave the store claiming to have asked for more than it holds,
    // and the next `loadMore()` would skip a step.
    guard let refreshed = try? await repository.logFile(path: file.path, lines: widened) else { return }
    requestedLines = widened
    state = .loaded(refreshed)
  }

  /// Pull-to-refresh at the current window size, for a log that is still being
  /// written.
  func refresh() async {
    guard state.value != nil else { return await load() }
    await mutate { [file, requestedLines] in
      try await repository.logFile(path: file.path, lines: requestedLines)
    }
  }
}
