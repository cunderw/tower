import SwiftUI
import TowerCore
import TowerData

/// An NZBGet instance: queue, history, and server status.
///
/// Three sections behind a segmented picker, the same shape as `ArrShellView`
/// — and for the same reason: three stacked lists on a
/// phone is a scroll, not a screen.
struct NZBGetServiceView: View {
  let instance: ServiceInstance
  @Bindable var store: NZBGetStore

  @State private var section: Section = .queue
  @State private var isShowingSpeedLimit = false
  @State private var deletionTarget: NZBGroup?

  enum Section: String, CaseIterable, Identifiable {
    case queue, history, status

    var id: String { rawValue }

    var title: String {
      switch self {
      case .queue: "Queue"
      case .history: "History"
      case .status: "Status"
      }
    }

    var systemImage: String {
      switch self {
      case .queue: "arrow.down.circle"
      case .history: "clock.arrow.circlepath"
      case .status: "info.circle"
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
      // On the control, not the enclosing stack — a container's identifier
      // overwrites every child's (CLAUDE.md, "An accessibility identifier on
      // a container overwrites every child's").
      .accessibilityIdentifier("nzbget.sections")

      content
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    .navigationTitle(instance.name)
    .navigationBarTitleDisplayMode(.inline)
    .toolbar { toolbar }
    .task {
      await store.appeared()
    }
    .task(id: section) {
      if section == .history { await store.loadHistory() }
    }
    // `refresh()` re-reads the queue and the status, which is exactly what the
    // first two sections show. History is excluded on purpose: finished
    // downloads do not change, so polling it is pure waste.
    .pollingRefresh(every: .towerFastPoll, isActive: section != .history) {
      await store.refresh()
    }
    .sheet(isPresented: $isShowingSpeedLimit) {
      NZBSpeedLimitSheet(store: store)
    }
    .confirmationDialog(
      "Delete \(deletionTarget?.name ?? "")?",
      isPresented: Binding(get: { deletionTarget != nil }, set: { if !$0 { deletionTarget = nil } }),
      titleVisibility: .visible
    ) {
      Button("Delete", role: .destructive) {
        if let target = deletionTarget {
          Task { await store.delete(target) }
        }
        deletionTarget = nil
      }
      .accessibilityIdentifier("nzbget.confirmDelete")
      Button("Cancel", role: .cancel) { deletionTarget = nil }
    } message: {
      Text("This removes it from the queue and deletes what has been downloaded so far.")
    }
  }

  @ViewBuilder
  private var content: some View {
    switch section {
    case .queue: queueSection
    case .history: historySection
    case .status: statusSection
    }
  }

  // MARK: - Queue

  @ViewBuilder
  private var queueSection: some View {
    switch store.state {
    case .idle, .loading:
      LoadingStateView(title: "Loading queue…", isLoadInFlight: store.isLoadInFlight) {
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
        .accessibilityIdentifier("nzbget.error")
        Button("Try Again") { Task { await store.load() } }
          .accessibilityIdentifier("nzbget.retry")
      }
    case .loaded(let groups), .actionFailed(let groups, _):
      queueList(groups)
    }
  }

  private func queueList(_ groups: [NZBGroup]) -> some View {
    List {
      if case .actionFailed(_, let error) = store.state {
        Text(error.message)
          .font(.caption)
          .foregroundStyle(.red)
          .accessibilityIdentifier("nzbget.actionError")
      }

      if let status = store.status {
        SwiftUI.Section { NZBStatusSummaryRow(status: status) }
      }

      SwiftUI.Section {
        ForEach(store.filteredQueue) { group in
          NZBGroupRow(group: group) { priority in
            Task { await store.setPriority(priority, for: group) }
          }
          .swipeActions(edge: .leading, allowsFullSwipe: true) {
            if group.status.isPaused {
              Button("Resume", systemImage: "play.fill") {
                Task { await store.setPaused(false, for: group) }
              }
              .tint(.green)
              .accessibilityIdentifier("nzbget.resume.\(group.id)")
            } else {
              Button("Pause", systemImage: "pause.fill") {
                Task { await store.setPaused(true, for: group) }
              }
              .tint(.orange)
              .accessibilityIdentifier("nzbget.pause.\(group.id)")
            }
          }
          .swipeActions(edge: .trailing) {
            // Opens the confirmation; never deletes on the swipe itself.
            Button("Delete", systemImage: "trash", role: .destructive) {
              deletionTarget = group
            }
            .accessibilityIdentifier("nzbget.delete.\(group.id)")
          }
        }
      }
    }
    .searchable(text: $store.searchText, prompt: "Search queue")
    .overlay {
      if groups.isEmpty {
        ContentUnavailableView(
          "Queue Empty", systemImage: "tray",
          description: Text("\(instance.name) has nothing left to download.")
        )
        .accessibilityIdentifier("nzbget.queue.empty")
      } else if store.filteredQueue.isEmpty {
        ContentUnavailableView.search
      }
    }
    .refreshable { await store.refresh() }
  }

  // MARK: - History

  @ViewBuilder
  private var historySection: some View {
    LoadableList(
      state: store.history, emptyTitle: "No History", identifier: "nzbget.history"
    ) { items in
      ForEach(items) { item in
        NZBHistoryRow(item: item)
          .swipeActions(edge: .leading) {
            // Retry is offered for everything, not just failures: re-downloading
            // a succeeded item is a legitimate thing to want, and NZBGet allows
            // it.
            Button("Retry", systemImage: "arrow.clockwise") {
              Task { await store.retry(item) }
            }
            .tint(.blue)
            .accessibilityIdentifier("nzbget.history.retry.\(item.id)")
          }
          .swipeActions(edge: .trailing) {
            // Deleting a *history entry* removes a record, not data — so unlike
            // the queue delete it needs no confirmation.
            Button("Delete", systemImage: "trash", role: .destructive) {
              Task { await store.deleteHistory(item) }
            }
            .accessibilityIdentifier("nzbget.history.delete.\(item.id)")
          }
      }
    }
    .refreshable { await store.loadHistory(force: true) }
  }

  // MARK: - Status

  @ViewBuilder
  private var statusSection: some View {
    if let status = store.status {
      List {
        SwiftUI.Section("Transfer") {
          LabeledContent(
            "Rate", value: Formatters.speed(bytesPerSecond: status.downloadRateBytesPerSecond))
          LabeledContent("Remaining", value: Formatters.bytes(status.remainingBytes))
          LabeledContent("Downloaded", value: Formatters.bytes(status.downloadedBytes))
          LabeledContent(
            "Speed limit",
            value: status.speedLimitBytesPerSecond
              .map { Formatters.speed(bytesPerSecond: $0) } ?? "Unlimited")
          Button("Set Speed Limit", systemImage: "speedometer") { isShowingSpeedLimit = true }
            .accessibilityIdentifier("nzbget.setSpeedLimit")
        }
        SwiftUI.Section("Server") {
          LabeledContent("Downloading", value: status.isDownloadPaused ? "Paused" : "Active")
          LabeledContent("Free space", value: Formatters.bytes(status.freeDiskSpaceBytes))
          LabeledContent("Post-processing jobs", value: String(status.postJobCount))
          if let uptime = status.uptime {
            LabeledContent("Uptime", value: Formatters.duration(seconds: Int(uptime)))
          }
          if let version = status.version {
            LabeledContent("Version", value: version)
          }
        }
      }
      .accessibilityIdentifier("nzbget.status")
      .refreshable { await store.refresh() }
    } else {
      ContentUnavailableView(
        "No Status", systemImage: "questionmark.circle",
        description: Text("\(instance.name) didn't report its status.")
      )
      .accessibilityIdentifier("nzbget.status.empty")
    }
  }

  // MARK: - Toolbar

  @ToolbarContentBuilder
  private var toolbar: some ToolbarContent {
    ToolbarItem(placement: .topBarTrailing) {
      // NZBGet's own global switch, not a loop over the queue. The on-state is
      // carried by the glyph and the label, not by tint alone.
      Button {
        Task { await store.setDownloadPaused(!store.isDownloadPaused) }
      } label: {
        Label(
          store.isDownloadPaused ? "Resume Downloading" : "Pause Downloading",
          systemImage: store.isDownloadPaused ? "play.fill" : "pause.fill")
      }
      .accessibilityIdentifier("nzbget.globalPause")
      .accessibilityValue(store.isDownloadPaused ? "Paused" : "Active")
    }
    ToolbarItem(placement: .topBarTrailing) {
      Button("Speed Limit", systemImage: "speedometer") { isShowingSpeedLimit = true }
        .accessibilityIdentifier("nzbget.speedLimit")
    }
  }
}

/// The status header above the queue.
struct NZBStatusSummaryRow: View {
  let status: NZBServerStatus

  var body: some View {
    HStack(spacing: 16) {
      VStack(alignment: .leading, spacing: 2) {
        Label(
          Formatters.speed(bytesPerSecond: status.downloadRateBytesPerSecond),
          systemImage: "arrow.down"
        )
        .font(.subheadline.weight(.medium))
        Text("\(Formatters.bytes(status.remainingBytes)) remaining")
          .font(.caption2)
          .foregroundStyle(.secondary)
      }
      Spacer(minLength: 0)
      if status.isDownloadPaused {
        Label("Paused", systemImage: "pause.fill")
          .font(.caption2)
          .foregroundStyle(.orange)
      }
      if let limit = status.speedLimitBytesPerSecond {
        Label(Formatters.speed(bytesPerSecond: limit), systemImage: "speedometer")
          .font(.caption2)
          .foregroundStyle(.secondary)
      }
    }
    .accessibilityElement(children: .combine)
    .accessibilityIdentifier("nzbget.summary")
  }
}

/// One queue group, with its priority menu.
struct NZBGroupRow: View {
  let group: NZBGroup
  let setPriority: (NZBPriority) -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(group.name)
        .font(.body)
        .lineLimit(2)

      ProgressView(value: group.progress.clampedToUnitInterval)
        .progressViewStyle(.linear)
        .accessibilityHidden(true)

      HStack(spacing: 6) {
        Text(group.status.displayName)
        Text("·")
        Text("\(Int((group.progress.clampedToUnitInterval * 100).rounded()))%")
        Text("·")
        Text(Formatters.bytes(group.sizeBytes))
        if let eta = group.estimatedSecondsRemaining {
          Text("·")
          Text(Formatters.eta(eta))
        }
      }
      .font(.caption)
      .foregroundStyle(.secondary)

      HStack(spacing: 10) {
        if let category = group.category {
          Label(category, systemImage: "folder")
        }
        // Health below 100% is the early warning that a repair is coming.
        if let health = group.health, health < 1 {
          Label("\(Int((health * 100).rounded()))% health", systemImage: "heart.slash")
            .foregroundStyle(.orange)
        }
        Spacer(minLength: 0)
        Menu {
          Picker(
            "Priority",
            selection: Binding(get: { group.priority }, set: { setPriority($0) })
          ) {
            ForEach(NZBPriority.selectable, id: \.self) { priority in
              Text(priority.displayName).tag(priority)
            }
          }
        } label: {
          Text(group.priority.displayName)
        }
        .accessibilityIdentifier("nzbget.priority.\(group.id)")
      }
      .font(.caption2)
      .foregroundStyle(.secondary)
    }
    .padding(.vertical, 2)
    .accessibilityIdentifier("nzbget.row.\(group.id)")
  }
}

/// One finished item.
struct NZBHistoryRow: View {
  let item: NZBHistoryItem

  var body: some View {
    VStack(alignment: .leading, spacing: 3) {
      Text(item.name)
        .font(.callout)
        .lineLimit(2)
      HStack(spacing: 6) {
        // NZBGet's own compound status verbatim: "which part failed" is the
        // useful bit, and any rewording loses it.
        Text(item.status)
          .foregroundStyle(item.isSuccess ? Color.secondary : Color.red)
        Text("·")
        Text(Formatters.bytes(item.sizeBytes))
        if let completed = item.completedAt {
          Text("·")
          Text(completed.formatted(date: .abbreviated, time: .shortened))
        }
      }
      .font(.caption2)
      .foregroundStyle(.secondary)
    }
    .accessibilityElement(children: .combine)
    .accessibilityIdentifier("nzbget.history.row.\(item.id)")
  }
}

/// The global rate cap.
struct NZBSpeedLimitSheet: View {
  let store: NZBGetStore

  @Environment(\.dismiss) private var dismiss
  @State private var limit: String = ""

  var body: some View {
    NavigationStack {
      Form {
        Section {
          LabeledContent("Limit") {
            TextField("Unlimited", text: $limit)
              .keyboardType(.numberPad)
              .multilineTextAlignment(.trailing)
              .accessibilityIdentifier("nzbget.speedLimit.field")
          }
        } footer: {
          // KB/s, which is the unit NZBGet's own UI uses and the number a user
          // already has in their head.
          Text("In KB/s. Leave empty for no limit.")
        }
      }
      .navigationTitle("Speed Limit")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Save") {
            Task {
              await store.setSpeedLimit(bytesPerSecond: Self.bytesPerSecond(limit))
              dismiss()
            }
          }
          .accessibilityIdentifier("nzbget.speedLimit.save")
        }
      }
      .onAppear {
        limit = store.status?.speedLimitBytesPerSecond.map { String($0 / 1_024) } ?? ""
      }
    }
  }

  /// Empty, zero, or unparseable all mean "no limit" — which is what NZBGet's
  /// `rate` call spells as 0.
  static func bytesPerSecond(_ field: String) -> Int64? {
    let trimmed = field.trimmingCharacters(in: .whitespaces)
    guard let kilobytes = Int64(trimmed), kilobytes > 0 else { return nil }
    return kilobytes * 1_024
  }
}
