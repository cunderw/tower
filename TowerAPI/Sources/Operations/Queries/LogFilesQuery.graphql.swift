// @generated
// This file was automatically generated and should not be edited.

@_exported import ApolloAPI
@_spi(Execution) @_spi(Unsafe) import ApolloAPI

nonisolated public struct LogFilesQuery: GraphQLQuery {
  public static let operationName: String = "LogFiles"
  public static let operationDocument: ApolloAPI.OperationDocument = .init(
    definition: .init(
      #"query LogFiles { logFiles { __typename name path size modifiedAt } }"#
    ))

  public init() {}

  nonisolated public struct Data: TowerAPI.SelectionSet {
    @_spi(Unsafe) public let __data: DataDict
    @_spi(Unsafe) public init(_dataDict: DataDict) { __data = _dataDict }

    @_spi(Execution) public static var __parentType: any ApolloAPI.ParentType { TowerAPI.Objects.Query }
    @_spi(Execution) public static var __selections: [ApolloAPI.Selection] { [
      .field("logFiles", [LogFile].self),
    ] }
    @_spi(Execution) public static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
      LogFilesQuery.Data.self
    ] }

    /// #### Required Permissions:
    ///
    /// - Action: **READ_ANY**
    /// - Resource: **LOGS**
    public var logFiles: [LogFile] { __data["logFiles"] }

    /// LogFile
    ///
    /// Parent Type: `LogFile`
    nonisolated public struct LogFile: TowerAPI.SelectionSet {
      @_spi(Unsafe) public let __data: DataDict
      @_spi(Unsafe) public init(_dataDict: DataDict) { __data = _dataDict }

      @_spi(Execution) public static var __parentType: any ApolloAPI.ParentType { TowerAPI.Objects.LogFile }
      @_spi(Execution) public static var __selections: [ApolloAPI.Selection] { [
        .field("__typename", String.self),
        .field("name", String.self),
        .field("path", String.self),
        .field("size", Int.self),
        .field("modifiedAt", TowerAPI.DateTime.self),
      ] }
      @_spi(Execution) public static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
        LogFilesQuery.Data.LogFile.self
      ] }

      /// Name of the log file
      public var name: String { __data["name"] }
      /// Full path to the log file
      public var path: String { __data["path"] }
      /// Size of the log file in bytes
      public var size: Int { __data["size"] }
      /// Last modified timestamp
      public var modifiedAt: TowerAPI.DateTime { __data["modifiedAt"] }
    }
  }
}
