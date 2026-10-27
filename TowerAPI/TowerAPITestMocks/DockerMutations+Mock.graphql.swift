// @generated
// This file was automatically generated and should not be edited.

import ApolloTestSupport
@testable import TowerAPI

nonisolated public final class DockerMutations: MockObject {
  public static let objectType: ApolloAPI.Object = TowerAPI.Objects.DockerMutations
  public static let _mockFields = MockFields()
  public typealias MockValueCollectionType = Array<Mock<DockerMutations>>

  public struct MockFields: Sendable {
    @Field<DockerContainer>("pause") public var pause
    @Field<DockerContainer>("restart") public var restart
    @Field<DockerContainer>("start") public var start
    @Field<DockerContainer>("stop") public var stop
    @Field<DockerContainer>("unpause") public var unpause
  }
}

public extension Mock where O == DockerMutations {
  convenience init(
    pause: Mock<DockerContainer> = Mock<DockerContainer>(),
    restart: Mock<DockerContainer> = Mock<DockerContainer>(),
    start: Mock<DockerContainer> = Mock<DockerContainer>(),
    stop: Mock<DockerContainer> = Mock<DockerContainer>(),
    unpause: Mock<DockerContainer> = Mock<DockerContainer>()
  ) {
    self.init()
    _setEntity(pause, for: \.pause)
    _setEntity(restart, for: \.restart)
    _setEntity(start, for: \.start)
    _setEntity(stop, for: \.stop)
    _setEntity(unpause, for: \.unpause)
  }
}
