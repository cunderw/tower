import SwiftUI
import TowerCore

/// The issues list and one issue's thread.
struct OverseerrIssuesView: View {
  @Bindable var store: OverseerrIssuesStore

  var body: some View {
    content
      .sensoryFeedback(.success, trigger: store.lastActionSuccess)
      .sensoryFeedback(.error, trigger: store.lastActionFailure)
      .task {
        await store.appeared()
      }
  }

  @ViewBuilder
  private var content: some View {
    switch store.state {
    case .idle, .loading:
      LoadingStateView(title: "Loading issues…", isLoadInFlight: store.isLoadInFlight) {
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
        .accessibilityIdentifier("overseerr.issues.error")
        Button("Try Again") { Task { await store.load() } }
          .accessibilityIdentifier("overseerr.issues.retry")
      }
    case .loaded(let issues), .actionFailed(let issues, _):
      list(issues)
    }
  }

  private func list(_ issues: [OverseerrIssue]) -> some View {
    List {
      if case .actionFailed(_, let error) = store.state {
        Text(error.message)
          .font(.caption)
          .foregroundStyle(.red)
          .accessibilityIdentifier("overseerr.issues.actionError")
      }

      ForEach(issues) { issue in
        NavigationLink(value: IssueRoute(id: issue.id)) {
          IssueRow(issue: issue)
        }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
          // Reversible both ways: an issue closed by mistake is normal, and
          // the API supports reopening.
          if issue.status == .resolved {
            Button("Reopen", systemImage: "arrow.uturn.backward") {
              Task { await store.setResolved(false, for: issue) }
            }
            .tint(.orange)
            .accessibilityIdentifier("overseerr.issue.reopen.\(issue.id)")
          } else {
            Button("Resolve", systemImage: "checkmark") {
              Task { await store.setResolved(true, for: issue) }
            }
            .tint(.green)
            .accessibilityIdentifier("overseerr.issue.resolve.\(issue.id)")
          }
        }
      }
    }
    .navigationDestination(for: IssueRoute.self) { route in
      // Identifier, not value.
      OverseerrIssueDetailView(store: store, issueID: route.id)
    }
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        // A button, not a Toggle: a Toggle row in this app only responds at
        // its switch, and this lives in a toolbar anyway.
        Button {
          store.includeResolved.toggle()
        } label: {
          Label(
            "Show Resolved Issues",
            systemImage: store.includeResolved ? "line.3.horizontal.decrease.circle.fill"
              : "line.3.horizontal.decrease.circle")
        }
        .accessibilityIdentifier("overseerr.issues.filter")
        .accessibilityValue(store.includeResolved ? "All issues" : "Open issues only")
      }
    }
    .overlay {
      if issues.isEmpty { emptyState }
    }
    .refreshable { await store.refresh() }
  }

  /// "Nothing is broken" is good news and should read like it — distinct from
  /// a filter that matched nothing.
  @ViewBuilder
  private var emptyState: some View {
    if store.includeResolved {
      ContentUnavailableView(
        "No Issues", systemImage: "checkmark.seal",
        description: Text("Nobody has reported a problem.")
      )
      .accessibilityIdentifier("overseerr.issues.empty")
    } else {
      ContentUnavailableView(
        "Nothing Broken", systemImage: "checkmark.seal",
        description: Text("No open issues. Resolved ones are hidden.")
      )
      .accessibilityIdentifier("overseerr.issues.empty")
    }
  }
}

/// A distinct route type, so this destination can't collide with the requests
/// list's `Int` destination in the same navigation stack.
struct IssueRoute: Hashable {
  let id: Int
}

struct IssueRow: View {
  let issue: OverseerrIssue

  var body: some View {
    VStack(alignment: .leading, spacing: 3) {
      Text(issue.displayTitle)
        .font(.body)
        .lineLimit(2)
      HStack(spacing: 6) {
        IssueStatusBadge(status: issue.status)
        Text(issue.type.displayName)
        if let createdBy = issue.createdBy {
          Text("·")
          Text(createdBy)
        }
        if let created = issue.createdAt {
          Text("·")
          Text(created.formatted(.relative(presentation: .named)))
        }
      }
      .font(.caption)
      .foregroundStyle(.secondary)
      .lineLimit(1)

      // The first comment is the report itself, and it is the thing worth
      // reading on the row — "Audio" alone says nothing actionable.
      if let first = issue.comments.first {
        Text(first.message)
          .font(.caption2)
          .foregroundStyle(.secondary)
          .lineLimit(2)
      }
    }
    .accessibilityElement(children: .combine)
    .accessibilityIdentifier("overseerr.issue.row.\(issue.id)")
  }
}

struct IssueStatusBadge: View {
  let status: IssueStatus

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
    case .open: .orange
    case .resolved: .green
    case .unknown: .secondary
    }
  }
}

/// One issue: the thread, a box to add to it, and resolve/reopen.
struct OverseerrIssueDetailView: View {
  @Bindable var store: OverseerrIssuesStore
  let issueID: Int

  @State private var draft = ""
  @FocusState private var isComposing: Bool

  private var issue: OverseerrIssue? { store.issue(id: issueID) }

  var body: some View {
    Group {
      if let issue {
        detail(issue)
      } else {
        // Resolved from here while resolved issues are hidden: the row has
        // left the list, which is correct, and this says so.
        ContentUnavailableView(
          "Issue Closed", systemImage: "checkmark.seal",
          description: Text("It's no longer in this list.")
        )
        .accessibilityIdentifier("overseerr.issue.gone")
      }
    }
    .navigationTitle(issue?.displayTitle ?? "Issue")
    .navigationBarTitleDisplayMode(.inline)
    .accessibilityIdentifier("overseerr.issue.detail")
  }

  private func detail(_ issue: OverseerrIssue) -> some View {
    List {
      Section {
        LabeledContent("Status", value: issue.status.displayName)
        LabeledContent("Type", value: issue.type.displayName)
        if let createdBy = issue.createdBy {
          LabeledContent("Reported by", value: createdBy)
        }
        if let created = issue.createdAt {
          LabeledContent("When", value: created.formatted(date: .abbreviated, time: .shortened))
        }
      }

      Section("Comments") {
        if issue.comments.isEmpty {
          Text("No comments yet.")
            .foregroundStyle(.secondary)
            .accessibilityIdentifier("overseerr.issue.noComments")
        }
        ForEach(issue.comments) { comment in
          VStack(alignment: .leading, spacing: 3) {
            Text(comment.message)
              .font(.callout)
            HStack(spacing: 6) {
              if let author = comment.author { Text(author) }
              if let created = comment.createdAt {
                Text("·")
                Text(created.formatted(.relative(presentation: .named)))
              }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
          }
          .accessibilityElement(children: .combine)
          .accessibilityIdentifier("overseerr.issue.comment.\(comment.id)")
        }
      }

      Section {
        TextField("Add a comment", text: $draft, axis: .vertical)
          .lineLimit(1...4)
          .focused($isComposing)
          .accessibilityIdentifier("overseerr.issue.commentField")

        Button("Post Comment", systemImage: "paperplane") {
          Task {
            if await store.comment(on: issue, message: draft) {
              // Cleared only on success, so a failed post doesn't lose what
              // was typed.
              draft = ""
              isComposing = false
            }
          }
        }
        .disabled(
          draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || store.isInFlight(issue))
        .accessibilityIdentifier("overseerr.issue.postComment")
      }

      Section {
        if issue.status == .resolved {
          Button("Reopen Issue", systemImage: "arrow.uturn.backward") {
            Task { await store.setResolved(false, for: issue) }
          }
          .disabled(store.isInFlight(issue))
          .accessibilityIdentifier("overseerr.issue.detail.reopen")
        } else {
          Button("Resolve Issue", systemImage: "checkmark.seal") {
            Task { await store.setResolved(true, for: issue) }
          }
          .disabled(store.isInFlight(issue))
          .accessibilityIdentifier("overseerr.issue.detail.resolve")
        }
      }
    }
  }
}
