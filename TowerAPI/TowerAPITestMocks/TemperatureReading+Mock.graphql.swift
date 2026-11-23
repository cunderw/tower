// @generated
// This file was automatically generated and should not be edited.

import ApolloTestSupport
@testable import TowerAPI

nonisolated public final class TemperatureReading: MockObject {
  public static let objectType: ApolloAPI.Object = TowerAPI.Objects.TemperatureReading
  public static let _mockFields = MockFields()
  public typealias MockValueCollectionType = Array<Mock<TemperatureReading>>

  public struct MockFields: Sendable {
    @Field<GraphQLEnum<TowerAPI.TemperatureUnit>>("unit") public var unit
    @Field<Double>("value") public var value
  }
}

public extension Mock where O == TemperatureReading {
  convenience init(
    unit: GraphQLEnum<TowerAPI.TemperatureUnit> = .case(.celsius),
    value: Double = 0.0
  ) {
    self.init()
    _setScalar(unit, for: \.unit)
    _setScalar(value, for: \.value)
  }
}
