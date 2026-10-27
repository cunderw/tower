// @generated
// This file was automatically generated and should not be edited.

import ApolloTestSupport
@testable import TowerAPI

nonisolated public final class Capacity: MockObject {
  public static let objectType: ApolloAPI.Object = TowerAPI.Objects.Capacity
  public static let _mockFields = MockFields()
  public typealias MockValueCollectionType = Array<Mock<Capacity>>

  public struct MockFields: Sendable {
    @Field<String>("free") public var free
    @Field<String>("total") public var total
    @Field<String>("used") public var used
  }
}

public extension Mock where O == Capacity {
  convenience init(
    free: String = "",
    total: String = "",
    used: String = ""
  ) {
    self.init()
    _setScalar(free, for: \.free)
    _setScalar(total, for: \.total)
    _setScalar(used, for: \.used)
  }
}
