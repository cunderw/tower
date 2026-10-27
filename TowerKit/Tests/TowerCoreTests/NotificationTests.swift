import Foundation
import Testing
@testable import TowerCore

@Test func importanceMapsKnownValues() {
  #expect(NotificationImportance(rawValue: "INFO") == .info)
  #expect(NotificationImportance(rawValue: "WARNING") == .warning)
  #expect(NotificationImportance(rawValue: "ALERT") == .alert)
}

@Test func importanceMapsUnrecognizedToUnknown() {
  #expect(NotificationImportance(rawValue: "CRITICAL") == .unknown)
}

@Test func everyImportanceHasNonEmptyCopy() {
  // Importance is never conveyed by colour alone, so every case —
  // including `.unknown` — needs a word.
  #expect(NotificationImportance.allCases.allSatisfy { !$0.displayName.isEmpty })
}

@Test func severityRanksAlertsFirstAndWarningsSecond() {
  #expect(NotificationImportance.alert.severityRank < NotificationImportance.warning.severityRank)
  #expect(NotificationImportance.warning.severityRank < NotificationImportance.info.severityRank)
}

@Test func unknownImportanceSortsWithInfoRatherThanAtEitherExtreme() {
  // Promoting an unrecognized importance to the top would claim a severity Tower
  // has no basis for; burying it last would hide it.
  #expect(NotificationImportance.unknown.severityRank == NotificationImportance.info.severityRank)
}

@Test func kindMapsKnownValuesAndDegrades() {
  #expect(NotificationKind(rawValue: "UNREAD") == .unread)
  #expect(NotificationKind(rawValue: "ARCHIVE") == .archive)
  #expect(NotificationKind(rawValue: "SNOOZED") == .unknown)
}

// MARK: - Overview

@Test func badgeCountIsNilRatherThanZeroWhenNothingIsUnread() {
  // A badge reading "0" is worse than no badge: it draws the eye to say nothing
  // happened.
  let overview = NotificationOverview(unread: .zero, archive: NotificationCounts(info: 1, warning: 0, alert: 5, total: 6))
  #expect(overview.badgeCount == nil)
}

@Test func badgeCountIsTheUnreadTotal() {
  // Two unread, both alerts.
  let overview = NotificationOverview(
    unread: NotificationCounts(info: 0, warning: 0, alert: 2, total: 2),
    archive: NotificationCounts(info: 1, warning: 0, alert: 5, total: 6)
  )
  #expect(overview.badgeCount == 2)
}

@Test func unreadSeverityIsSeparateFromTheCount() {
  // A count says nothing about severity. Ten unread info notices and one unread
  // alert are very different situations that produce similar badges.
  let tenInfo = NotificationOverview(
    unread: NotificationCounts(info: 10, warning: 0, alert: 0, total: 10), archive: .zero
  )
  let oneAlert = NotificationOverview(
    unread: NotificationCounts(info: 0, warning: 0, alert: 1, total: 1), archive: .zero
  )

  #expect(!tenInfo.hasUnreadWarningsOrAlerts)
  #expect(oneAlert.hasUnreadWarningsOrAlerts)
  #expect(tenInfo.badgeCount ?? 0 > oneAlert.badgeCount ?? 0)
}

@Test func archivedSeverityDoesNotAffectTheUnreadSignals() {
  // Five archived alerts must not light up the bell. Archiving is the act of
  // saying "seen".
  let overview = NotificationOverview(
    unread: .zero, archive: NotificationCounts(info: 1, warning: 0, alert: 5, total: 6)
  )
  #expect(overview.badgeCount == nil)
  #expect(!overview.hasUnreadWarningsOrAlerts)
}

// MARK: - Paging

@Test func aFullPageIsNotTheLastPage() {
  let page = NotificationPage(
    notifications: (1...25).map { .stub(id: "\($0)") }, requestedLimit: 25
  )
  #expect(!page.isLastPage)
}

@Test func aShortPageIsTheLastPage() {
  // The only end-of-list signal this API offers: `list` carries no total, and
  // `overview.total` counts the bucket rather than the filtered page.
  let page = NotificationPage(notifications: [.stub(id: "1")], requestedLimit: 25)
  #expect(page.isLastPage)
}

@Test func anEmptyPageIsTheLastPage() {
  #expect(NotificationPage(notifications: [], requestedLimit: 25).isLastPage)
}

extension ServerNotification {
  fileprivate static func stub(id: String) -> ServerNotification {
    ServerNotification(
      id: id, title: "Unraid Server Alert", subject: "UPS Alert",
      description: "UPS on tower is running on battery power", importance: .alert, kind: .unread,
      linkPath: nil, timestamp: nil
    )
  }
}
