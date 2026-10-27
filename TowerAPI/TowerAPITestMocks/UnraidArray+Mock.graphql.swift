// @generated
// This file was automatically generated and should not be edited.

import ApolloTestSupport
@testable import TowerAPI

nonisolated public final class UnraidArray: MockObject {
  public static let objectType: ApolloAPI.Object = TowerAPI.Objects.UnraidArray
  public static let _mockFields = MockFields()
  public typealias MockValueCollectionType = Array<Mock<UnraidArray>>

  public struct MockFields: Sendable {
    @Field<[ArrayDisk]>("caches") public var caches
    @Field<ArrayCapacity>("capacity") public var capacity
    @Field<[ArrayDisk]>("disks") public var disks
    @Field<[ArrayDisk]>("parities") public var parities
    @Field<ParityCheck>("parityCheckStatus") public var parityCheckStatus
    @Field<GraphQLEnum<TowerAPI.ArrayState>>("state") public var state
  }
}

public extension Mock where O == UnraidArray {
  convenience init(
    caches: [Mock<ArrayDisk>] = [],
    capacity: Mock<ArrayCapacity> = Mock<ArrayCapacity>(),
    disks: [Mock<ArrayDisk>] = [],
    parities: [Mock<ArrayDisk>] = [],
    parityCheckStatus: Mock<ParityCheck> = Mock<ParityCheck>(),
    state: GraphQLEnum<TowerAPI.ArrayState> = .case(.started)
  ) {
    self.init()
    _setList(caches, for: \.caches)
    _setEntity(capacity, for: \.capacity)
    _setList(disks, for: \.disks)
    _setList(parities, for: \.parities)
    _setEntity(parityCheckStatus, for: \.parityCheckStatus)
    _setScalar(state, for: \.state)
  }
}
