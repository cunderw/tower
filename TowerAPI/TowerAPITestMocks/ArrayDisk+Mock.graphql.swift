// @generated
// This file was automatically generated and should not be edited.

import ApolloTestSupport
@testable import TowerAPI

nonisolated public final class ArrayDisk: MockObject {
  public static let objectType: ApolloAPI.Object = TowerAPI.Objects.ArrayDisk
  public static let _mockFields = MockFields()
  public typealias MockValueCollectionType = Array<Mock<ArrayDisk>>

  public struct MockFields: Sendable {
    @Field<String>("device") public var device
    @Field<TowerAPI.BigInt>("fsFree") public var fsFree
    @Field<TowerAPI.BigInt>("fsSize") public var fsSize
    @Field<String>("fsType") public var fsType
    @Field<TowerAPI.BigInt>("fsUsed") public var fsUsed
    @Field<TowerAPI.PrefixedID>("id") public var id
    @Field<Int>("idx") public var idx
    @Field<String>("name") public var name
    @Field<TowerAPI.BigInt>("numErrors") public var numErrors
    @Field<TowerAPI.BigInt>("numReads") public var numReads
    @Field<TowerAPI.BigInt>("numWrites") public var numWrites
    @Field<Bool>("rotational") public var rotational
    @Field<TowerAPI.BigInt>("size") public var size
    @Field<GraphQLEnum<TowerAPI.ArrayDiskStatus>>("status") public var status
    @Field<Int>("temp") public var temp
    @Field<GraphQLEnum<TowerAPI.ArrayDiskType>>("type") public var type
  }
}

public extension Mock where O == ArrayDisk {
  convenience init(
    device: String? = nil,
    fsFree: TowerAPI.BigInt? = nil,
    fsSize: TowerAPI.BigInt? = nil,
    fsType: String? = nil,
    fsUsed: TowerAPI.BigInt? = nil,
    id: TowerAPI.PrefixedID = .defaultMockValue,
    idx: Int = 0,
    name: String? = nil,
    numErrors: TowerAPI.BigInt? = nil,
    numReads: TowerAPI.BigInt? = nil,
    numWrites: TowerAPI.BigInt? = nil,
    rotational: Bool? = nil,
    size: TowerAPI.BigInt? = nil,
    status: GraphQLEnum<TowerAPI.ArrayDiskStatus>? = nil,
    temp: Int? = nil,
    type: GraphQLEnum<TowerAPI.ArrayDiskType> = .case(.data)
  ) {
    self.init()
    _setScalar(device, for: \.device)
    _setScalar(fsFree, for: \.fsFree)
    _setScalar(fsSize, for: \.fsSize)
    _setScalar(fsType, for: \.fsType)
    _setScalar(fsUsed, for: \.fsUsed)
    _setScalar(id, for: \.id)
    _setScalar(idx, for: \.idx)
    _setScalar(name, for: \.name)
    _setScalar(numErrors, for: \.numErrors)
    _setScalar(numReads, for: \.numReads)
    _setScalar(numWrites, for: \.numWrites)
    _setScalar(rotational, for: \.rotational)
    _setScalar(size, for: \.size)
    _setScalar(status, for: \.status)
    _setScalar(temp, for: \.temp)
    _setScalar(type, for: \.type)
  }
}
