import SwiftUI
import TowerCore

/// Search Overseerr and file a request.
struct OverseerrSearchView: View {
  @Bindable var store: OverseerrSearchStore
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      content
        .navigationTitle("Request Media")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $store.searchText, prompt: "Search movies and series")
        .onSubmit(of: .search) { Task { await store.search() } }
        .sensoryFeedback(.success, trigger: store.lastActionSuccess)
        .sensoryFeedback(.error, trigger: store.lastActionFailure)
        .toolbar {
          ToolbarItem(placement: .cancellationAction) {
            Button("Done") { dismiss() }
          }
        }
        .sheet(item: $store.requesting) { _ in
          RequestSheet(store: store)
        }
    }
  }

  @ViewBuilder
  private var content: some View {
    switch store.state {
    case .idle:
      ContentUnavailableView(
        "Search Overseerr", systemImage: "magnifyingglass",
        description: Text("Find a film or series to request.")
      )
      .accessibilityIdentifier("overseerr.search.prompt")
    case .loading:
      ProgressView()
    case .failed(let error):
      ContentUnavailableView {
        Label(error.message, systemImage: "exclamationmark.triangle")
      } description: {
        if let suggestion = error.serviceRecoverySuggestion { Text(suggestion) }
      }
      .accessibilityIdentifier("overseerr.search.error")
    case .loaded(let results), .actionFailed(let results, _):
      if results.isEmpty {
        ContentUnavailableView(
          "No Results", systemImage: "magnifyingglass",
          description: Text("Nothing matched “\(store.lastSearchedTerm)”.")
        )
        .accessibilityIdentifier("overseerr.search.empty")
      } else {
        List(results) { result in
          SearchResultRow(
            result: result,
            state: store.stateDescription(for: result),
            isRequestable: store.isRequestable(result)
          ) {
            Task { await store.beginRequest(for: result) }
          }
        }
      }
    }
  }
}

/// One search hit: poster, title, year, and either a Request button or the
/// state that replaces it.
struct SearchResultRow: View {
  let result: OverseerrSearchResult
  /// Non-nil when this can't be requested — what the row says instead.
  let state: String?
  let isRequestable: Bool
  let request: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      DashboardRow(showsChevron: false) {
        MediaPoster(
          url: result.posterURL,
          fallbackSystemImage: result.mediaType == .tv ? "tv" : "film")

        VStack(alignment: .leading, spacing: 3) {
          Text(result.title)
            .font(.body)
            .lineLimit(2)
          HStack(spacing: 6) {
            Text(result.mediaType.displayName)
            if let year = result.year {
              Text("·")
              Text(String(year))
            }
          }
          .font(.caption)
          .foregroundStyle(.secondary)
          if let overview = result.overview {
            Text(overview)
              .font(.caption2)
              .foregroundStyle(.secondary)
              .lineLimit(2)
          }
        }

        Spacer(minLength: 4)
      }
      .accessibilityElement(children: .combine)
      .accessibilityLabel(accessibilityLabel)
      .accessibilityIdentifier("overseerr.result.\(result.id)")

      // **Outside the combined element**, so the button keeps its own identity
      // and identifier (an identifier on a container overwrites its children's).
      if isRequestable {
        Button("Request", systemImage: "plus.circle") { request() }
          .buttonStyle(.borderless)
          .font(.caption)
          .accessibilityIdentifier("overseerr.result.\(result.id).request")
      } else if let state {
        // The state *instead of* a button — offering Request on something
        // already available files a duplicate that Overseerr rejects, which
        // reads to the user as the app being broken.
        Label(state, systemImage: "checkmark.circle.fill")
          .font(.caption)
          .foregroundStyle(.green)
          .accessibilityIdentifier("overseerr.result.\(result.id).state")
      }
    }
  }

  private var accessibilityLabel: String {
    var parts = [result.title, result.mediaType.displayName]
    if let year = result.year { parts.append(String(year)) }
    if let state { parts.append(state) }
    return parts.joined(separator: ", ")
  }
}

/// The confirm step: one button for a movie, a season picker for a series.
struct RequestSheet: View {
  @Bindable var store: OverseerrSearchStore

  var body: some View {
    NavigationStack {
      Group {
        if let draft = store.requesting {
          form(draft)
        } else {
          ProgressView()
        }
      }
      .navigationTitle(store.requesting?.result.title ?? "Request")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { store.cancelRequest() }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Request") { Task { _ = await store.submit() } }
            .disabled(!(store.requesting?.canSubmit ?? false))
            .accessibilityIdentifier("overseerr.request.confirm")
        }
      }
    }
  }

  @ViewBuilder
  private func form(_ draft: RequestDraft) -> some View {
    Form {
      if let error = draft.error {
        Section {
          Text(error.message)
            .font(.caption)
            .foregroundStyle(.red)
            .accessibilityIdentifier("overseerr.request.error")
        }
      }

      if draft.isTV {
        seasonSection(draft)
      } else {
        Section {
          // A movie is one confirm — nothing to choose, so the sheet says what
          // will happen rather than presenting an empty form.
          Text("Request this film.")
            .font(.callout)
            .foregroundStyle(.secondary)
            .accessibilityIdentifier("overseerr.request.movieSummary")
        }
      }

      Section {
        Toggle("Request in 4K", isOn: Binding(
          get: { store.requesting?.is4K ?? false },
          set: { newValue in
            guard var draft = store.requesting else { return }
            draft.is4K = newValue
            store.requesting = draft
          }))
          .accessibilityIdentifier("overseerr.request.is4k")
      }
    }
    .overlay {
      if draft.isSubmitting { ProgressView().controlSize(.large) }
    }
  }

  @ViewBuilder
  private func seasonSection(_ draft: RequestDraft) -> some View {
    switch draft.seasons {
    case .idle, .loading:
      Section { ProgressView() }
    case .failed(let error):
      Section {
        Text(error.message)
          .font(.caption)
          .foregroundStyle(.red)
          .accessibilityIdentifier("overseerr.request.seasonsError")
      }
    case .loaded(let seasons), .actionFailed(let seasons, _):
      Section {
        ForEach(seasons) { season in
          Button {
            store.toggleSeason(season.seasonNumber)
          } label: {
            HStack {
              VStack(alignment: .leading, spacing: 2) {
                Text(season.displayName)
                Text(Formatters.count(season.episodeCount, "episode"))
                  .font(.caption2)
                  .foregroundStyle(.secondary)
              }
              Spacer()
              // A checkmark rather than a `Toggle`: tapping a Toggle row does
              // nothing in this app — only the switch responds (CLAUDE.md,
              // "Tapping a SwiftUI `Toggle` row does nothing") — and a
              // whole-row tap is the right target here.
              if draft.selectedSeasons.contains(season.seasonNumber) {
                Image(systemName: "checkmark")
                  .foregroundStyle(.tint)
              }
            }
          }
          .buttonStyle(.plain)
          .accessibilityIdentifier("overseerr.request.season.\(season.seasonNumber)")
          .accessibilityAddTraits(
            draft.selectedSeasons.contains(season.seasonNumber) ? [.isSelected] : [])
        }
      } header: {
        HStack {
          Text("Seasons")
          Spacer()
          Button(draft.isEverySeasonSelected ? "None" : "All") {
            if draft.isEverySeasonSelected {
              store.clearSeasonSelection()
            } else {
              store.selectAllSeasons()
            }
          }
          .font(.caption)
          .accessibilityIdentifier("overseerr.request.seasonsToggleAll")
        }
      } footer: {
        if draft.selectedSeasons.isEmpty {
          Text("Pick at least one season.")
            .foregroundStyle(.orange)
        }
      }
    }
  }
}
