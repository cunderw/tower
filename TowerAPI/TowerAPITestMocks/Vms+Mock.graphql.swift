// @generated
// This file was automatically generated and should not be edited.

import ApolloTestSupport
@testable import TowerAPI

nonisolated public final class Vms: MockObject {
  public static let objectType: ApolloAPI.Object = TowerAPI.Objects.Vms
  public static let _mockFields = MockFields()
  public typealias MockValueCollectionType = Array<Mock<Vms>>

  public struct MockFields: Sendable {
    @Field<[VmDomain]>("domains") public var domains
    @Field<TowerAPI.PrefixedID>("id") public var id
  }
}

public extension Mock where O == Vms {
  convenience init(
    domains: [Mock<VmDomain>]? = nil,
    id: TowerAPI.PrefixedID = .defaultMockValue
  ) {
    self.init()
    _setList(domains, for: \.domains)
    _setScalar(id, for: \.id)
  }
}
