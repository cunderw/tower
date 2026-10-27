// @generated
// This file was automatically generated and should not be edited.

import ApolloTestSupport
@testable import TowerAPI

nonisolated public final class LogFileContent: MockObject {
  public static let objectType: ApolloAPI.Object = TowerAPI.Objects.LogFileContent
  public static let _mockFields = MockFields()
  public typealias MockValueCollectionType = Array<Mock<LogFileContent>>

  public struct MockFields: Sendable {
    @Field<String>("content") public var content
    @Field<String>("path") public var path
    @Field<Int>("startLine") public var startLine
    @Field<Int>("totalLines") public var totalLines
  }
}

public extension Mock where O == LogFileContent {
  convenience init(
    content: String = "",
    path: String = "",
    startLine: Int? = nil,
    totalLines: Int = 0
  ) {
    self.init()
    _setScalar(content, for: \.content)
    _setScalar(path, for: \.path)
    _setScalar(startLine, for: \.startLine)
    _setScalar(totalLines, for: \.totalLines)
  }
}
