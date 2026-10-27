import SwiftUI
import TowerCore

/// One row in the notification sheet.
///
/// Leads with `subject` rather than `title`: Unraid's `title` is a generic banner
/// ("Unraid Server Alert") repeated on every notification from a given source,
/// while `subject` is the specific one ("UPS Alert"). A list of identical titles
/// with the useful text buried underneath would be a worse list.
///
/// **Importance is never colour alone.** The glyph carries a shape as well as a
/// tint (`exclamationmark.triangle.fill` vs `info.circle`), and the merged
/// accessibility label names the importance in words — colour is never the only
/// signal, least of all on the one surface in the app where severity is the
/// whole point.
struct NotificationRow: View {
  let notification: ServerNotification
  /// Whether an action is running against this notification.
  let isInFlight: Bool

  var body: some View {
    HStack(alignment: .top, spacing: 10) {
      Image(systemName: importanceSymbol)
        .foregroundStyle(importanceColor)
        .font(.body)
        // Decorative here: the merged label below names the importance in words,
        // and a glyph announced separately would say it twice.
        .accessibilityHidden(true)
        .padding(.top, 2)

      VStack(alignment: .leading, spacing: 3) {
        Text(notification.subject)
          .font(.body)
          .fontWeight(notification.kind == .unread ? .semibold : .regular)
        Text(notification.description)
          .font(.caption)
          .foregroundStyle(.secondary)
          // Long enough to be worth reading in place; the full text is rarely
          // longer than this and truncating to one line lost too much.
          .lineLimit(3)
        if let timestamp = notification.timestamp {
          Text(timestamp, format: .relative(presentation: .named))
            .font(.caption2)
            .foregroundStyle(.tertiary)
        }
        // No placeholder when `timestamp` is nil — an unreadable or absent
        // timestamp renders nothing rather than "unknown time", which would be
        // chrome about metadata nobody asked for.
      }

      Spacer(minLength: 0)

      if isInFlight {
        ProgressView()
          .controlSize(.small)
          .accessibilityHidden(true)
      }
    }
    .padding(.vertical, 2)
    // One VoiceOver stop per row: importance, subject, description, and the
    // relative time, in the order the row lays out.
    .accessibilityElement(children: .combine)
    .accessibilityLabel(accessibilityLabel)
    .accessibilityIdentifier("notifications.row.\(notification.id)")
  }

  /// Importance in words first, then the content. Built explicitly rather than
  /// left to `.combine` because the glyph is hidden — combining alone would drop
  /// the importance entirely, which is the one thing this row must always say.
  private var accessibilityLabel: String {
    var parts = [notification.importance.displayName, notification.subject, notification.description]
    if let timestamp = notification.timestamp {
      parts.append(timestamp.formatted(.relative(presentation: .named)))
    }
    return parts.joined(separator: ", ")
  }

  /// Distinct shapes, not just distinct tints — a triangle reads as a warning at
  /// a glance and to anyone who can't distinguish the colours.
  private var importanceSymbol: String {
    switch notification.importance {
    case .alert: "exclamationmark.triangle.fill"
    case .warning: "exclamationmark.circle.fill"
    case .info: "info.circle"
    // An importance Tower doesn't recognize gets a neutral glyph rather than
    // being guessed into one of the three above.
    case .unknown: "questionmark.circle"
    }
  }

  private var importanceColor: Color {
    switch notification.importance {
    case .alert: .red
    case .warning: .orange
    case .info: .accentColor
    case .unknown: .secondary
    }
  }
}

#Preview {
  List {
    NotificationRow(notification: .previewFixture(importance: .alert, subject: "UPS Alert"), isInFlight: false)
    NotificationRow(notification: .previewFixture(importance: .warning, subject: "Disk temperature"), isInFlight: false)
    NotificationRow(notification: .previewFixture(importance: .info, subject: "Parity check finished"), isInFlight: false)
    NotificationRow(notification: .previewFixture(importance: .unknown, subject: "Something new"), isInFlight: false)
    NotificationRow(
      notification: .previewFixture(importance: .info, subject: "No timestamp", timestamp: nil),
      isInFlight: false
    )
    NotificationRow(notification: .previewFixture(importance: .alert, subject: "Archiving…"), isInFlight: true)
  }
}

#Preview("Accessibility Size (AX5)") {
  List {
    NotificationRow(notification: .previewFixture(importance: .alert, subject: "UPS Alert"), isInFlight: false)
    NotificationRow(notification: .previewFixture(importance: .info, subject: "Parity check finished"), isInFlight: false)
  }
  .environment(\.dynamicTypeSize, .accessibility5)
}

extension ServerNotification {
  fileprivate static func previewFixture(
    importance: NotificationImportance,
    subject: String,
    timestamp: Date? = Date(timeIntervalSinceNow: -3_600)
  ) -> ServerNotification {
    ServerNotification(
      id: "hash:\(subject)", title: "Unraid Server Alert", subject: subject,
      description: "UPS on tower is running on battery power",
      importance: importance, kind: .unread, linkPath: "/Settings/UPSsettings",
      timestamp: timestamp
    )
  }
}
