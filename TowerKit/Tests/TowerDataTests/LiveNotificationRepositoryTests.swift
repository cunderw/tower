import Foundation
import Testing
import TowerCore
import TowerData

// Proves `LiveNotificationRepository`'s reads end to end against a real Unraid
// GraphQL API — opt-in only, skipped whenever `UNRAID_URL`/`UNRAID_API_KEY`
// aren't set:
// ```
// set -a; source .env.local; set +a
// cd TowerKit && swift test --filter LiveNotificationRepositoryTests
// ```
//
// **Read-only, and this one matters.** A real server can hold an alert
// nobody has acted on yet, such as a UPS battery warning. Archiving it would
// hide a genuine warning; deleting it would destroy it. The mutation paths are
// proven against `StubURLProtocol` in `NotificationRepositoryStubTests.swift`,
// which costs nothing.

private enum LiveServerCredentials {
  static var server: Server? {
    let environment = ProcessInfo.processInfo.environment
    guard let urlString = environment["UNRAID_URL"], let url = URL(string: urlString),
          let apiKey = environment["UNRAID_API_KEY"], !apiKey.isEmpty
    else { return nil }
    return Server(name: "Live", url: url, apiKey: apiKey)
  }
}

@Suite(.enabled(if: LiveServerCredentials.server != nil))
struct LiveNotificationRepositoryTests {
  private func repository() throws -> LiveNotificationRepository {
    let server = try #require(LiveServerCredentials.server)
    return LiveNotificationRepository(provider: ApolloClientProvider(server: server))
  }

  @Test func overviewSucceedsAgainstARealServer() async throws {
    let overview = try await repository().overview()

    // Not asserted against fixed counts — notifications arrive and get archived
    // all the time, so this checks the invariants instead: totals are consistent
    // with their parts, and nothing is negative.
    #expect(overview.unread.total == overview.unread.info + overview.unread.warning + overview.unread.alert)
    #expect(overview.archive.total == overview.archive.info + overview.archive.warning + overview.archive.alert)
    #expect(overview.unread.total >= 0)
    #expect(overview.archive.total >= 0)
    print("Live notification overview — unread: \(overview.unread.total), archive: \(overview.archive.total)")
  }

  @Test func aPageOfUnreadNotificationsDecodesAndIsBoundedByItsLimit() async throws {
    let page = try await repository().page(kind: .unread, offset: 0, limit: 3)

    #expect(page.notifications.count <= 3, "limit is a maximum the server must respect")
    // Every notification must be renderable regardless of what its metadata did:
    // a subject and a description are what the row and the sheet show.
    #expect(page.notifications.allSatisfy { !$0.subject.isEmpty })
    #expect(page.notifications.allSatisfy { !$0.description.isEmpty })
    #expect(page.notifications.allSatisfy { $0.kind == .unread }, "the unread filter returned something else")
    // No importance may decode as `.unknown` against the current server — if one
    // does, Unraid added a case and the UI needs a look, which is exactly what
    // this assertion is for.
    #expect(page.notifications.allSatisfy { $0.importance != .unknown })
  }

  @Test func theArchiveBucketIsSeparateFromUnread() async throws {
    // Proves the filter's `type` argument is actually wired to the right thing —
    // a mistake here would silently show the wrong bucket in both tabs of the
    // sheet.
    let archived = try await repository().page(kind: .archive, offset: 0, limit: 5)

    #expect(archived.notifications.allSatisfy { $0.kind == .archive })
  }

  @Test func pagingPastTheEndReturnsAnEmptyPageRatherThanFailing() async throws {
    let page = try await repository().page(kind: .unread, offset: 10_000, limit: 5)

    #expect(page.notifications.isEmpty)
    #expect(page.isLastPage)
  }
}
