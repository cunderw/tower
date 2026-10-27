// @generated
// This file was automatically generated and should not be edited.

import ApolloTestSupport
@testable import TowerAPI

nonisolated public final class ContainerHostConfig: MockObject {
  public static let objectType: ApolloAPI.Object = TowerAPI.Objects.ContainerHostConfig
  public static let _mockFields = MockFields()
  public typealias MockValueCollectionType = Array<Mock<ContainerHostConfig>>

  public struct MockFields: Sendable {
    @Field<String>("networkMode") public var networkMode
  }
}

public extension Mock where O == ContainerHostConfig {
  convenience init(
    networkMode: String = ""
  ) {
    self.init()
    _setScalar(networkMode, for: \.networkMode)
  }
}
