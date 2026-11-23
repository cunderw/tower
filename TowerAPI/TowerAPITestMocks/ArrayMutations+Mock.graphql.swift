// @generated
// This file was automatically generated and should not be edited.

import ApolloTestSupport
@testable import TowerAPI

nonisolated public final class ArrayMutations: MockObject {
  public static let objectType: ApolloAPI.Object = TowerAPI.Objects.ArrayMutations
  public static let _mockFields = MockFields()
  public typealias MockValueCollectionType = Array<Mock<ArrayMutations>>

  public struct MockFields: Sendable {
    @Field<UnraidArray>("setState") public var setState
  }
}

public extension Mock where O == ArrayMutations {
  convenience init(
    setState: Mock<UnraidArray> = Mock<UnraidArray>()
  ) {
    self.init()
    _setEntity(setState, for: \.setState)
  }
}
