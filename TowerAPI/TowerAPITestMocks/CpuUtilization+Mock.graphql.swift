// @generated
// This file was automatically generated and should not be edited.

import ApolloTestSupport
@testable import TowerAPI

nonisolated public final class CpuUtilization: MockObject {
  public static let objectType: ApolloAPI.Object = TowerAPI.Objects.CpuUtilization
  public static let _mockFields = MockFields()
  public typealias MockValueCollectionType = Array<Mock<CpuUtilization>>

  public struct MockFields: Sendable {
    @Field<Double>("percentTotal") public var percentTotal
  }
}

public extension Mock where O == CpuUtilization {
  convenience init(
    percentTotal: Double = 0.0
  ) {
    self.init()
    _setScalar(percentTotal, for: \.percentTotal)
  }
}
