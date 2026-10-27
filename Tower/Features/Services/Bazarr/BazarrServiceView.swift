import SwiftUI
import TowerCore
import TowerData

/// A Bazarr instance: wanted, the two libraries, providers, and history.
///
/// Five sections behind a segmented picker — the same shape as the *arr shell
/// and the NZBGet screen, without being either of them, because Bazarr shares
/// no client code with the *arrs.
struct BazarrServiceView: View {
  let instance: ServiceInstance
  @Bindable var store: BazarrStore

  @State private var section: Section = .wanted
  @State private var searchTarget: WantedSubtitle?

  enum Section: String, CaseIterable, Identifiable {
    case wanted, series, movies, providers, history

    var id: String { rawValue }

    var title: String {
      switch self {
      case .wanted: "Wanted"
      case .series: "Series"
      case .movies: "Movies"
      case .providers: "Providers"
      case .history: "History"
      }
    }

    var systemImage: String {
      switch self {
      case .wanted: "captions.bubble"
      case .series: "tv"
      case .movies: "film"
      case .providers: "antenna.radiowaves.left.and.right"
      case .history: "clock.arrow.circlepath"
      }
    }
  }

  var body: some View {
    VStack(spacing: 0) {
      Picker("Section", selection: $section) {
        ForEach(Section.allCases) { section in
          Label(section.title, systemImage: section.systemImage)
            .labelStyle(.iconOnly)
            .accessibilityLabel(section.title)
            .tag(section)
        }
      }
      .pickerStyle(.segmented)
      .padding(.horizontal)
      .padding(.bottom, 8)
      // On the control, not the enclosing stack.
      .accessibilityIdentifier("bazarr.sections")

      sectionContent
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    .navigationTitle(instance.name)
    .navigationBarTitleDisplayMode(.inline)
    .sensoryFeedback(.success, trigger: store.lastActionSuccess)
    .sensoryFeedback(.error, trigger: store.lastActionFailure)
    .task {
      await store.appeared()
    }
    .task(id: section) {
      switch section {
      case .series: await store.loadSeries()
      case .movies: await store.loadMovies()
      case .providers: await store.loadProviders()
      case .history: await store.loadHistory()
      case .wanted: break
      }
    }
    .sheet(item: $searchTarget) { item in
      SubtitleSearchView(store: store, item: item)
    }
  }

  @ViewBuilder
  private var sectionContent: some View {
    switch section {
    case .wanted: wantedSection
    case .series: library(store.series, identifier: "bazarr.series")
    case .movies: library(store.movies, identifier: "bazarr.movies")
    case .providers: providersSection
    case .history: historySection
    }
  }

  // MARK: - Wanted

  @ViewBuilder
  private var wantedSection: some View {
    switch store.state {
    case .idle, .loading:
      LoadingStateView(title: "Loading wanted…", isLoadInFlight: store.isLoadInFlight) {
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
        .accessibilityIdentifier("bazarr.error")
        Button("Try Again") { Task { await store.load() } }
          .accessibilityIdentifier("bazarr.retry")
      }
    case .loaded(let wanted), .actionFailed(let wanted, _):
      wantedList(wanted)
    }
  }

  private func wantedList(_ wanted: [WantedSubtitle]) -> some View {
    List {
      if let error = store.actionError {
        Text(error.message)
          .font(.caption)
          .foregroundStyle(.red)
          .accessibilityIdentifier("bazarr.actionError")
      }

      if !wanted.isEmpty {
        // Subtitles, not rows: one episode can be missing three languages, and
        // the number people care about is how many files are outstanding.
        Text("\(Formatters.count(store.missingCount, "subtitle")) wanted")
          .font(.caption)
          .foregroundStyle(.secondary)
          .accessibilityIdentifier("bazarr.wantedCount")
      }

      ForEach(store.filteredWanted) { item in
        WantedRow(item: item, isDownloading: store.isDownloading(item)) {
          searchTarget = item
        }
      }
    }
    .searchable(text: $store.searchText, prompt: "Search wanted")
    .overlay {
      if wanted.isEmpty {
        // Good news, and it should read like it.
        ContentUnavailableView(
          "Nothing Wanted", systemImage: "checkmark.circle",
          description: Text("Every episode and film has the subtitles it asked for.")
        )
        .accessibilityIdentifier("bazarr.wanted.empty")
      } else if store.filteredWanted.isEmpty {
        ContentUnavailableView.search
      }
    }
    .refreshable { await store.refresh() }
  }

  // MARK: - Libraries

  @ViewBuilder
  private func library(_ state: Loadable<[BazarrMediaItem]>, identifier: String) -> some View {
    LoadableList(state: state, emptyTitle: "Nothing Here", identifier: identifier) { items in
      ForEach(items) { item in
        BazarrLibraryRow(item: item, missingCount: store.displayedMissingCount(for: item))
      }
    }
    .refreshable { await store.refreshLibrary(series: identifier.hasSuffix("series")) }
  }

  // MARK: - Providers

  @ViewBuilder
  private var providersSection: some View {
    LoadableList(
      state: store.providers, emptyTitle: "No Providers", identifier: "bazarr.providers"
    ) { providers in
      // Leads with the count, because "two of my providers are down" is the
      // reason to open this section.
      if !store.failingProviders.isEmpty {
        Label(
          "\(store.failingProviders.count) provider"
            + "\(store.failingProviders.count == 1 ? "" : "s") failing",
          systemImage: "exclamationmark.triangle.fill")
          .font(.caption)
          .foregroundStyle(.orange)
          .accessibilityIdentifier("bazarr.failingProviders")
      }
      ForEach(providers) { provider in
        ProviderRow(provider: provider)
      }
    }
    .refreshable { await store.loadProviders(force: true) }
  }

  // MARK: - History

  @ViewBuilder
  private var historySection: some View {
    LoadableList(
      state: store.history, emptyTitle: "No History", identifier: "bazarr.history"
    ) { records in
      ForEach(records) { record in
        SubtitleHistoryRow(record: record)
      }
    }
    .refreshable { await store.loadHistory(force: true) }
  }
}

/// One thing missing subtitles.
struct WantedRow: View {
  let item: WantedSubtitle
  let isDownloading: Bool
  let search: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      VStack(alignment: .leading, spacing: 3) {
        Text(item.title)
          .font(.callout)
          .lineLimit(2)
        if let subtitle = item.subtitle, !subtitle.isEmpty {
          Text(subtitle)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
        // Each wanted language spelled out, flags included: "English" and
        // "English (HI)" are different files.
        Text(item.missing.map(\.displayName).joined(separator: ", "))
          .font(.caption2)
          .foregroundStyle(.orange)
          .lineLimit(2)
      }
      .accessibilityElement(children: .combine)
      .accessibilityIdentifier("bazarr.wanted.\(item.id)")

      // Outside the combined element, so the button keeps its identity.
      if isDownloading {
        ProgressView()
      } else {
        Button("Find Subtitles", systemImage: "magnifyingglass") { search() }
          .buttonStyle(.borderless)
          .font(.caption)
          .accessibilityIdentifier("bazarr.wanted.\(item.id).search")
      }
    }
    .padding(.vertical, 2)
  }
}

/// A library row. The count, the tint and the VoiceOver label all read the one
/// `missingCount`, so the row cannot show a count while VoiceOver says
/// "Complete".
struct BazarrLibraryRow: View {
  let item: BazarrMediaItem
  /// From `BazarrStore.displayedMissingCount(for:)`.
  let missingCount: Int

  var body: some View {
    HStack {
      VStack(alignment: .leading, spacing: 3) {
        Text(item.title)
          .font(.callout)
          .lineLimit(2)
        HStack(spacing: 6) {
          if let profile = item.languageProfileName {
            Text(profile)
          }
          if !item.monitored {
            if item.languageProfileName != nil { Text("·") }
            Text("Unmonitored")
          }
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
      }

      Spacer(minLength: 8)

      if missingCount > 0 {
        VStack(alignment: .trailing, spacing: 1) {
          Text("\(missingCount)")
            .font(.caption.weight(.medium))
            .foregroundStyle(.orange)
          Text(missingNoun)
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
      } else {
        Image(systemName: "checkmark.circle.fill")
          .foregroundStyle(.green)
          .accessibilityHidden(true)
      }
    }
    .accessibilityElement(children: .combine)
    .accessibilityLabel(accessibilityLabel)
    .accessibilityIdentifier("bazarr.item.\(item.id)")
  }

  private var missingNoun: String {
    let singular = item.isSeries ? "episode" : "language"
    return missingCount == 1 ? singular : singular + "s"
  }

  private var accessibilityLabel: String {
    var parts = [item.title]
    if let profile = item.languageProfileName { parts.append(profile) }
    if missingCount > 0 {
      parts.append("\(missingCount) \(missingNoun) missing")
    } else {
      parts.append("Complete")
    }
    if !item.monitored { parts.append("Unmonitored") }
    return parts.joined(separator: ", ")
  }
}

struct ProviderRow: View {
  let provider: SubtitleProvider

  var body: some View {
    VStack(alignment: .leading, spacing: 3) {
      HStack(spacing: 6) {
        Text(provider.name)
          .font(.callout)
        Spacer(minLength: 4)
        // Word plus tint, never tint alone.
        Text(provider.status.displayName)
          .font(.caption2.weight(.medium))
          .padding(.horizontal, 6)
          .padding(.vertical, 2)
          .background(
            (provider.status == .healthy ? Color.green : Color.orange).opacity(0.15),
            in: Capsule()
          )
          .foregroundStyle(provider.status == .healthy ? Color.green : Color.orange)
      }
      if provider.status == .failing, let message = provider.message {
        // Bazarr's own words: it explains a throttle or a bad login better
        // than any rewording here.
        Text(message)
          .font(.caption2)
          .foregroundStyle(.secondary)
      }
      if let retry = provider.retryAt, retry != "-" {
        Text("Retries \(retry)")
          .font(.caption2)
          .foregroundStyle(.secondary)
      }
    }
    .accessibilityElement(children: .combine)
    .accessibilityIdentifier("bazarr.provider.\(provider.name)")
  }
}

struct SubtitleHistoryRow: View {
  let record: SubtitleHistoryRecord

  var body: some View {
    VStack(alignment: .leading, spacing: 3) {
      Text(record.title)
        .font(.callout)
        .lineLimit(2)
      if let subtitle = record.subtitle, !subtitle.isEmpty {
        Text(subtitle)
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }
      HStack(spacing: 6) {
        Text(record.action.displayName)
        if let language = record.language {
          Text("·")
          Text(language.displayName)
        }
        if let provider = record.provider {
          Text("·")
          Text(provider)
        }
        if let score = record.score {
          Text("·")
          Text("\(score)%")
        }
        if let timestamp = record.timestamp {
          Text("·")
          Text(timestamp)
        }
      }
      .font(.caption2)
      .foregroundStyle(.secondary)
      .lineLimit(1)
    }
    .accessibilityElement(children: .combine)
    .accessibilityIdentifier("bazarr.history.\(record.id)")
  }
}
