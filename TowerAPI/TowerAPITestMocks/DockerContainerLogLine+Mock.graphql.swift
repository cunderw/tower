// @generated
// This file was automatically generated and should not be edited.

import ApolloTestSupport
@testable import TowerAPI

nonisolated public final class DockerContainerLogLine: MockObject {
  public static let objectType: ApolloAPI.Object = TowerAPI.Objects.DockerContainerLogLine
  public static let _mockFields = MockFields()
  public typealias MockValueCollectionType = Array<Mock<DockerContainerLogLine>>

  public struct MockFields: Sendable {
    @Field<String>("message") public var message
    @Field<TowerAPI.DateTime>("timestamp") public var timestamp
  }
}

public extension Mock where O == DockerContainerLogLine {
  convenience init(
    message: String = "",
    timestamp: TowerAPI.DateTime = .defaultMockValue
  ) {
    self.init()
    _setScalar(message, for: \.message)
    _setScalar(timestamp, for: \.timestamp)
  }
}
