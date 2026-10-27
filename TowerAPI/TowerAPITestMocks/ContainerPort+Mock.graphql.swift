// @generated
// This file was automatically generated and should not be edited.

import ApolloTestSupport
@testable import TowerAPI

nonisolated public final class ContainerPort: MockObject {
  public static let objectType: ApolloAPI.Object = TowerAPI.Objects.ContainerPort
  public static let _mockFields = MockFields()
  public typealias MockValueCollectionType = Array<Mock<ContainerPort>>

  public struct MockFields: Sendable {
    @Field<String>("ip") public var ip
    @Field<TowerAPI.Port>("privatePort") public var privatePort
    @Field<TowerAPI.Port>("publicPort") public var publicPort
    @Field<GraphQLEnum<TowerAPI.ContainerPortType>>("type") public var type
  }
}

public extension Mock where O == ContainerPort {
  convenience init(
    ip: String? = nil,
    privatePort: TowerAPI.Port? = nil,
    publicPort: TowerAPI.Port? = nil,
    type: GraphQLEnum<TowerAPI.ContainerPortType> = .case(.tcp)
  ) {
    self.init()
    _setScalar(ip, for: \.ip)
    _setScalar(privatePort, for: \.privatePort)
    _setScalar(publicPort, for: \.publicPort)
    _setScalar(type, for: \.type)
  }
}
