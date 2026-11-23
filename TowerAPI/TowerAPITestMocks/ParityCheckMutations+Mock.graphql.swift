// @generated
// This file was automatically generated and should not be edited.

import ApolloTestSupport
@testable import TowerAPI

nonisolated public final class ParityCheckMutations: MockObject {
  public static let objectType: ApolloAPI.Object = TowerAPI.Objects.ParityCheckMutations
  public static let _mockFields = MockFields()
  public typealias MockValueCollectionType = Array<Mock<ParityCheckMutations>>

  public struct MockFields: Sendable {
    @Field<TowerAPI.JSON>("cancel") public var cancel
    @Field<TowerAPI.JSON>("pause") public var pause
    @Field<TowerAPI.JSON>("resume") public var resume
    @Field<TowerAPI.JSON>("start") public var start
  }
}

public extension Mock where O == ParityCheckMutations {
  convenience init(
    cancel: TowerAPI.JSON = .defaultMockValue,
    pause: TowerAPI.JSON = .defaultMockValue,
    resume: TowerAPI.JSON = .defaultMockValue,
    start: TowerAPI.JSON = .defaultMockValue
  ) {
    self.init()
    _setScalar(cancel, for: \.cancel)
    _setScalar(pause, for: \.pause)
    _setScalar(resume, for: \.resume)
    _setScalar(start, for: \.start)
  }
}
