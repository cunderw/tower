import SwiftUI
import TowerCore
import TowerData

/// A Tautulli instance: activity, history, users, and libraries.
///
/// Four sections behind a segmented picker — the same shape as the Bazarr and
/// NZBGet screens. Only activity polls; the rest load on first visit and keep
/// what they got.
struct TautulliServiceView: View {
  let instance: ServiceInstance
  @Bindable var store: TautulliActivityStore

  @State private var section: Section = .activity
  /// The stream a confirmation is open for.
  @State private var pendingTerminate: TautulliSession?
  @State private var terminateMessage = ""

  enum Section: String, CaseIterable, Identifiable {
    case activity, history, users, libraries

    var id: String { rawValue }

    var title: String {
      switch self {
      case .activity: "Activity"
      case .history: "History"
      case .users: "Users"
      case .libraries: "Libraries"
      }
    }

    var systemImage: String {
      switch self {
      case .activity: "play.tv"
      case .history: "clock.arrow.circlepath"
      case .users: "person.2"
      case .libraries: "books.vertical"
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
      .accessibilityIdentifier("tautulli.sections")

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
      // The same cadence every polling screen in the app uses. Activity is the
      // one screen here where a stale answer is actively misleading — somebody
      // reads it to decide whether to start another stream.
      .pollingRefresh(isActive: section == .activity) { await store.refresh() }
      .task(id: section) {
        switch section {
        case .activity: break
        case .history: await store.loadHistory()
        case .users: await store.loadUsers()
        case .libraries: await store.loadLibraries()
        }
      }
      // Refetches when a filter changes rather than filtering on screen:
      // Tautulli narrows in SQL, so a local filter would search one page.
      .task(id: store.historyReloadToken) {
        guard section == .history, store.historyReloadToken > 0 else { return }
        await store.reloadHistory()
      }
      .confirmationDialog(
        pendingTerminate.map { "Stop \($0.user)'s stream?" } ?? "Stop this stream?",
        isPresented: Binding(
          get: { pendingTerminate != nil },
          set: { if !$0 { pendingTerminate = nil } }),
        titleVisibility: .visible
      ) {
        if let session = pendingTerminate {
          Button("Stop Stream", role: .destructive) {
            let message = terminateMessage.trimmingCharacters(in: .whitespacesAndNewlines)
            Task { await store.terminate(session, message: message.isEmpty ? nil : message) }
            pendingTerminate = nil
            terminateMessage = ""
          }
          .accessibilityIdentifier("tautulli.confirmTerminate")
        }
        Button("Cancel", role: .cancel) { pendingTerminate = nil }
      } message: {
        if let session = pendingTerminate {
          // Naming the title as well as the person: two people can be watching,
          // and stopping the wrong one is not undoable.
          Text("\(session.title) will stop playing on \(session.player).")
        }
      }
  }

  @ViewBuilder
  private var sectionContent: some View {
    switch section {
    case .activity: content
    case .history: TautulliHistorySection(store: store)
    case .users: TautulliUsersSection(store: store)
    case .libraries: TautulliLibrariesSection(store: store)
    }
  }

  @ViewBuilder
  private var content: some View {
    switch store.state {
    case .idle, .loading:
      LoadingStateView(title: "Loading activity…", isLoadInFlight: store.isLoadInFlight) {
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
        .accessibilityIdentifier("tautulli.error")
        Button("Try Again") { Task { await store.load() } }
          .accessibilityIdentifier("tautulli.retry")
      }
    case .loaded(let activity), .actionFailed(let activity, _):
      activityList(activity)
    }
  }

  private func activityList(_ activity: TautulliActivity) -> some View {
    List {
      if let error = store.actionError {
        Text(error.message)
          .font(.caption)
          .foregroundStyle(.red)
          .accessibilityIdentifier("tautulli.actionError")
      }

      if !activity.sessions.isEmpty {
        ActivitySummaryRow(activity: activity)
      }

      ForEach(store.sessions) { session in
        StreamCard(
          session: session,
          isTerminating: store.isTerminating(session),
          canTerminate: store.canTerminate(session)
        ) {
          terminateMessage = ""
          pendingTerminate = session
        }
      }
    }
    .overlay {
      if activity.sessions.isEmpty {
        // Good news, and it should read like it — an idle Plex is not an error
        // state.
        ContentUnavailableView(
          "Nothing Playing", systemImage: "moon.zzz",
          description: Text("Tautulli isn't seeing any streams right now.")
        )
        .accessibilityIdentifier("tautulli.activity.empty")
      }
    }
    .refreshable { await store.refresh() }
  }
}

/// The counts and bandwidth across every stream.
struct ActivitySummaryRow: View {
  let activity: TautulliActivity

  var body: some View {
    HStack {
      VStack(alignment: .leading, spacing: 3) {
        Text(
          "\(activity.streamCount) stream\(activity.streamCount == 1 ? "" : "s")"
        )
        .font(.callout.weight(.medium))
        // The split is the point: three direct plays cost the server nothing,
        // three transcodes are a different machine entirely.
        Text(breakdown)
          .font(.caption2)
          .foregroundStyle(.secondary)
      }
      Spacer(minLength: 8)
      VStack(alignment: .trailing, spacing: 3) {
        Text(Formatters.bitrate(kilobitsPerSecond: activity.totalBandwidthKbps))
          .font(.caption.monospacedDigit())
        if activity.wanBandwidthKbps > 0 {
          Text("\(Formatters.bitrate(kilobitsPerSecond: activity.wanBandwidthKbps)) remote")
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
      }
    }
    .accessibilityElement(children: .combine)
    .accessibilityIdentifier("tautulli.summary")
  }

  private var breakdown: String {
    var parts: [String] = []
    if activity.directPlayCount > 0 { parts.append("\(activity.directPlayCount) direct play") }
    if activity.directStreamCount > 0 {
      parts.append("\(activity.directStreamCount) direct stream")
    }
    if activity.transcodeCount > 0 { parts.append("\(activity.transcodeCount) transcoding") }
    return parts.isEmpty ? "Idle" : parts.joined(separator: " · ")
  }
}

/// One stream.
struct StreamCard: View {
  let session: TautulliSession
  let isTerminating: Bool
  let canTerminate: Bool
  let terminate: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      VStack(alignment: .leading, spacing: 4) {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
          Text(session.title)
            .font(.callout)
            .lineLimit(2)
          Spacer(minLength: 4)
          DecisionBadge(session: session)
        }

        if let subtitle = session.subtitle {
          Text(subtitle)
            .font(.caption)
            .foregroundStyle(.secondary)
        }

        HStack(spacing: 6) {
          Text(session.user)
          Text("·")
          Text(session.player)
          if session.location != .unknown {
            Text("·")
            Text(session.location.displayName)
          }
          if session.state != .playing {
            Text("·")
            Text(session.state.displayName)
          }
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .lineLimit(1)

        ProgressView(value: Double(min(max(session.progressPercent, 0), 100)), total: 100)
          .tint(session.isTranscoding ? .orange : .accentColor)

        HStack(spacing: 6) {
          Text("\(session.progressPercent)%")
          Text("·")
          Text(Formatters.bitrate(kilobitsPerSecond: session.bandwidthKbps))
          if let quality = Self.qualityBesideBitrate(session.qualityProfile) {
            Text("·")
            Text(quality)
          }
          // Only while something is actually being transcoded: a percentage
          // next to a direct play would read as a stalled conversion.
          if let transcode = session.transcodeProgressPercent {
            Text("·")
            Text("transcoded \(transcode)%")
          }
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .lineLimit(1)
      }
      // The identifier goes on the text stack, not the card: one on the
      // enclosing container overwrites the button's below it.
      .accessibilityElement(children: .combine)
      .accessibilityIdentifier("tautulli.stream.\(session.id)")

      if isTerminating {
        ProgressView()
      } else if canTerminate {
        Button("Stop Stream", systemImage: "stop.circle", role: .destructive) { terminate() }
          .buttonStyle(.borderless)
          .font(.caption)
          .accessibilityIdentifier("tautulli.stream.\(session.id).terminate")
      }
    }
    .padding(.vertical, 2)
  }

  /// The quality profile without the bitrate it starts with. Tautulli names a
  /// transcode's profile after its target rate ("4 Mbps 720p"), and the row
  /// already shows the measured rate beside it, so the two would read as one
  /// stream at two bitrates. A profile that is only a rate ("320 kbps") leaves
  /// nothing to add; one with no rate ("Original") passes through.
  static func qualityBesideBitrate(_ profile: String?) -> String? {
    guard let profile else { return nil }
    let remainder = profile
      .replacing(#/^\s*\d+(?:\.\d+)?\s*[km]bps\b/#.ignoresCase(), with: "")
      .trimmingCharacters(in: .whitespaces)
    return remainder.isEmpty ? nil : remainder
  }
}

/// Direct play, direct stream, or transcode — a word and a tint, never a tint
/// alone.
struct DecisionBadge: View {
  let session: TautulliSession

  var body: some View {
    Text(label)
      .font(.caption2.weight(.medium))
      .padding(.horizontal, 6)
      .padding(.vertical, 2)
      .background(tint.opacity(0.15), in: Capsule())
      .foregroundStyle(tint)
      .accessibilityHidden(true)
  }

  /// "Transcode (audio)" when only the audio is being converted: that is a
  /// cheap operation, and lumping it in with a video transcode misrepresents
  /// what the server is doing.
  private var label: String {
    guard session.decision == .transcode else { return session.decision.displayName }
    return session.isVideoTranscoding ? "Transcode" : "Transcode (audio)"
  }

  private var tint: Color {
    switch session.decision {
    case .directPlay: .green
    case .directStream: .blue
    case .transcode: session.isVideoTranscoding ? .orange : .yellow
    case .unknown: .secondary
    }
  }
}
