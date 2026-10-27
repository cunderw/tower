import ApolloTestSupport
import Testing
@testable import TowerAPI
import TowerAPITestMocks
@testable import TowerData
import TowerCore

// Exercises `ServerNotification.init(from:)` and the overview/count mapping —
// the Apollo → domain boundary behind `LiveNotificationRepository`. The
// repository's own guards and mutation wiring are covered in
// `NotificationRepositoryStubTests.swift`.
//
// See `DashboardMappingTests.swift` for the Apollo `Mock<O>` crash
// these explicit constructions guard against.

private func makeQuery(
  notifications: Mock<TowerAPITestMocks.Notifications>
) -> Mock<TowerAPITestMocks.Query> {
  Mock<TowerAPITestMocks.Query>(
    array: Mock<TowerAPITestMocks.UnraidArray>(
      capacity: Mock<TowerAPITestMocks.ArrayCapacity>(
        kilobytes: Mock<TowerAPITestMocks.Capacity>(free: "0", total: "0", used: "0")
      ),
      parityCheckStatus: Mock<TowerAPITestMocks.ParityCheck>(status: .case(.neverRun)),
      state: .case(.started)
    ),
    docker: Mock<TowerAPITestMocks.Docker>(containers: []),
    info: Mock<TowerAPITestMocks.Info>(
      cpu: Mock<TowerAPITestMocks.InfoCpu>(),
      os: Mock<TowerAPITestMocks.InfoOs>()
    ),
    metrics: Mock<TowerAPITestMocks.Metrics>(),
    notifications: notifications,
    shares: [],
    vms: Mock<TowerAPITestMocks.Vms>(domains: [])
  )
}

private func notificationMock(
  description: String = "UPS on tower is running on battery power",
  id: TowerAPI.PrefixedID = "hash:alert-1",
  importance: GraphQLEnum<TowerAPI.NotificationImportance> = .case(.alert),
  link: String? = "/Settings/UPSsettings",
  subject: String = "UPS Alert",
  timestamp: String? = "2026-07-30T02:57:55.000Z",
  title: String = "Unraid Server Alert",
  type: GraphQLEnum<TowerAPI.NotificationType> = .case(.unread)
) -> Mock<TowerAPITestMocks.Notification> {
  Mock<TowerAPITestMocks.Notification>(
    description: description, id: id, importance: importance, link: link,
    subject: subject, timestamp: timestamp, title: title, type: type
  )
}

private func mapOne(
  _ notification: Mock<TowerAPITestMocks.Notification>
) async throws -> ServerNotification {
  let data = await NotificationListQuery.Data.from(
    makeQuery(
      notifications: Mock<TowerAPITestMocks.Notifications>(
        list: [notification],
        overview: Mock<TowerAPITestMocks.NotificationOverview>(
          archive: Mock<TowerAPITestMocks.NotificationCounts>(),
          unread: Mock<TowerAPITestMocks.NotificationCounts>()
        )
      )
    )
  )
  return try #require(data.notifications.list.map(ServerNotification.init(from:)).first)
}

@Test func mapsEveryRenderedField() async throws {
  let notification = try await mapOne(notificationMock())

  #expect(notification.id == "hash:alert-1")
  #expect(notification.title == "Unraid Server Alert")
  #expect(notification.subject == "UPS Alert")
  #expect(notification.description == "UPS on tower is running on battery power")
  #expect(notification.importance == .alert)
  #expect(notification.kind == .unread)
  #expect(notification.linkPath == "/Settings/UPSsettings")
  #expect(notification.timestamp != nil)
}

@Test func mapsUnrecognizedImportanceToUnknown() async throws {
  // A future Unraid adding an importance must degrade, not blank the sheet.
  let notification = try await mapOne(notificationMock(importance: .unknown("CRITICAL")))

  #expect(notification.importance == .unknown)
  #expect(!notification.importance.displayName.isEmpty)
}

@Test func anAbsentTimestampBecomesNilWithoutCostingTheNotification() async throws {
  // `timestamp` is nullable on the wire. The notification is the payload; the
  // timestamp is metadata.
  let notification = try await mapOne(notificationMock(timestamp: nil))

  #expect(notification.timestamp == nil)
  #expect(notification.subject == "UPS Alert")
  #expect(!notification.description.isEmpty)
}

@Test func anUnparseableTimestampBecomesNilRatherThanThrowing() async throws {
  // The degrading path `DateTime` stays a `String` for: a value Apollo
  // would have thrown on costs the timestamp, not the page.
  let notification = try await mapOne(notificationMock(timestamp: "last Tuesday"))

  #expect(notification.timestamp == nil)
  #expect(notification.subject == "UPS Alert")
}

@Test func parsesTheLiveServersTimestampFormatIncludingMilliseconds() async throws {
  // The shape Unraid sends, fractional seconds and all.
  let notification = try await mapOne(notificationMock(timestamp: "2026-07-30T02:57:55.000Z"))
  let parsed = try #require(notification.timestamp)

  #expect(parsed.timeIntervalSince1970 == 1_785_380_275)
}

@Test func anEmptyLinkBecomesNilSoNoDeadAffordanceRenders() async throws {
  #expect(try await mapOne(notificationMock(link: "")).linkPath == nil)
  #expect(try await mapOne(notificationMock(link: nil)).linkPath == nil)
}

@Test func theLinkIsCarriedAsARelativePathNotAURL() async throws {
  // Unraid sends `"/Settings/UPSsettings"`. Passing that to `URL(string:)`
  // succeeds and yields a *relative* URL that opens nothing — the mistake the
  // model's doc comment exists to prevent, so the raw path must survive the
  // mapping untouched for the app layer to resolve.
  let notification = try await mapOne(notificationMock(link: "/Settings/UPSsettings"))

  #expect(notification.linkPath == "/Settings/UPSsettings")
  #expect(notification.linkPath?.hasPrefix("/") == true)
}

// The overview mapping is covered in `NotificationRepositoryStubTests.swift`
// instead of here: `NotificationOverview.init(from:)` is `fileprivate` because
// its parameter is a *private* structural protocol over three differently-named
// generated types, and widening either to reach it from a test would trade real
// encapsulation for a shortcut. The stub tests exercise it through `overview()`,
// which is the only path the app uses anyway.
