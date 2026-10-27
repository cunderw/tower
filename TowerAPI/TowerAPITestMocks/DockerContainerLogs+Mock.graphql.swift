// @generated
// This file was automatically generated and should not be edited.

import ApolloTestSupport
@testable import TowerAPI

nonisolated public final class DockerContainerLogs: MockObject {
  public static let objectType: ApolloAPI.Object = TowerAPI.Objects.DockerContainerLogs
  public static let _mockFields = MockFields()
  public typealias MockValueCollectionType = Array<Mock<DockerContainerLogs>>

  public struct MockFields: Sendable {
    @Field<TowerAPI.PrefixedID>("containerId") public var containerId
    @Field<TowerAPI.DateTime>("cursor") public var cursor
    @Field<[DockerContainerLogLine]>("lines") public var lines
  }
}

public extension Mock where O == DockerContainerLogs {
  convenience init(
    containerId: TowerAPI.PrefixedID = .defaultMockValue,
    cursor: TowerAPI.DateTime? = nil,
    lines: [Mock<DockerContainerLogLine>] = []
  ) {
    self.init()
    _setScalar(containerId, for: \.containerId)
    _setScalar(cursor, for: \.cursor)
    _setList(lines, for: \.lines)
  }
}
