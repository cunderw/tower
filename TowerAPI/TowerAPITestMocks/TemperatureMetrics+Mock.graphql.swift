// @generated
// This file was automatically generated and should not be edited.

import ApolloTestSupport
@testable import TowerAPI

nonisolated public final class TemperatureMetrics: MockObject {
  public static let objectType: ApolloAPI.Object = TowerAPI.Objects.TemperatureMetrics
  public static let _mockFields = MockFields()
  public typealias MockValueCollectionType = Array<Mock<TemperatureMetrics>>

  public struct MockFields: Sendable {
    @Field<[TemperatureSensor]>("sensors") public var sensors
  }
}

public extension Mock where O == TemperatureMetrics {
  convenience init(
    sensors: [Mock<TemperatureSensor>] = []
  ) {
    self.init()
    _setList(sensors, for: \.sensors)
  }
}
