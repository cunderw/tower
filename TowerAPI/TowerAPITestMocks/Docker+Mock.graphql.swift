// @generated
// This file was automatically generated and should not be edited.

import ApolloTestSupport
@testable import TowerAPI

nonisolated public final class Docker: MockObject {
  public static let objectType: ApolloAPI.Object = TowerAPI.Objects.Docker
  public static let _mockFields = MockFields()
  public typealias MockValueCollectionType = Array<Mock<Docker>>

  public struct MockFields: Sendable {
    @Field<[DockerContainer]>("containers") public var containers
    @Field<DockerContainerLogs>("logs") public var logs
  }
}

public extension Mock where O == Docker {
  convenience init(
    containers: [Mock<DockerContainer>] = [],
    logs: Mock<DockerContainerLogs> = Mock<DockerContainerLogs>()
  ) {
    self.init()
    _setList(containers, for: \.containers)
    _setEntity(logs, for: \.logs)
  }
}
