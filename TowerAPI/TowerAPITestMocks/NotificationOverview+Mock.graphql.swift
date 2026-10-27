// @generated
// This file was automatically generated and should not be edited.

import ApolloTestSupport
@testable import TowerAPI

nonisolated public final class NotificationOverview: MockObject {
  public static let objectType: ApolloAPI.Object = TowerAPI.Objects.NotificationOverview
  public static let _mockFields = MockFields()
  public typealias MockValueCollectionType = Array<Mock<NotificationOverview>>

  public struct MockFields: Sendable {
    @Field<NotificationCounts>("archive") public var archive
    @Field<NotificationCounts>("unread") public var unread
  }
}

public extension Mock where O == NotificationOverview {
  convenience init(
    archive: Mock<NotificationCounts> = Mock<NotificationCounts>(),
    unread: Mock<NotificationCounts> = Mock<NotificationCounts>()
  ) {
    self.init()
    _setEntity(archive, for: \.archive)
    _setEntity(unread, for: \.unread)
  }
}
