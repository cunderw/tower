// @generated
// This file was automatically generated and should not be edited.

import ApolloTestSupport
@testable import TowerAPI

nonisolated public final class Metrics: MockObject {
  public static let objectType: ApolloAPI.Object = TowerAPI.Objects.Metrics
  public static let _mockFields = MockFields()
  public typealias MockValueCollectionType = Array<Mock<Metrics>>

  public struct MockFields: Sendable {
    @Field<CpuUtilization>("cpu") public var cpu
    @Field<MemoryUtilization>("memory") public var memory
  }
}

public extension Mock where O == Metrics {
  convenience init(
    cpu: Mock<CpuUtilization>? = nil,
    memory: Mock<MemoryUtilization>? = nil
  ) {
    self.init()
    _setEntity(cpu, for: \.cpu)
    _setEntity(memory, for: \.memory)
  }
}
