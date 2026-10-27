// @generated
// This file was automatically generated and should not be edited.

import ApolloTestSupport
@testable import TowerAPI

nonisolated public final class MemoryUtilization: MockObject {
  public static let objectType: ApolloAPI.Object = TowerAPI.Objects.MemoryUtilization
  public static let _mockFields = MockFields()
  public typealias MockValueCollectionType = Array<Mock<MemoryUtilization>>

  public struct MockFields: Sendable {
    @Field<Double>("percentTotal") public var percentTotal
    @Field<TowerAPI.BigInt>("total") public var total
    @Field<TowerAPI.BigInt>("used") public var used
  }
}

public extension Mock where O == MemoryUtilization {
  convenience init(
    percentTotal: Double = 0.0,
    total: TowerAPI.BigInt = .defaultMockValue,
    used: TowerAPI.BigInt = .defaultMockValue
  ) {
    self.init()
    _setScalar(percentTotal, for: \.percentTotal)
    _setScalar(total, for: \.total)
    _setScalar(used, for: \.used)
  }
}
