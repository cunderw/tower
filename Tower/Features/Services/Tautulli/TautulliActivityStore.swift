import Foundation
import Observation
import TowerCore
import TowerData

/// Tautulli's activity screen: who is watching what, right now.
///
/// **Terminating removes the row locally rather than refetching.** Tautulli's
/// `get_activity` reads
/// Plex's session list, which keeps a terminated session for a beat while the
/// player notices, so a refetch straight after a terminate usually returns the
/// stream still playing and the row reappears before vanishing again. The row
/// goes the moment Tautulli accepts the call, and the next poll reconciles.
@MainActor
@Observable
final class TautulliActivityStore: RefreshableStore {
  var state: Loadable<TautulliActivity> = .idle
  let loads = LoadTracker()

  /// Streams with a terminate in flight, so their row can say so and can't be
  /// terminated twice.
  private(set) var terminating: Set<String> = []
  private(set) var actionError: AppError?

  private(set) var lastActionSuccess = 0
  private(set) var lastActionFailure = 0

  let repository: any TautulliRepositoryProtocol

  init(repository: any TautulliRepositoryProtocol) {
    self.repository = repository
  }

  // MARK: - Loading

  func load() async {
    await load { [self] in try await repository.activity() }
  }

  /// Never passes through `.loading`: this screen polls every 30 seconds, and
  /// a spinner every 30 seconds over a list that is already correct would be
  /// the most visible thing on it.
  func refresh() async {
    guard state.value != nil else { return await load() }
    await mutate { [self] in try await repository.activity() }
  }

  // MARK: - Terminating

  func isTerminating(_ session: TautulliSession) -> Bool {
    terminating.contains(session.sessionKey)
  }

  /// Whether Tower can stop this stream at all. Tautulli's terminate takes a
  /// session key, and a session that arrived without one can only be watched.
  func canTerminate(_ session: TautulliSession) -> Bool {
    !session.sessionKey.isEmpty
  }

  func terminate(_ session: TautulliSession, message: String?) async {
    guard canTerminate(session), !isTerminating(session) else { return }
    terminating.insert(session.sessionKey)
    defer { terminating.remove(session.sessionKey) }

    do {
      try await repository.terminate(sessionKey: session.sessionKey, message: message)
      actionError = nil
      lastActionSuccess += 1
      remove(session)
    } catch {
      let failure = AppError.wrapping(error)
      actionError = failure
      lastActionFailure += 1
      // The list keeps whatever it had: a failed terminate must not take the
      // stream off screen, or the user believes it worked.
      if let activity = state.value {
        state = .actionFailed(activity, failure)
      }
    }
  }

  /// Drops the stream and moves the counters with it, so the header can't say
  /// "3 streams" over a list of two.
  private func remove(_ session: TautulliSession) {
    guard let activity = state.value else { return }
    let sessions = activity.sessions.filter { $0.sessionKey != session.sessionKey }
    state = .loaded(
      TautulliActivity(
        streamCount: sessions.count,
        directPlayCount: sessions.filter { $0.decision == .directPlay }.count,
        directStreamCount: sessions.filter { $0.decision == .directStream }.count,
        transcodeCount: sessions.filter { $0.decision == .transcode }.count,
        // Bandwidth is the server's, not the sum of the rows' — subtracting
        // this stream's share is the honest local estimate until the next poll.
        totalBandwidthKbps: max(0, activity.totalBandwidthKbps - session.bandwidthKbps),
        lanBandwidthKbps: session.location == .lan
          ? max(0, activity.lanBandwidthKbps - session.bandwidthKbps)
          : activity.lanBandwidthKbps,
        wanBandwidthKbps: session.location == .lan
          ? activity.wanBandwidthKbps
          : max(0, activity.wanBandwidthKbps - session.bandwidthKbps),
        sessions: sessions))
  }

  // MARK: - History, users, and libraries

  /// Loaded on first visit and kept, like every other service's secondary
  /// sections. Activity stays the store's `state` because it is the screen's
  /// primary content and the only one that polls.
  var history: Loadable<TautulliHistoryPage> = .idle
  var users: Loadable<[TautulliUser]> = .idle
  var libraries: Loadable<[TautulliLibrary]> = .idle

  /// The history filters, which compose: user, media type, and search are sent
  /// together and narrowed by Tautulli in SQL.
  var historyFilter = TautulliHistoryFilter() {
    didSet { if historyFilter != oldValue { historyReloadToken += 1 } }
  }
  /// Bumped whenever the filter changes, so a view's `.task(id:)` refetches
  /// rather than the store polling for a change it can see directly.
  private(set) var historyReloadToken = 0

  /// One page. Tautulli filters server-side, so a bigger page is the only
  /// honest way to show more — a client-side filter over 50 rows would search
  /// only those 50 and look broken.
  static let historyPageSize = 100

  /// The filter the page in `history` was fetched with. A user's "Filter
  /// History" changes the filter while History is off screen, so arriving there
  /// has to notice that the page it kept answers a different question.
  private var historyFetchedFilter: TautulliHistoryFilter?

  func loadHistory(force: Bool = false) async {
    await fetchHistory(force: force || historyFetchedFilter != historyFilter)
  }

  /// Refetches history for the current filter, keeping whatever is on screen
  /// until the new page arrives.
  func reloadHistory() async {
    await fetchHistory(force: true)
  }

  /// Commits its own result rather than going through `fill`, because two
  /// history fetches can be in flight at once: the section's first load and a
  /// filter's reload are separate view tasks, and each search keystroke
  /// cancels the previous one's. A page for a filter that has since changed is
  /// dropped, so a late one can't sit under the newer filter. A cancelled fetch
  /// is dropped too, rather than shown as an error, because the fetch that
  /// replaced it fills the list; returning to History refetches when none did.
  private func fetchHistory(force: Bool) async {
    if !force, history.value != nil { return }
    let filter = historyFilter
    if history.value == nil { history = .loading }
    do {
      let page = try await repository.history(
        filter: filter, start: 0, length: Self.historyPageSize)
      guard filter == historyFilter else { return }
      history = .loaded(page)
      historyFetchedFilter = filter
    } catch {
      let failure = AppError.wrapping(error)
      guard filter == historyFilter, failure != .cancelled, !Task.isCancelled else { return }
      history = .failed(failure)
    }
  }

  func loadUsers(force: Bool = false) async {
    await fill(\.users, force: force) { [self] in try await repository.users() }
  }

  func loadLibraries(force: Bool = false) async {
    await fill(\.libraries, force: force) { [self] in try await repository.libraries() }
  }

  /// One user's history, for the drill-in. Kept out of `history` so opening a
  /// user doesn't destroy the filter the list behind it is showing.
  func history(for user: TautulliUser) async -> Loadable<TautulliHistoryPage> {
    do {
      return .loaded(
        try await repository.history(
          filter: TautulliHistoryFilter(userID: user.id), start: 0,
          length: Self.historyPageSize))
    } catch {
      return .failed(AppError.wrapping(error))
    }
  }

  /// Loads one section on first visit and keeps what it got. Addressed by key
  /// path rather than `inout`, which can't cross an `await` on an isolated
  /// property — the same helper `BazarrStore` carries, for the same reason.
  private func fill<Value: Sendable>(
    _ keyPath: ReferenceWritableKeyPath<TautulliActivityStore, Loadable<Value>>,
    force: Bool,
    _ work: @escaping () async throws -> Value
  ) async {
    if !force, self[keyPath: keyPath].value != nil { return }
    if self[keyPath: keyPath].value == nil { self[keyPath: keyPath] = .loading }
    do {
      self[keyPath: keyPath] = .loaded(try await work())
    } catch {
      self[keyPath: keyPath] = .failed(AppError.wrapping(error))
    }
  }

  /// Whether any history filter is narrowing the list — what the empty state
  /// reads to tell "no history" apart from "nothing matched".
  var isHistoryFiltered: Bool {
    historyFilter.userID != nil
      || historyFilter.mediaType?.isEmpty == false
      || historyFilter.search?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
  }

  /// The name behind `historyFilter.userID`, so the filter chip can say
  /// "Casey" rather than "user 5".
  func userName(id: Int) -> String? {
    (users.value ?? []).first { $0.id == id }?.name
  }

  // MARK: - Derived

  var sessions: [TautulliSession] {
    // Transcodes first: they are the streams costing the server work, and the
    // reason to open this screen when something is struggling.
    (state.value?.sessions ?? []).sorted {
      if $0.isTranscoding != $1.isTranscoding { return $0.isTranscoding }
      return $0.user.localizedCaseInsensitiveCompare($1.user) == .orderedAscending
    }
  }

  var isEmpty: Bool {
    guard let activity = state.value else { return false }
    return activity.sessions.isEmpty
  }
}
