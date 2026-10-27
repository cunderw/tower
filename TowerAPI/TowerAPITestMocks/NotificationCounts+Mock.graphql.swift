// @generated
// This file was automatically generated and should not be edited.

import ApolloTestSupport
@testable import TowerAPI

nonisolated public final class NotificationCounts: MockObject {
  public static let objectType: ApolloAPI.Object = TowerAPI.Objects.NotificationCounts
  public static let _mockFields = MockFields()
  public typealias MockValueCollectionType = Array<Mock<NotificationCounts>>

  public struct MockFields: Sendable {
    @Field<Int>("alert") public var alert
    @Field<Int>("info") public var info
    @Field<Int>("total") public var total
    @Field<Int>("warning") public var warning
  }
}

public extension Mock where O == NotificationCounts {
  convenience init(
    alert: Int = 0,
    info: Int = 0,
    total: Int = 0,
    warning: Int = 0
  ) {
    self.init()
    _setScalar(alert, for: \.alert)
    _setScalar(info, for: \.info)
    _setScalar(total, for: \.total)
    _setScalar(warning, for: \.warning)
  }
}
