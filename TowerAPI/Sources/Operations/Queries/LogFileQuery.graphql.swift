// @generated
// This file was automatically generated and should not be edited.

@_exported import ApolloAPI
@_spi(Execution) @_spi(Unsafe) import ApolloAPI

nonisolated public struct LogFileQuery: GraphQLQuery {
  public static let operationName: String = "LogFile"
  public static let operationDocument: ApolloAPI.OperationDocument = .init(
    definition: .init(
      #"query LogFile($path: String!, $lines: Int) { logFile(path: $path, lines: $lines) { __typename path content totalLines startLine } }"#
    ))

  public var path: String
  public var lines: GraphQLNullable<Int32>

  public init(
    path: String,
    lines: GraphQLNullable<Int32>
  ) {
    self.path = path
    self.lines = lines
  }

  @_spi(Unsafe) public var __variables: Variables? { [
    "path": path,
    "lines": lines
  ] }

  nonisolated public struct Data: TowerAPI.SelectionSet {
    @_spi(Unsafe) public let __data: DataDict
    @_spi(Unsafe) public init(_dataDict: DataDict) { __data = _dataDict }

    @_spi(Execution) public static var __parentType: any ApolloAPI.ParentType { TowerAPI.Objects.Query }
    @_spi(Execution) public static var __selections: [ApolloAPI.Selection] { [
      .field("logFile", LogFile.self, arguments: [
        "path": .variable("path"),
        "lines": .variable("lines")
      ]),
    ] }
    @_spi(Execution) public static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
      LogFileQuery.Data.self
    ] }

    /// #### Required Permissions:
    ///
    /// - Action: **READ_ANY**
    /// - Resource: **LOGS**
    public var logFile: LogFile { __data["logFile"] }

    /// LogFile
    ///
    /// Parent Type: `LogFileContent`
    nonisolated public struct LogFile: TowerAPI.SelectionSet {
      @_spi(Unsafe) public let __data: DataDict
      @_spi(Unsafe) public init(_dataDict: DataDict) { __data = _dataDict }

      @_spi(Execution) public static var __parentType: any ApolloAPI.ParentType { TowerAPI.Objects.LogFileContent }
      @_spi(Execution) public static var __selections: [ApolloAPI.Selection] { [
        .field("__typename", String.self),
        .field("path", String.self),
        .field("content", String.self),
        .field("totalLines", Int.self),
        .field("startLine", Int?.self),
      ] }
      @_spi(Execution) public static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
        LogFileQuery.Data.LogFile.self
      ] }

      /// Path to the log file
      public var path: String { __data["path"] }
      /// Content of the log file
      public var content: String { __data["content"] }
      /// Total number of lines in the file
      public var totalLines: Int { __data["totalLines"] }
      /// Starting line number of the content (1-indexed)
      public var startLine: Int? { __data["startLine"] }
    }
  }
}
