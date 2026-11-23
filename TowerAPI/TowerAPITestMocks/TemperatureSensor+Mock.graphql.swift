// @generated
// This file was automatically generated and should not be edited.

import ApolloTestSupport
@testable import TowerAPI

nonisolated public final class TemperatureSensor: MockObject {
  public static let objectType: ApolloAPI.Object = TowerAPI.Objects.TemperatureSensor
  public static let _mockFields = MockFields()
  public typealias MockValueCollectionType = Array<Mock<TemperatureSensor>>

  public struct MockFields: Sendable {
    @Field<TemperatureReading>("current") public var current
    @Field<GraphQLEnum<TowerAPI.SensorType>>("type") public var type
  }
}

public extension Mock where O == TemperatureSensor {
  convenience init(
    current: Mock<TemperatureReading> = Mock<TemperatureReading>(),
    type: GraphQLEnum<TowerAPI.SensorType> = .case(.cpuPackage)
  ) {
    self.init()
    _setEntity(current, for: \.current)
    _setScalar(type, for: \.type)
  }
}
