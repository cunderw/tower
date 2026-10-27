// @generated
// This file was automatically generated and should not be edited.

import ApolloTestSupport
@testable import TowerAPI

nonisolated public final class VmDomain: MockObject {
  public static let objectType: ApolloAPI.Object = TowerAPI.Objects.VmDomain
  public static let _mockFields = MockFields()
  public typealias MockValueCollectionType = Array<Mock<VmDomain>>

  public struct MockFields: Sendable {
    @Field<TowerAPI.PrefixedID>("id") public var id
    @Field<String>("name") public var name
    @Field<GraphQLEnum<TowerAPI.VmState>>("state") public var state
  }
}

public extension Mock where O == VmDomain {
  convenience init(
    id: TowerAPI.PrefixedID = .defaultMockValue,
    name: String? = nil,
    state: GraphQLEnum<TowerAPI.VmState> = .case(.nostate)
  ) {
    self.init()
    _setScalar(id, for: \.id)
    _setScalar(name, for: \.name)
    _setScalar(state, for: \.state)
  }
}
