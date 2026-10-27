import Foundation
import Testing
import TowerCore
import TowerData

// Exercises `LiveNotificationRepository` itself — the overview mapping, the
// paging arguments, and the guards — through `StubURLProtocol` (installed in the
// provider's own session). `NotificationMappingTests.swift` covers
// `ServerNotification.init(from:)`.

private func makeRepository(host: String, json: String) -> LiveNotificationRepository {
  let endpoint = URL(string: "http://\(host)/graphql")!
  StubURLProtocol.stub(url: endpoint, json: json)
  let server = Server(name: "Stub", url: URL(string: "http://\(host)")!, apiKey: "test-key")
  return LiveNotificationRepository(
    provider: ApolloClientProvider(server: server, sessionConfiguration: StubURLProtocol.configuration())
  )
}

private func countsJSON(info: Int, warning: Int, alert: Int, total: Int) -> String {
  #"{"__typename": "NotificationCounts", "info": \#(info), "warning": \#(warning), "alert": \#(alert), "total": \#(total)}"#
}

private func overviewResponse(unread: String, archive: String) -> String {
  """
  {"data": {"notifications": {"__typename": "Notifications", "id": "hash:notifications", \
  "overview": {"__typename": "NotificationOverview", "unread": \(unread), "archive": \(archive)}}}}
  """
}

private func notificationJSON(
  id: String, subject: String = "UPS Alert", importance: String = "ALERT",
  type: String = "UNREAD", timestamp: String? = "2026-07-30T02:57:55.000Z", link: String? = nil
) -> String {
  let timestampJSON = timestamp.map { "\"\($0)\"" } ?? "null"
  let linkJSON = link.map { "\"\($0)\"" } ?? "null"
  return """
  {"__typename": "Notification", "id": "\(id)", "title": "Unraid Server Alert", \
  "subject": "\(subject)", "description": "UPS on tower is running on battery power", \
  "importance": "\(importance)", "link": \(linkJSON), "type": "\(type)", "timestamp": \(timestampJSON)}
  """
}

private func listResponse(_ notifications: [String]) -> String {
  """
  {"data": {"notifications": {"__typename": "Notifications", "id": "hash:notifications", \
  "list": [\(notifications.joined(separator: ", "))]}}}
  """
}

// MARK: - overview()

@Test func overviewMapsBothBucketsOffTheWire() async throws {
  // Two unread alerts and six archived.
  let repository = makeRepository(
    host: "stub-notif-overview.test",
    json: overviewResponse(
      unread: countsJSON(info: 0, warning: 0, alert: 2, total: 2),
      archive: countsJSON(info: 1, warning: 0, alert: 5, total: 6)
    )
  )

  let overview = try await repository.overview()

  #expect(overview.unread == NotificationCounts(info: 0, warning: 0, alert: 2, total: 2))
  #expect(overview.archive == NotificationCounts(info: 1, warning: 0, alert: 5, total: 6))
  #expect(overview.badgeCount == 2)
  #expect(overview.hasUnreadWarningsOrAlerts)
}

@Test func overviewWithNothingUnreadProducesNoBadge() async throws {
  let repository = makeRepository(
    host: "stub-notif-overview-empty.test",
    json: overviewResponse(
      unread: countsJSON(info: 0, warning: 0, alert: 0, total: 0),
      archive: countsJSON(info: 1, warning: 0, alert: 5, total: 6)
    )
  )

  let overview = try await repository.overview()

  #expect(overview.badgeCount == nil)
  #expect(!overview.hasUnreadWarningsOrAlerts, "archived alerts must not light up the bell")
}

@Test func overviewThrowsGraphQLErrorPreservingMessages() async throws {
  let repository = makeRepository(
    host: "stub-notif-overview-errors.test",
    json: #"{"data": null, "errors": [{"message": "Forbidden"}]}"#
  )

  do {
    _ = try await repository.overview()
    Issue.record("expected overview() to throw")
  } catch let error as AppError {
    #expect(error == .graphQL(["Forbidden"]))
  }
}

@Test func overviewThrowsDecodingWhenDataIsMissing() async throws {
  let repository = makeRepository(host: "stub-notif-overview-nil.test", json: #"{"data": null}"#)

  do {
    _ = try await repository.overview()
    Issue.record("expected overview() to throw")
  } catch let error as AppError {
    guard case .decoding = error else {
      Issue.record("expected .decoding, got \(error)")
      return
    }
  }
}

// MARK: - page()

@Test func pagePreservesTheServersOrderRatherThanResorting() async throws {
  // The server returns newest-first, and `offset` paging only makes sense against
  // its own ordering — sorting client-side would shuffle rows between pages.
  let repository = makeRepository(
    host: "stub-notif-page-order.test",
    json: listResponse([
      notificationJSON(id: "hash:3", subject: "Newest"),
      notificationJSON(id: "hash:2", subject: "Middle"),
      notificationJSON(id: "hash:1", subject: "Oldest"),
    ])
  )

  let page = try await repository.page(kind: .unread, offset: 0, limit: 25)

  #expect(page.notifications.map(\.subject) == ["Newest", "Middle", "Oldest"])
}

@Test func aShortPageReportsItselfAsTheLast() async throws {
  // The only end-of-list signal the API offers — `list` carries no total.
  let repository = makeRepository(
    host: "stub-notif-page-short.test",
    json: listResponse([notificationJSON(id: "hash:1")])
  )

  let page = try await repository.page(kind: .unread, offset: 0, limit: 25)

  #expect(page.notifications.count == 1)
  #expect(page.requestedLimit == 25)
  #expect(page.isLastPage)
}

@Test func anEmptyPageIsAValidAnswerNotAnError() async throws {
  // Paging past the end, or an empty bucket. Both are real states.
  let repository = makeRepository(host: "stub-notif-page-empty.test", json: listResponse([]))

  let page = try await repository.page(kind: .archive, offset: 100, limit: 25)

  #expect(page.notifications.isEmpty)
  #expect(page.isLastPage)
}

@Test func pageClampsNonsenseArgumentsRatherThanTrapping() async throws {
  // `offset`/`limit` come from a paging caller and are converted to `Int32` for
  // the wire. A negative offset or a zero limit should be clamped to something
  // the server can answer, not crash the app — and `requestedLimit` must report
  // the clamped value, or `isLastPage` would compare against a limit that was
  // never asked for.
  let repository = makeRepository(
    host: "stub-notif-page-clamp.test",
    json: listResponse([notificationJSON(id: "hash:1")])
  )

  let page = try await repository.page(kind: .unread, offset: -5, limit: 0)

  #expect(page.requestedLimit == 1)
  #expect(page.notifications.count == 1)
  #expect(!page.isLastPage, "one notification for a clamped limit of one is a full page")
}

@Test func pageThrowsGraphQLErrorPreservingMessages() async throws {
  let repository = makeRepository(
    host: "stub-notif-page-errors.test",
    json: #"{"data": null, "errors": [{"message": "bad filter"}]}"#
  )

  do {
    _ = try await repository.page(kind: .unread, offset: 0, limit: 25)
    Issue.record("expected page() to throw")
  } catch let error as AppError {
    #expect(error == .graphQL(["bad filter"]))
  }
}

// MARK: - Mutations

@Test func deleteReturnsTheServersRecomputedOverviewRatherThanADecrement() async throws {
  // `deleteNotification` answers with the recomputed overview, so there is no
  // second round trip and no locally-adjusted count to drift from the server.
  let repository = makeRepository(
    host: "stub-notif-delete.test",
    json: """
    {"data": {"deleteNotification": {"__typename": "NotificationOverview", \
    "unread": \(countsJSON(info: 0, warning: 0, alert: 1, total: 1)), \
    "archive": \(countsJSON(info: 1, warning: 0, alert: 5, total: 6))}}}
    """
  )

  let overview = try await repository.delete(id: "hash:alert-1", kind: .unread)

  #expect(overview.unread.total == 1)
  #expect(overview.badgeCount == 1)
}

@Test func archiveAllReturnsTheRecomputedOverview() async throws {
  let repository = makeRepository(
    host: "stub-notif-archive-all.test",
    json: """
    {"data": {"archiveAll": {"__typename": "NotificationOverview", \
    "unread": \(countsJSON(info: 0, warning: 0, alert: 0, total: 0)), \
    "archive": \(countsJSON(info: 1, warning: 0, alert: 7, total: 8))}}}
    """
  )

  let overview = try await repository.archiveAll()

  #expect(overview.badgeCount == nil, "archiving everything must clear the badge")
  #expect(overview.archive.total == 8)
}

@Test func aFailedMutationThrowsRatherThanReturningAStaleOverview() async throws {
  // The failure that would be worst to swallow: reporting a fresh overview after
  // a mutation the server rejected would tell the user their action landed.
  let repository = makeRepository(
    host: "stub-notif-archive-error.test",
    json: #"{"data": null, "errors": [{"message": "Not found"}]}"#
  )

  do {
    _ = try await repository.archive(id: "hash:gone")
    Issue.record("expected archive() to throw")
  } catch let error as AppError {
    #expect(error == .graphQL(["Not found"]))
  }
}
