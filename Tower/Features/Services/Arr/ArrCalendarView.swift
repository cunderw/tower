import SwiftUI
import TowerCore

/// The calendar section: the past week's and upcoming releases, grouped by day.
struct ArrCalendarView: View {
  @Bindable var store: ArrCalendarStore

  var body: some View {
    content
      .task {
        await store.appeared()
      }
  }

  @ViewBuilder
  private var content: some View {
    switch store.state {
    case .idle, .loading:
      LoadingStateView(title: "Loading calendar…", isLoadInFlight: store.isLoadInFlight) {
        store.cancelLoad()
      }
    case .failed(let error):
      VStack(spacing: 16) {
        ContentUnavailableView {
          Label(error.message, systemImage: "exclamationmark.triangle")
        } description: {
          if let suggestion = error.serviceRecoverySuggestion { Text(suggestion) }
        }
        .accessibilityIdentifier("calendar.error")
        Button("Try Again") { Task { await store.load() } }
          .accessibilityIdentifier("calendar.retry")
      }
    case .loaded, .actionFailed:
      list
    }
  }

  private var list: some View {
    List {
      ForEach(store.days) { day in
        Section(header: dayHeader(day)) {
          ForEach(day.entries) { entry in
            ArrCalendarRow(entry: entry)
          }
        }
      }
    }
    .overlay {
      if store.isEmpty {
        ContentUnavailableView(
          "Nothing Scheduled", systemImage: "calendar",
          description: Text("Nothing from the past week or the next four weeks.")
        )
        .accessibilityIdentifier("calendar.empty")
      }
    }
    .refreshable { await store.refresh() }
  }

  private func dayHeader(_ day: ArrCalendarDay) -> some View {
    HStack {
      Text(day.date.formatted(.dateTime.weekday(.wide).day().month(.abbreviated)))
      if day.isToday() {
        Text("Today")
          .font(.caption2.weight(.semibold))
          .padding(.horizontal, 5)
          .padding(.vertical, 1)
          .background(.tint.opacity(0.2), in: Capsule())
      }
    }
    .accessibilityIdentifier("calendar.day.\(Int(day.date.timeIntervalSince1970))")
  }
}

struct ArrCalendarRow: View {
  let entry: ArrCalendarEntry

  var body: some View {
    HStack(alignment: .top, spacing: 8) {
      VStack(alignment: .leading, spacing: 2) {
        Text(entry.title)
          .font(.callout)
          .lineLimit(2)
        if let subtitle = entry.subtitle {
          Text(subtitle)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        if let date = entry.date {
          Text(date.formatted(date: .omitted, time: .shortened))
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
      }

      Spacer(minLength: 4)

      // Already downloaded is the fact worth marking: the rest of the calendar
      // is things to wait for, and this one isn't.
      if entry.hasFile {
        Label("Downloaded", systemImage: "checkmark.circle.fill")
          .labelStyle(.iconOnly)
          .foregroundStyle(.green)
          .accessibilityHidden(true)
      } else if !entry.isMonitored {
        Text("Unmonitored")
          .font(.caption2)
          .foregroundStyle(.secondary)
      }
    }
    .padding(.vertical, 2)
    .accessibilityElement(children: .combine)
    .accessibilityLabel(accessibilityLabel)
    .accessibilityIdentifier("calendar.entry.\(entry.id)")
  }

  private var accessibilityLabel: String {
    var parts = [entry.title]
    if let subtitle = entry.subtitle { parts.append(subtitle) }
    if entry.hasFile { parts.append("Downloaded") }
    if !entry.isMonitored { parts.append("Unmonitored") }
    return parts.joined(separator: ", ")
  }
}

/// The history section: what this service has done lately.
struct ArrHistoryView: View {
  @Bindable var store: ArrHistoryStore
  /// Opens the media a record belongs to. `nil` when this service's library
  /// isn't reachable from here, in which case rows don't pretend to be links.
  let openMedia: ((Int) -> Void)?

  var body: some View {
    content
      .task {
        await store.appeared()
      }
  }

  @ViewBuilder
  private var content: some View {
    switch store.state {
    case .idle, .loading:
      LoadingStateView(title: "Loading history…", isLoadInFlight: store.isLoadInFlight) {
        store.cancelLoad()
      }
    case .failed(let error):
      VStack(spacing: 16) {
        ContentUnavailableView {
          Label(error.message, systemImage: "exclamationmark.triangle")
        } description: {
          if let suggestion = error.serviceRecoverySuggestion { Text(suggestion) }
        }
        .accessibilityIdentifier("history.error")
        Button("Try Again") { Task { await store.load() } }
          .accessibilityIdentifier("history.retry")
      }
    case .loaded, .actionFailed:
      list
    }
  }

  private var list: some View {
    List {
      ForEach(store.records) { record in
        if let openMedia, let mediaID = record.mediaID {
          Button { openMedia(mediaID) } label: {
            ArrHistoryRow(record: record)
          }
          .buttonStyle(.plain)
        } else {
          ArrHistoryRow(record: record)
        }
      }
    }
    .overlay {
      if store.isEmpty {
        ContentUnavailableView(
          "No History", systemImage: "clock.arrow.circlepath",
          description: Text("This service hasn't grabbed or imported anything yet.")
        )
        .accessibilityIdentifier("history.empty")
      }
    }
    .refreshable { await store.refresh() }
  }
}

struct ArrHistoryRow: View {
  let record: ArrHistoryRecord

  var body: some View {
    HStack(alignment: .top, spacing: 8) {
      Image(systemName: icon)
        .foregroundStyle(record.event.isFailure ? .red : .secondary)
        .frame(width: 20)
        .accessibilityHidden(true)

      VStack(alignment: .leading, spacing: 2) {
        Text(record.displayTitle)
          .font(.callout)
          .lineLimit(2)
        HStack(spacing: 6) {
          Text(record.event.displayName)
          if let quality = record.quality {
            Text("·")
            Text(quality)
          }
          if let date = record.date {
            Text("·")
            // Relative time: "2 hours ago" is what a history feed is read for.
            Text(date.formatted(.relative(presentation: .named)))
          }
        }
        .font(.caption)
        .foregroundStyle(record.event.isFailure ? .red : .secondary)
      }

      Spacer(minLength: 4)
    }
    .padding(.vertical, 2)
    .accessibilityElement(children: .combine)
    .accessibilityIdentifier("history.record.\(record.id)")
  }

  private var icon: String {
    switch record.event {
    case .grabbed: "arrow.down.circle"
    case .downloadFolderImported: "checkmark.circle"
    case .downloadFailed: "exclamationmark.triangle"
    case .fileDeleted: "trash"
    case .fileRenamed: "pencil"
    case .downloadIgnored: "eye.slash"
    case .unknown: "questionmark.circle"
    }
  }
}
