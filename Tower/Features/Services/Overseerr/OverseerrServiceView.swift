import SwiftUI
import TowerCore
import TowerData

/// An Overseerr instance: the requests list, its filters, and approve/decline.
struct OverseerrServiceView: View {
  let instance: ServiceInstance
  @Bindable var store: OverseerrRequestsStore

  @State private var pendingDecline: OverseerrRequest?
  @State private var searchStore: OverseerrSearchStore?
  @State private var section: Section = .requests
  /// Built on first visit and kept, so switching away and back doesn't refetch
  /// — and so an unvisited Issues tab has never asked the service anything.
  /// Same rule as `ArrShellView`'s lazy sections.
  @State private var issuesStore: OverseerrIssuesStore?

  enum Section: String, CaseIterable, Identifiable {
    case requests, issues

    var id: String { rawValue }

    var title: String {
      switch self {
      case .requests: "Requests"
      case .issues: "Issues"
      }
    }

    var systemImage: String {
      switch self {
      case .requests: "tray.full"
      case .issues: "exclamationmark.bubble"
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
      .accessibilityIdentifier("overseerr.sections")

      sectionContent
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
      .navigationTitle(instance.name)
      .navigationBarTitleDisplayMode(.inline)
      .toolbar { toolbar }
      // Driven off counters the store bumps only for real actions, so a
      // background refresh never buzzes the user (the DockerStore pattern).
      .sensoryFeedback(.success, trigger: store.lastActionSuccess)
      .sensoryFeedback(.error, trigger: store.lastActionFailure)
      .task {
        await store.appeared()
      }
      .sheet(item: $searchStore) { search in
        OverseerrSearchView(store: search)
      }
      .confirmationDialog(
        pendingDecline.map { "Decline \($0.displayTitle)?" } ?? "Decline request?",
        isPresented: Binding(
          get: { pendingDecline != nil },
          set: { if !$0 { pendingDecline = nil } }),
        titleVisibility: .visible
      ) {
        // Declining is the destructive half and the only one that asks: an
        // approval can be undone by approving again, a decline tells someone
        // no and shows up in their notifications.
        Button("Decline", role: .destructive) {
          if let pendingDecline {
            let request = pendingDecline
            Task { await store.decline(request) }
          }
          pendingDecline = nil
        }
        .accessibilityIdentifier("overseerr.confirmDecline")
        Button("Cancel", role: .cancel) { pendingDecline = nil }
      } message: {
        Text("The person who asked for this will be told it was declined.")
      }
  }

  @ViewBuilder
  private var sectionContent: some View {
    switch section {
    case .requests:
      content
    case .issues:
      OverseerrIssuesView(store: issuesStoreIfNeeded())
    }
  }

  /// Built once, on first visit.
  private func issuesStoreIfNeeded() -> OverseerrIssuesStore {
    if let issuesStore { return issuesStore }
    let created = OverseerrIssuesStore(repository: store.repository)
    // Assigning during a body evaluation is safe here for the same reason it is
    // in `ArrShellView`: it happens on the render that first shows the section,
    // and the value is derived rather than a response to user input. What it
    // must not become is a store built fresh in `body` with no `@State` behind
    // it at all — that resets the `Loadable` on every render and spins forever.
    Task { @MainActor in issuesStore = created }
    return created
  }

  @ViewBuilder
  private var content: some View {
    switch store.state {
    case .idle, .loading:
      LoadingStateView(title: "Loading requests…", isLoadInFlight: store.isLoadInFlight) {
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
        .accessibilityIdentifier("overseerr.error")
        Button("Try Again") { Task { await store.load() } }
          .accessibilityIdentifier("overseerr.retry")
      }
    case .loaded(let requests), .actionFailed(let requests, _):
      list(requests)
    }
  }

  private func list(_ requests: [OverseerrRequest]) -> some View {
    List {
      if case .actionFailed(_, let error) = store.state {
        Text(error.message)
          .font(.caption)
          .foregroundStyle(.red)
          .accessibilityIdentifier("overseerr.actionError")
      }

      ForEach(requests) { request in
        NavigationLink(value: request.id) {
          OverseerrRequestRow(request: request, isInFlight: store.isInFlight(request))
        }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
          if request.status.isActionable {
            Button("Approve", systemImage: "checkmark") {
              Task { await store.approve(request) }
            }
            .tint(.green)
            .accessibilityIdentifier("overseerr.approve.\(request.id)")
          }
        }
        .swipeActions(edge: .trailing) {
          if request.status.isActionable {
            // Opens the confirmation; never declines on the swipe itself.
            Button("Decline", systemImage: "xmark", role: .destructive) {
              pendingDecline = request
            }
            .accessibilityIdentifier("overseerr.decline.\(request.id)")
          }
        }
        .onAppear {
          // Paging on the last row's appearance, rather than a "Load more"
          // button: a request queue is scrolled, not paged through.
          if request.id == requests.last?.id { Task { await store.loadMore() } }
        }
      }

      if store.isLoadingMore {
        HStack {
          Spacer()
          ProgressView()
          Spacer()
        }
        .accessibilityIdentifier("overseerr.loadingMore")
      }
    }
    .navigationDestination(for: Int.self) { requestID in
      // Identifier, not value.
      OverseerrRequestDetailView(store: store, requestID: requestID)
    }
    .overlay {
      if requests.isEmpty {
        emptyState
      }
    }
    .refreshable { await store.refresh() }
  }

  /// The empty state says which filter is empty — "nothing pending" is good
  /// news and reads differently from "this server has no requests".
  @ViewBuilder
  private var emptyState: some View {
    if store.filter == .pending {
      ContentUnavailableView(
        "Nothing Pending", systemImage: "checkmark.circle",
        description: Text("Every request has been dealt with.")
      )
      .accessibilityIdentifier("overseerr.empty")
    } else {
      ContentUnavailableView(
        "No Requests", systemImage: "tray",
        description: Text(
          store.filter == .all
            ? "This server has no requests yet."
            : "Nothing here is \(store.filter.displayName.lowercased()).")
      )
      .accessibilityIdentifier("overseerr.empty")
    }
  }

  @ToolbarContentBuilder
  private var toolbar: some ToolbarContent {
    ToolbarItem(placement: .topBarTrailing) {
      Button("Request Media", systemImage: "plus") {
        // The search store is handed the requests store so a new request shows
        // up in the list behind the sheet.
        searchStore = OverseerrSearchStore(
          repository: store.repository, requestsStore: store)
      }
      .accessibilityIdentifier("overseerr.search")
    }

    ToolbarItem(placement: .topBarTrailing) {
      Menu("Filter", systemImage: "line.3.horizontal.decrease.circle") {
        Picker("Show", selection: $store.filter) {
          ForEach(RequestFilter.allCases) { option in
            Text(option.displayName).tag(option)
          }
        }
      }
      .accessibilityIdentifier("overseerr.filter")
    }
  }
}

/// One request row: what, who, when, and where it has got to.
struct OverseerrRequestRow: View {
  let request: OverseerrRequest
  var isInFlight: Bool = false

  var body: some View {
    DashboardRow(showsChevron: false) {
      MediaPoster(
        url: request.posterURL,
        fallbackSystemImage: request.mediaType == .tv ? "tv" : "film")

      VStack(alignment: .leading, spacing: 3) {
        Text(request.displayTitle)
          .font(.body)
          .lineLimit(2)

        HStack(spacing: 6) {
          RequestStatusBadge(status: request.status)
          if let mediaStatus {
            Text(mediaStatus)
          }
          if request.is4K {
            Text("·")
            Text("4K")
          }
        }
        .font(.caption)
        .foregroundStyle(.secondary)

        let detailLine = detailLine
        if !detailLine.isEmpty {
          Text(detailLine)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
      }

      Spacer(minLength: 4)

      if isInFlight { ProgressView() }
    }
    .accessibilityElement(children: .combine)
    .accessibilityLabel(accessibilityLabel)
    .accessibilityIdentifier("overseerr.row.\(request.id)")
  }

  /// Who asked, when, and which seasons, with a separator only between parts
  /// that are present: a request from a deleted Overseerr user has no
  /// requester, and must not open on a stray "·".
  var detailLine: String {
    var parts: [String] = []
    if let requestedBy = request.requestedBy { parts.append(requestedBy) }
    if let created = request.createdAt {
      parts.append(created.formatted(.relative(presentation: .named)))
    }
    if !request.seasons.isEmpty { parts.append(seasonSummary) }
    return parts.joined(separator: " · ")
  }

  /// "Seasons 1–3" beats a list of eleven numbers on a row.
  private var seasonSummary: String {
    let seasons = request.seasons
    guard let first = seasons.first, let last = seasons.last else { return "" }
    if seasons.count == 1 { return "Season \(first)" }
    let isContiguous = seasons.count == (last - first + 1)
    return isContiguous
      ? "Seasons \(first)–\(last)"
      : "\(seasons.count) seasons"
  }

  /// The media's availability, or nil when it reads the same as the request's
  /// status: a pending request for pending media would say "Pending" twice.
  var mediaStatus: String? {
    let text = request.mediaStatus.displayName
    return text == request.status.displayName ? nil : text
  }

  var accessibilityLabel: String {
    var parts = [request.displayTitle, request.status.displayName]
    if let mediaStatus { parts.append(mediaStatus) }
    if request.is4K { parts.append("4K") }
    if let requestedBy = request.requestedBy { parts.append("Requested by \(requestedBy)") }
    if !request.seasons.isEmpty { parts.append(seasonSummary) }
    return parts.joined(separator: ", ")
  }
}

/// The status, as a word plus a tint — never a tint alone.
struct RequestStatusBadge: View {
  let status: RequestStatus

  var body: some View {
    Text(status.displayName)
      .font(.caption2.weight(.medium))
      .padding(.horizontal, 6)
      .padding(.vertical, 2)
      .background(tint.opacity(0.15), in: Capsule())
      .foregroundStyle(tint)
  }

  private var tint: Color {
    switch status {
    case .pending: .orange
    case .approved: .green
    case .declined: .red
    case .failed: .red
    case .unknown: .secondary
    }
  }
}

/// One request in full: who asked, when, where it has got to, and the two
/// decisions.
struct OverseerrRequestDetailView: View {
  @Bindable var store: OverseerrRequestsStore
  let requestID: Int

  @State private var isConfirmingDecline = false

  private var request: OverseerrRequest? {
    store.state.value?.first { $0.id == requestID }
  }

  var body: some View {
    Group {
      if let request {
        detail(request)
      } else {
        // Approved from this screen on the pending filter: the row is gone
        // from the list, which is the correct outcome, and this says so
        // rather than showing a stale copy.
        ContentUnavailableView(
          "Request Handled", systemImage: "checkmark.circle",
          description: Text("It's no longer in this list.")
        )
        .accessibilityIdentifier("overseerr.detail.gone")
      }
    }
    .navigationTitle(request?.displayTitle ?? "Request")
    .navigationBarTitleDisplayMode(.inline)
    // **No identifier on this Group.** One on a container overwrites its
    // children's, and it swallowed `overseerr.detail.gone` (CLAUDE.md, "An
    // accessibility identifier on a container overwrites every child's"). The
    // screen is addressed through its own controls instead.
  }

  private func detail(_ request: OverseerrRequest) -> some View {
    List {
      Section {
        LabeledContent("Status", value: request.status.displayName)
        LabeledContent("Media", value: request.mediaStatus.displayName)
        LabeledContent("Type", value: request.mediaType.displayName)
        if request.is4K { LabeledContent("Quality", value: "4K") }
      }

      Section("Requested") {
        if let requestedBy = request.requestedBy {
          LabeledContent("By", value: requestedBy)
        }
        if let created = request.createdAt {
          LabeledContent("When", value: created.formatted(date: .abbreviated, time: .shortened))
        }
        if let updated = request.updatedAt, updated != request.createdAt {
          LabeledContent("Updated", value: updated.formatted(date: .abbreviated, time: .shortened))
        }
      }

      if !request.seasons.isEmpty {
        Section("Seasons") {
          Text(request.seasons.map(String.init).joined(separator: ", "))
            .accessibilityIdentifier("overseerr.detail.seasons")
        }
      }

      if request.status.isActionable {
        Section {
          Button("Approve", systemImage: "checkmark.circle") {
            Task { await store.approve(request) }
          }
          .disabled(store.isInFlight(request))
          .accessibilityIdentifier("overseerr.detail.approve")

          Button("Decline", systemImage: "xmark.circle", role: .destructive) {
            isConfirmingDecline = true
          }
          .disabled(store.isInFlight(request))
          .accessibilityIdentifier("overseerr.detail.decline")
        }
      }
    }
    .confirmationDialog(
      "Decline \(request.displayTitle)?", isPresented: $isConfirmingDecline,
      titleVisibility: .visible
    ) {
      Button("Decline", role: .destructive) { Task { await store.decline(request) } }
        .accessibilityIdentifier("overseerr.detail.confirmDecline")
      Button("Cancel", role: .cancel) {}
    } message: {
      Text("The person who asked for this will be told it was declined.")
    }
  }
}
