// @generated
// This file was automatically generated and should not be edited.

import ApolloTestSupport
@testable import TowerAPI

nonisolated public final class LogFile: MockObject {
  public static let objectType: ApolloAPI.Object = TowerAPI.Objects.LogFile
  public static let _mockFields = MockFields()
  public typealias MockValueCollectionType = Array<Mock<LogFile>>

  public struct MockFields: Sendable {
    @Field<TowerAPI.DateTime>("modifiedAt") public var modifiedAt
    @Field<String>("name") public var name
    @Field<String>("path") public var path
    @Field<Int>("size") public var size
  }
}

public extension Mock where O == LogFile {
  convenience init(
    modifiedAt: TowerAPI.DateTime = .defaultMockValue,
    name: String = "",
    path: String = "",
    size: Int = 0
  ) {
    self.init()
    _setScalar(modifiedAt, for: \.modifiedAt)
    _setScalar(name, for: \.name)
    _setScalar(path, for: \.path)
    _setScalar(size, for: \.size)
  }
}
