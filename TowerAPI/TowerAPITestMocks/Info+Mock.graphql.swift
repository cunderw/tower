// @generated
// This file was automatically generated and should not be edited.

import ApolloTestSupport
@testable import TowerAPI

nonisolated public final class Info: MockObject {
  public static let objectType: ApolloAPI.Object = TowerAPI.Objects.Info
  public static let _mockFields = MockFields()
  public typealias MockValueCollectionType = Array<Mock<Info>>

  public struct MockFields: Sendable {
    @Field<InfoCpu>("cpu") public var cpu
    @Field<InfoOs>("os") public var os
  }
}

public extension Mock where O == Info {
  convenience init(
    cpu: Mock<InfoCpu> = Mock<InfoCpu>(),
    os: Mock<InfoOs> = Mock<InfoOs>()
  ) {
    self.init()
    _setEntity(cpu, for: \.cpu)
    _setEntity(os, for: \.os)
  }
}
