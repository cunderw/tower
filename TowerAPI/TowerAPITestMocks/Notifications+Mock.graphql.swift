// @generated
// This file was automatically generated and should not be edited.

import ApolloTestSupport
@testable import TowerAPI

nonisolated public final class Notifications: MockObject {
  public static let objectType: ApolloAPI.Object = TowerAPI.Objects.Notifications
  public static let _mockFields = MockFields()
  public typealias MockValueCollectionType = Array<Mock<Notifications>>

  public struct MockFields: Sendable {
    @Field<TowerAPI.PrefixedID>("id") public var id
    @Field<[Notification]>("list") public var list
    @Field<NotificationOverview>("overview") public var overview
  }
}

public extension Mock where O == Notifications {
  convenience init(
    id: TowerAPI.PrefixedID = .defaultMockValue,
    list: [Mock<Notification>] = [],
    overview: Mock<NotificationOverview> = Mock<NotificationOverview>()
  ) {
    self.init()
    _setScalar(id, for: \.id)
    _setList(list, for: \.list)
    _setEntity(overview, for: \.overview)
  }
}
