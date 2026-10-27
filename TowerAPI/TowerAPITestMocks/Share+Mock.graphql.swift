// @generated
// This file was automatically generated and should not be edited.

import ApolloTestSupport
@testable import TowerAPI

nonisolated public final class Share: MockObject {
  public static let objectType: ApolloAPI.Object = TowerAPI.Objects.Share
  public static let _mockFields = MockFields()
  public typealias MockValueCollectionType = Array<Mock<Share>>

  public struct MockFields: Sendable {
    @Field<String>("allocator") public var allocator
    @Field<Bool>("cache") public var cache
    @Field<String>("comment") public var comment
    @Field<String>("cow") public var cow
    @Field<[String]>("exclude") public var exclude
    @Field<String>("floor") public var floor
    @Field<TowerAPI.BigInt>("free") public var free
    @Field<TowerAPI.PrefixedID>("id") public var id
    @Field<[String]>("include") public var include
    @Field<String>("name") public var name
    @Field<String>("nameOrig") public var nameOrig
    @Field<String>("splitLevel") public var splitLevel
    @Field<TowerAPI.BigInt>("used") public var used
  }
}

public extension Mock where O == Share {
  convenience init(
    allocator: String? = nil,
    cache: Bool? = nil,
    comment: String? = nil,
    cow: String? = nil,
    exclude: [String]? = nil,
    floor: String? = nil,
    free: TowerAPI.BigInt? = nil,
    id: TowerAPI.PrefixedID = .defaultMockValue,
    include: [String]? = nil,
    name: String? = nil,
    nameOrig: String? = nil,
    splitLevel: String? = nil,
    used: TowerAPI.BigInt? = nil
  ) {
    self.init()
    _setScalar(allocator, for: \.allocator)
    _setScalar(cache, for: \.cache)
    _setScalar(comment, for: \.comment)
    _setScalar(cow, for: \.cow)
    _setScalarList(exclude, for: \.exclude)
    _setScalar(floor, for: \.floor)
    _setScalar(free, for: \.free)
    _setScalar(id, for: \.id)
    _setScalarList(include, for: \.include)
    _setScalar(name, for: \.name)
    _setScalar(nameOrig, for: \.nameOrig)
    _setScalar(splitLevel, for: \.splitLevel)
    _setScalar(used, for: \.used)
  }
}
