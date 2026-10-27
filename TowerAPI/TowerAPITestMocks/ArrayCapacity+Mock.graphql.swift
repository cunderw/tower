// @generated
// This file was automatically generated and should not be edited.

import ApolloTestSupport
@testable import TowerAPI

nonisolated public final class ArrayCapacity: MockObject {
  public static let objectType: ApolloAPI.Object = TowerAPI.Objects.ArrayCapacity
  public static let _mockFields = MockFields()
  public typealias MockValueCollectionType = Array<Mock<ArrayCapacity>>

  public struct MockFields: Sendable {
    @Field<Capacity>("kilobytes") public var kilobytes
  }
}

public extension Mock where O == ArrayCapacity {
  convenience init(
    kilobytes: Mock<Capacity> = Mock<Capacity>()
  ) {
    self.init()
    _setEntity(kilobytes, for: \.kilobytes)
  }
}
