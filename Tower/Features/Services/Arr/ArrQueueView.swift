import SwiftUI
import TowerCore

/// The queue section: what is downloading, what is stuck, and why.
struct ArrQueueView: View {
  @Bindable var store: ArrQueueStore
  /// Whether this section is on screen — the poll follows it, so a queue nobody
  /// is looking at costs nothing.
  let isVisible: Bool
  /// Supplied by the shell; `nil` means no row links anywhere.
  var downloadClients: DownloadClientNavigator?

  @State private var pendingRemoval: ArrQueueItem?
  @State private var openedClient: DownloadClientLink?

  var body: some View {
    content
      .task {
        await store.appeared()
      }
      // The same cadence every polling screen in the app uses.
      .pollingRefresh(isActive: isVisible) { await store.refresh() }
      .confirmationDialog(
        pendingRemoval.map { "Remove \($0.displayTitle)?" } ?? "Remove from queue?",
        isPresented: Binding(
          get: { pendingRemoval != nil },
          set: { if !$0 { pendingRemoval = nil } }),
        titleVisibility: .visible
      ) {
        // Two different decisions, spelled out: blocklisting is what stops the
        // *arr grabbing the same broken release again in five minutes.
        Button("Remove", role: .destructive) {
          if let pendingRemoval { remove(pendingRemoval, blocklist: false) }
          pendingRemoval = nil
        }
        .accessibilityIdentifier("queue.confirmRemove")

        Button("Remove and Blocklist", role: .destructive) {
          if let pendingRemoval { remove(pendingRemoval, blocklist: true) }
          pendingRemoval = nil
        }
        .accessibilityIdentifier("queue.confirmBlocklist")

        Button("Cancel", role: .cancel) { pendingRemoval = nil }
      } message: {
        Text("Blocklisting also tells this service not to grab the same release again.")
      }
      .sheet(item: $openedClient) { link in
        if let makeRepository = downloadClients?.makeRepository {
          DownloadClientLinkSheet(link: link, makeRepository: makeRepository)
        }
      }
  }

  @ViewBuilder
  private var content: some View {
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
        .accessibilityIdentifier("queue.error")
        Button("Try Again") { Task { await store.load() } }
          .accessibilityIdentifier("queue.retry")
      }
    case .loaded, .actionFailed:
      list
    }
  }

  private var list: some View {
    List {
      if case .actionFailed(_, let error) = store.state {
        Text(error.message)
          .font(.caption)
          .foregroundStyle(.red)
          .accessibilityIdentifier("queue.actionError")
      }
      ForEach(store.items) { item in
        ArrQueueRow(item: item, clientLink: downloadClients?.link(for: item)) { link in
          openedClient = link
        }
          .swipeActions(edge: .trailing) {
            Button("Remove", systemImage: "trash", role: .destructive) {
              pendingRemoval = item
            }
            .accessibilityIdentifier("queue.row.\(item.id).remove")
          }
      }
    }
    .overlay {
      if store.isEmpty {
        ContentUnavailableView(
          "Queue Empty", systemImage: "checkmark.circle",
          description: Text("Nothing is downloading right now.")
        )
        .accessibilityIdentifier("queue.empty")
      }
    }
    .refreshable { await store.refresh() }
  }

  private func remove(_ item: ArrQueueItem, blocklist: Bool) {
    Task { await store.remove(item, removeFromClient: true, blocklist: blocklist) }
  }
}

/// One queue row: title, progress, and — when something is wrong — what.
struct ArrQueueRow: View {
  let item: ArrQueueItem
  /// The download client fetching this item, when Tower has it configured and
  /// could match it. `nil` renders a plain row — no affordance that
  /// goes nowhere.
  var clientLink: DownloadClientLink?
  var openClient: (DownloadClientLink) -> Void = { _ in }

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      details

      // **Outside the combined element, not inside it.** The details above are
      // merged into one VoiceOver stop with `children: .combine`, and a button
      // placed inside that loses its own identity and identifier — the same
      // trap as an identifier on a container overwriting its children's.
      // Rendered only when a client actually matched, so there is never an
      // affordance that goes nowhere.
      if let clientLink {
        Button {
          openClient(clientLink)
        } label: {
          Label("Open in \(clientLink.instance.name)", systemImage: "arrow.up.forward.app")
            .font(.caption2)
        }
        .buttonStyle(.borderless)
        .accessibilityIdentifier("queue.row.\(item.id).openClient")
      }
    }
  }

  private var details: some View {
    VStack(alignment: .leading, spacing: 5) {
      Text(item.displayTitle)
        .font(.callout)
        .lineLimit(2)

      if let progress = item.progress, !item.needsAttention {
        ProgressView(value: progress)
          .accessibilityHidden(true)
      }

      HStack(spacing: 6) {
        Text(statusText)
          .foregroundStyle(item.needsAttention ? .orange : .secondary)
        if let sizeText {
          Text("·")
          Text(sizeText)
        }
        if let timeLeft = item.timeLeft, !item.needsAttention {
          Text("·")
          Text(timeLeft)
        }
      }
      .font(.caption)

      let source = [item.downloadProtocol.displayName, item.downloadClient]
        .compactMap { $0 }
        .joined(separator: " · ")
      if !source.isEmpty {
        Text(source)
          .font(.caption2)
          .foregroundStyle(.secondary)
      }

      // Why it is stuck, in the service's own words. A row that says only
      // "warning" sends the user to the *arr's web UI to find out what this
      // screen already knows.
      ForEach(reasons, id: \.self) { reason in
        Label(reason, systemImage: "exclamationmark.triangle.fill")
          .font(.caption2)
          .foregroundStyle(.orange)
          .labelStyle(.titleAndIcon)
      }
    }
    .padding(.vertical, 2)
    .accessibilityElement(children: .combine)
    .accessibilityLabel(accessibilityLabel)
    .accessibilityIdentifier("queue.row.\(item.id)")
  }

  /// The tracked *state* leads when something is wrong — "Import blocked" is
  /// the fact a user acts on, not "downloading".
  private var statusText: String {
    if item.needsAttention { return item.trackedState.displayName }
    if item.progress == 1 { return "Waiting to import" }
    return item.status.displayName
  }

  private var sizeText: String? {
    guard let size = item.sizeBytes, size > 0 else { return nil }
    guard let left = item.sizeLeftBytes, left > 0 else { return Formatters.bytes(size) }
    return "\(Formatters.bytes(size - left)) of \(Formatters.bytes(size))"
  }

  private var reasons: [String] {
    var reasons = item.statusMessages
    if let error = item.errorMessage, !error.isEmpty { reasons.append(error) }
    return reasons
  }

  private var accessibilityLabel: String {
    var parts = [item.displayTitle, statusText]
    if let progress = item.progress {
      parts.append("\(Int((progress * 100).rounded())) percent")
    }
    if let timeLeft = item.timeLeft, !item.needsAttention { parts.append(timeLeft) }
    if let label = item.downloadProtocol.displayName { parts.append(label) }
    parts.append(contentsOf: reasons)
    return parts.joined(separator: ", ")
  }
}
