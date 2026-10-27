import SwiftUI
import TowerCore
import TowerData

/// A Prowlarr instance: indexers, stats, and history.
///
/// The add-indexer form is a sheet from here.
struct ProwlarrServiceView: View {
  let instance: ServiceInstance
  @Bindable var store: ProwlarrIndexersStore

  @State private var section: Section = .indexers
  @State private var pendingDeletion: ProwlarrIndexer?
  @State private var addStore: AddIndexerStore?

  enum Section: String, CaseIterable, Identifiable {
    case indexers, stats, history

    var id: String { rawValue }

    var title: String {
      switch self {
      case .indexers: "Indexers"
      case .stats: "Stats"
      case .history: "History"
      }
    }

    var systemImage: String {
      switch self {
      case .indexers: "antenna.radiowaves.left.and.right"
      case .stats: "chart.bar"
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
      .accessibilityIdentifier("prowlarr.sections")

      sectionContent
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    .navigationTitle(instance.name)
    .navigationBarTitleDisplayMode(.inline)
    .sensoryFeedback(.success, trigger: store.lastActionSuccess)
    .sensoryFeedback(.error, trigger: store.lastActionFailure)
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        Button("Add Indexer", systemImage: "plus") {
          // Handed the list store so a saved indexer appears behind the sheet.
          addStore = AddIndexerStore(repository: store.repository, indexersStore: store)
        }
        .accessibilityIdentifier("prowlarr.add")
      }
    }
    .sheet(item: $addStore) { add in
      AddIndexerView(store: add)
    }
    .task {
      await store.appeared()
    }
    .task(id: section) {
      if section == .history { await store.loadHistory() }
    }
    .confirmationDialog(
      "Delete \(pendingDeletion?.name ?? "")?",
      isPresented: Binding(
        get: { pendingDeletion != nil },
        set: { if !$0 { pendingDeletion = nil } }),
      titleVisibility: .visible
    ) {
      Button("Delete", role: .destructive) {
        if let target = pendingDeletion { Task { await store.delete(target) } }
        pendingDeletion = nil
      }
      .accessibilityIdentifier("prowlarr.confirmDelete")
      Button("Cancel", role: .cancel) { pendingDeletion = nil }
    } message: {
      Text("Every app syncing from this Prowlarr will lose this indexer.")
    }
  }

  @ViewBuilder
  private var sectionContent: some View {
    switch section {
    case .indexers: indexersSection
    case .stats: statsSection
    case .history: historySection
    }
  }

  // MARK: - Indexers

  @ViewBuilder
  private var indexersSection: some View {
    switch store.state {
    case .idle, .loading:
      LoadingStateView(title: "Loading indexers…", isLoadInFlight: store.isLoadInFlight) {
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
        .accessibilityIdentifier("prowlarr.error")
        Button("Try Again") { Task { await store.load() } }
          .accessibilityIdentifier("prowlarr.retry")
      }
    case .loaded(let indexers), .actionFailed(let indexers, _):
      indexerList(indexers)
    }
  }

  private func indexerList(_ indexers: [ProwlarrIndexer]) -> some View {
    List {
      if case .actionFailed(_, let error) = store.state {
        Text(error.message)
          .font(.caption)
          .foregroundStyle(.red)
          .accessibilityIdentifier("prowlarr.actionError")
      }

      // Leads with the count, because "two of my indexers are down" is the
      // reason to open this screen.
      if store.failingCount > 0 {
        Label(
          "\(store.failingCount) indexer\(store.failingCount == 1 ? "" : "s") failing",
          systemImage: "exclamationmark.triangle.fill")
          .font(.caption)
          .foregroundStyle(.orange)
          .accessibilityIdentifier("prowlarr.failingCount")
      }

      ForEach(store.filteredIndexers) { indexer in
        IndexerRow(
          indexer: indexer,
          stats: store.stats(for: indexer),
          testResult: store.testResult(for: indexer),
          isInFlight: store.isInFlight(indexer),
          setEnabled: { isEnabled in
            Task { await store.setEnabled(isEnabled, for: indexer) }
          },
          dismissTestResult: { store.clearTestResult(for: indexer) })
          .swipeActions(edge: .leading) {
            Button("Test", systemImage: "stethoscope") {
              Task { await store.test(indexer) }
            }
            .tint(.blue)
            .accessibilityIdentifier("prowlarr.test.\(indexer.id)")
          }
          .swipeActions(edge: .trailing) {
            Button("Delete", systemImage: "trash", role: .destructive) {
              pendingDeletion = indexer
            }
            .accessibilityIdentifier("prowlarr.delete.\(indexer.id)")
          }
      }
    }
    .searchable(text: $store.searchText, prompt: "Search indexers")
    .overlay {
      if indexers.isEmpty {
        ContentUnavailableView(
          "No Indexers", systemImage: "antenna.radiowaves.left.and.right",
          description: Text("\(instance.name) has no indexers configured.")
        )
        .accessibilityIdentifier("prowlarr.empty")
      } else if store.filteredIndexers.isEmpty {
        ContentUnavailableView.search
      }
    }
    .refreshable { await store.refresh() }
  }

  // MARK: - Stats

  @ViewBuilder
  private var statsSection: some View {
    let rows = store.statsRows
    if rows.isEmpty {
      ContentUnavailableView(
        "No Stats Yet", systemImage: "chart.bar",
        description: Text("Prowlarr reports these once its indexers have been queried.")
      )
      .accessibilityIdentifier("prowlarr.stats.empty")
    } else {
      List(rows) { stats in
        IndexerStatsRow(stats: stats)
      }
      .refreshable { await store.refresh() }
    }
  }

  // MARK: - History

  @ViewBuilder
  private var historySection: some View {
    LoadableList(
      state: store.history, emptyTitle: "No History", identifier: "prowlarr.history"
    ) { records in
      ForEach(records) { record in
        ProwlarrHistoryRow(record: record)
      }
    }
    .refreshable { await store.loadHistory(force: true) }
  }
}

/// One indexer: what it is, whether it works, and the switch.
struct IndexerRow: View {
  let indexer: ProwlarrIndexer
  let stats: IndexerStats?
  let testResult: IndexerTestResult?
  let isInFlight: Bool
  let setEnabled: (Bool) -> Void
  let dismissTestResult: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack {
        VStack(alignment: .leading, spacing: 3) {
          Text(indexer.name)
            .font(.body)
            .lineLimit(1)

          HStack(spacing: 6) {
            // A failing indexer says so in words *and* in colour — never
            // colour alone.
            // The privacy label always follows, so a state word always
            // takes a separator.
            if indexer.isFailing {
              Label("Failing", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
              Text("·")
            } else if !indexer.isEnabled {
              Text("Disabled")
              Text("·")
            }
            if let label = indexer.downloadProtocol.displayName {
              Text(label)
              Text("·")
            }
            Text(indexer.privacy.displayName)
          }
          .font(.caption)
          .foregroundStyle(.secondary)

          if let stats, let rate = stats.successRate {
            HStack(spacing: 6) {
              Text(
                "\(Int((rate * 100).rounded()))% of \(Formatters.count(stats.queries, "query", plural: "queries"))"
              )
              Text("·")
              Text(Formatters.count(stats.grabs, "grab"))
              Text("·")
              Text("\(stats.averageResponseTimeMilliseconds) ms")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
          }

          if let until = indexer.disabledUntil, until > .now {
            Text("Prowlarr retries \(until.formatted(.relative(presentation: .named)))")
              .font(.caption2)
              .foregroundStyle(.orange)
          }
        }

        Spacer(minLength: 8)

        if isInFlight {
          ProgressView()
        } else {
          // The switch carries its own identifier: tapping a `Toggle` *row*
          // does nothing in this app — only the switch responds — so a
          // test has to address the switch, and it must not be swallowed by a
          // container identifier.
          Toggle(
            "Enabled",
            isOn: Binding(get: { indexer.isEnabled }, set: { setEnabled($0) })
          )
          .labelsHidden()
          .accessibilityIdentifier("prowlarr.toggle.\(indexer.id)")
        }
      }

      // The test outcome, in place — not an alert, and not a pushed screen.
      if let testResult {
        HStack(alignment: .top, spacing: 6) {
          Image(
            systemName: testResult.isSuccess
              ? "checkmark.circle.fill" : "xmark.octagon.fill")
          VStack(alignment: .leading, spacing: 2) {
            Text(testResult.isSuccess ? "Test passed" : "Test failed")
            // Prowlarr's own words: it explains a bad cookie or a dead URL
            // better than any rewording here could.
            ForEach(testResult.messages, id: \.self) { message in
              Text(message)
                .foregroundStyle(.secondary)
            }
          }
          Spacer(minLength: 4)
          Button("Dismiss", systemImage: "xmark") { dismissTestResult() }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
        }
        .font(.caption2)
        .foregroundStyle(testResult.isSuccess ? Color.green : Color.red)
        .accessibilityIdentifier("prowlarr.testResult.\(indexer.id)")
      }
    }
    .padding(.vertical, 2)
    // **No identifier on this stack** — one on a container overwrites every
    // child's, and both the toggle and the test result need their own.
  }
}

struct IndexerStatsRow: View {
  let stats: IndexerStats

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(stats.indexerName)
        .font(.body)
      HStack(spacing: 12) {
        figure("Queries", stats.queries.formatted())
        figure("Grabs", stats.grabs.formatted())
        figure("Failed", stats.failedQueries.formatted())
        figure("Avg", "\(stats.averageResponseTimeMilliseconds.formatted()) ms")
      }
      if let rate = stats.successRate {
        ProgressView(value: rate)
          .tint(rate > 0.9 ? .green : rate > 0.7 ? .orange : .red)
          .accessibilityHidden(true)
      }
    }
    .accessibilityElement(children: .combine)
    .accessibilityLabel(accessibilityLabel)
    .accessibilityIdentifier("prowlarr.stats.\(stats.indexerID)")
  }

  private func figure(_ label: String, _ value: String) -> some View {
    VStack(alignment: .leading, spacing: 1) {
      Text(value)
        .font(.caption.weight(.medium))
      Text(label)
        .font(.caption2)
        .foregroundStyle(.secondary)
    }
  }

  private var accessibilityLabel: String {
    var parts = [
      stats.indexerName, Formatters.count(stats.queries, "query", plural: "queries"),
      Formatters.count(stats.grabs, "grab"),
      "\(stats.failedQueries) failed",
      "\(stats.averageResponseTimeMilliseconds) millisecond average",
    ]
    if let rate = stats.successRate {
      parts.append("\(Int((rate * 100).rounded())) percent successful")
    }
    return parts.joined(separator: ", ")
  }
}

struct ProwlarrHistoryRow: View {
  let record: ProwlarrHistoryRecord

  var body: some View {
    VStack(alignment: .leading, spacing: 3) {
      Text(record.query ?? record.eventType)
        .font(.callout)
        .lineLimit(2)
      HStack(spacing: 6) {
        Text(record.isSuccessful ? "Succeeded" : "Failed")
          .foregroundStyle(record.isSuccessful ? Color.secondary : Color.red)
        if let source = record.source {
          Text("·")
          Text(source)
        }
        if let date = record.date {
          Text("·")
          Text(date.formatted(.relative(presentation: .named)))
        }
      }
      .font(.caption2)
      .foregroundStyle(.secondary)
    }
    .accessibilityElement(children: .combine)
    .accessibilityIdentifier("prowlarr.history.row.\(record.id)")
  }
}
