import SwiftUI
import TowerCore

/// The Parity screen: the current check with its controls, and the history of
/// past checks.
///
/// Re-reads the current check from `DashboardStore` on every render (ADR 0002),
/// so the dashboard's poll keeps it live and an action fired here shows here.
/// The history has its own store, created when the screen opens: nothing else
/// reads it, and it is fetched once per visit rather than polled.
struct ParityCheckView: View {
  @Bindable var store: DashboardStore
  @State private var history: ParityHistoryStore

  init(store: DashboardStore) {
    self.store = store
    _history = State(initialValue: store.makeParityHistoryStore())
  }

  var body: some View {
    List {
      if case .actionFailed(_, let error) = store.state {
        Section {
          Text(error.message)
            .font(.callout)
            .foregroundStyle(.red)
            .accessibilityIdentifier("parity.error")
        }
      }
      if let snapshot = store.state.value {
        currentSection(snapshot)
      }
      historySection
    }
    .navigationTitle("Parity")
    .navigationBarTitleDisplayMode(.inline)
    .task { await history.appeared() }
    .refreshable {
      async let dashboard: Void = store.refresh()
      async let records: Void = history.refresh()
      _ = await (dashboard, records)
    }
  }

  private func currentSection(_ snapshot: DashboardSnapshot) -> some View {
    let parity = snapshot.parity
    let actions = snapshot.availableParityActions
    return Section("Current Check") {
      LabeledContent("Status", value: parity.state.displayName)
        .accessibilityIdentifier("parity.status")
      if parity.isActive {
        ProgressView(value: parity.progressFraction ?? 0) {
          Text(progressLine(parity))
            .font(.subheadline)
        }
        .tint(parity.state == .paused ? Color.secondary : Color.accentColor)
        if parity.correcting {
          LabeledContent("Mode", value: "Correcting errors")
        }
      }
      if !actions.isEmpty {
        ParityControls(actions: actions, actionInFlight: store.parityActionInFlight) { action, correct in
          Task {
            await store.perform(action, correct: correct)
            // A cancelled check becomes a history row.
            if action == .cancel { await history.refresh() }
          }
        }
      }
    }
  }

  /// "63% · 150 MB/s". A nil percent is "—", not 0%, and the idle "0" speed
  /// and a paused check's last speed are dropped, as on the hero card.
  private func progressLine(_ parity: ParityStatus) -> String {
    var line = parity.progressPercent.map { "\($0)%" } ?? "—"
    if parity.state != .paused, let speed = parity.speed, !speed.isEmpty, speed != "0" {
      line += " · \(speed)"
    }
    return line
  }

  @ViewBuilder
  private var historySection: some View {
    Section("History") {
      switch history.state {
      case .idle, .loading:
        HStack {
          Spacer()
          ProgressView()
          Spacer()
        }
        .accessibilityIdentifier("parity.history.loading")
      case .failed(let error):
        VStack(alignment: .leading, spacing: 8) {
          Text(error.message)
            .foregroundStyle(.red)
          Button("Try Again") { Task { await history.load() } }
        }
        .accessibilityIdentifier("parity.history.error")
      case .loaded(let records), .actionFailed(let records, _):
        if case .actionFailed(_, let error) = history.state {
          Text(error.message)
            .font(.caption)
            .foregroundStyle(.red)
        }
        if records.isEmpty {
          Text("No parity checks have run on this server.")
            .foregroundStyle(.secondary)
            .accessibilityIdentifier("parity.history.empty")
        }
        ForEach(records) { record in
          ParityHistoryRow(record: record)
        }
      }
    }
  }
}

/// One past check: its date and status, then duration, speed and errors.
/// A value the server did not report is left out of the line rather than
/// shown as zero.
struct ParityHistoryRow: View {
  let record: ParityCheckRecord

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack(alignment: .firstTextBaseline) {
        Text(dateText)
          .font(.body)
        Spacer(minLength: 8)
        Text(record.state.displayName)
          .font(.subheadline)
          .foregroundStyle(statusColor)
      }
      Text("\(detailPrefix)\(errorsText)")
        .font(.subheadline)
        .foregroundStyle(.secondary)
    }
    .accessibilityElement(children: .combine)
    .accessibilityIdentifier("parity.history.row.\(record.id)")
  }

  private var dateText: String {
    guard let date = record.date else { return "Unknown date" }
    return date.formatted(date: .abbreviated, time: .shortened)
  }

  /// Duration and speed, each left out when the server did not report it,
  /// with the separator before the error count.
  private var detailPrefix: String {
    var parts: [String] = []
    if let seconds = record.durationSeconds, seconds > 0 {
      parts.append(Formatters.duration(seconds: seconds))
    }
    if let speed = record.speedText {
      parts.append(speed)
    }
    return parts.map { "\($0) · " }.joined()
  }

  /// Orange when a check found errors. The colour is on the count, not the
  /// status: a completed check with errors still completed, and orange on
  /// the status is what marks a cancelled one.
  private var errorsText: Text {
    guard let errors = record.errors else { return Text("Errors unknown") }
    let text = Text(Formatters.count(errors, "error"))
    return errors > 0 ? text.foregroundStyle(.orange) : text
  }

  private var statusColor: Color {
    switch record.state {
    case .completed: .secondary
    case .failed: .red
    case .cancelled: .orange
    default: .secondary
    }
  }
}

#Preview("History rows") {
  List {
    ParityHistoryRow(record: ParityCheckRecord(
      id: 0, date: .now.addingTimeInterval(-86_400 * 21), durationSeconds: 90_128,
      speed: "133.1 MB/s", state: .completed, errors: 0
    ))
    ParityHistoryRow(record: ParityCheckRecord(
      id: 1, date: .now.addingTimeInterval(-86_400 * 52), durationSeconds: 111_037,
      speed: "108.1 MB/s", state: .completed, errors: 12
    ))
    ParityHistoryRow(record: ParityCheckRecord(
      id: 2, date: nil, durationSeconds: 0, speed: "nan B/s", state: .completed, errors: nil
    ))
  }
}
