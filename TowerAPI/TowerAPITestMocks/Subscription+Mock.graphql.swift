// @generated
// This file was automatically generated and should not be edited.

import ApolloTestSupport
@testable import TowerAPI

nonisolated public final class Subscription: MockObject {
  public static let objectType: ApolloAPI.Object = TowerAPI.Objects.Subscription
  public static let _mockFields = MockFields()
  public typealias MockValueCollectionType = Array<Mock<Subscription>>

  public struct MockFields: Sendable {
    @Field<CpuUtilization>("systemMetricsCpu") public var systemMetricsCpu
    @Field<MemoryUtilization>("systemMetricsMemory") public var systemMetricsMemory
    @Field<TemperatureMetrics>("systemMetricsTemperature") public var systemMetricsTemperature
  }
}

public extension Mock where O == Subscription {
  convenience init(
    systemMetricsCpu: Mock<CpuUtilization> = Mock<CpuUtilization>(),
    systemMetricsMemory: Mock<MemoryUtilization> = Mock<MemoryUtilization>(),
    systemMetricsTemperature: Mock<TemperatureMetrics>? = nil
  ) {
    self.init()
    _setEntity(systemMetricsCpu, for: \.systemMetricsCpu)
    _setEntity(systemMetricsMemory, for: \.systemMetricsMemory)
    _setEntity(systemMetricsTemperature, for: \.systemMetricsTemperature)
  }
}
