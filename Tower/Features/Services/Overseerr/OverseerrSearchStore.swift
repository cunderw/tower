import Foundation
import Observation
import TowerCore
import TowerData

/// Overseerr's search-and-request flow — filing a request without
/// opening the web UI.
///
/// **Search is explicit, not as-you-type.** Every keystroke here is a TMDB
/// round trip through Overseerr, and the *arr add flows in this app already
/// submit on the keyboard's Search key. Matching them keeps one habit rather
/// than two.
@MainActor
@Observable
final class OverseerrSearchStore: LoadingStore, Identifiable {
  let id = UUID()

  var state: Loadable<[OverseerrSearchResult]> = .idle
  let loads = LoadTracker()

  var searchText: String = ""
  /// The term the current results belong to, so the empty state can say what
  /// found nothing rather than "no results" against a box the user has since
  /// retyped.
  private(set) var lastSearchedTerm: String = ""

  /// The result whose request sheet is open, if any.
  var requesting: RequestDraft?

  private(set) var lastActionSuccess = 0
  private(set) var lastActionFailure = 0
  /// Results already requested during this session, so the row updates without
  /// a second search. Overseerr's own `mediaInfo` only refreshes on re-query.
  private(set) var requestedIDs: Set<Int> = []

  private let repository: any OverseerrRepositoryProtocol
  /// Told about a new request so the list behind the sheet shows it.
  private let requestsStore: OverseerrRequestsStore?

  init(
    repository: any OverseerrRepositoryProtocol,
    requestsStore: OverseerrRequestsStore? = nil
  ) {
    self.repository = repository
    self.requestsStore = requestsStore
  }

  var canSearch: Bool {
    !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  func search() async {
    let term = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !term.isEmpty else { return }
    lastSearchedTerm = term
    await load { [self] in try await repository.search(term: term) }
  }

  /// Whether this result can still be requested, accounting for what has been
  /// requested since the search ran.
  func isRequestable(_ result: OverseerrSearchResult) -> Bool {
    !result.isAlreadyInLibrary && !requestedIDs.contains(result.id)
  }

  /// What the row says instead of offering a button.
  func stateDescription(for result: OverseerrSearchResult) -> String? {
    if requestedIDs.contains(result.id) { return "Requested" }
    guard result.isAlreadyInLibrary else { return nil }
    return result.mediaStatus?.displayName
  }

  // MARK: - Requesting

  /// Opens the request flow for a result.
  ///
  /// A movie is one confirm; a series needs its seasons, which means a second
  /// call before anything can be shown — so the draft carries a `Loadable` for
  /// them rather than blocking the tap.
  func beginRequest(for result: OverseerrSearchResult) async {
    guard isRequestable(result) else { return }
    var draft = RequestDraft(result: result)
    requesting = draft

    guard result.mediaType == .tv else { return }
    draft.seasons = .loading
    requesting = draft
    do {
      let seasons = try await repository.seasons(tmdbID: result.id)
      draft.seasons = .loaded(seasons)
      // Everything selected by default: "I want the show" is the common ask,
      // and an empty selection would make the confirm button start disabled.
      draft.selectedSeasons = Set(seasons.map(\.seasonNumber))
      requesting = draft
    } catch {
      draft.seasons = .failed(AppError.wrapping(error))
      requesting = draft
    }
  }

  func toggleSeason(_ seasonNumber: Int) {
    guard var draft = requesting else { return }
    if draft.selectedSeasons.contains(seasonNumber) {
      draft.selectedSeasons.remove(seasonNumber)
    } else {
      draft.selectedSeasons.insert(seasonNumber)
    }
    requesting = draft
  }

  func selectAllSeasons() {
    guard var draft = requesting, let seasons = draft.seasons.value else { return }
    draft.selectedSeasons = Set(seasons.map(\.seasonNumber))
    requesting = draft
  }

  func clearSeasonSelection() {
    guard var draft = requesting else { return }
    draft.selectedSeasons = []
    requesting = draft
  }

  /// Submits the draft. Returns true when the sheet should close.
  func submit() async -> Bool {
    guard var draft = requesting, draft.canSubmit else { return false }
    draft.isSubmitting = true
    draft.error = nil
    requesting = draft

    let seasons = draft.result.mediaType == .tv
      // All of them selected means "the whole series", which the DTO sends as
      // an omitted key rather than an explicit list — the same thing, and what
      // Overseerr's own UI does.
      ? (draft.isEverySeasonSelected ? [] : draft.selectedSeasons.sorted())
      : []

    do {
      _ = try await repository.submit(
        SubmitRequest(
          mediaType: draft.result.mediaType, mediaID: draft.result.id, seasons: seasons,
          is4K: draft.is4K))
      requestedIDs.insert(draft.result.id)
      lastActionSuccess += 1
      requesting = nil
      // A new request has to appear in the requests list, so the list is
      // re-read rather than the sheet simply closing on a 200.
      await requestsStore?.load()
      return true
    } catch {
      draft.isSubmitting = false
      // The sheet stays open carrying the season selection: a rejected request
      // is usually a permissions problem, not a reason to pick seasons again.
      draft.error = AppError.wrapping(error)
      requesting = draft
      lastActionFailure += 1
      return false
    }
  }

  func cancelRequest() { requesting = nil }
}

/// The in-progress request. A value type, so a half-filled season selection
/// can't outlive the sheet that owns it.
struct RequestDraft: Identifiable, Sendable {
  let result: OverseerrSearchResult
  var seasons: Loadable<[OverseerrSeason]> = .idle
  var selectedSeasons: Set<Int> = []
  var is4K = false
  var isSubmitting = false
  var error: AppError?

  var id: Int { result.id }

  var isTV: Bool { result.mediaType == .tv }

  var isEverySeasonSelected: Bool {
    guard let seasons = seasons.value, !seasons.isEmpty else { return false }
    return selectedSeasons.count == seasons.count
  }

  /// A movie is always submittable; a series needs at least one season, and
  /// needs its season list to have arrived.
  var canSubmit: Bool {
    guard !isSubmitting else { return false }
    guard isTV else { return true }
    return !selectedSeasons.isEmpty
  }
}
