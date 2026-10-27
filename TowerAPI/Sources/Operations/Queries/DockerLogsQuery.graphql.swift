// @generated
// This file was automatically generated and should not be edited.

@_exported import ApolloAPI
@_spi(Execution) @_spi(Unsafe) import ApolloAPI

nonisolated public struct DockerLogsQuery: GraphQLQuery {
  public static let operationName: String = "DockerLogs"
  public static let operationDocument: ApolloAPI.OperationDocument = .init(
    definition: .init(
      #"query DockerLogs($id: PrefixedID!, $tail: Int, $since: DateTime) { docker { __typename logs(id: $id, tail: $tail, since: $since) { __typename containerId cursor lines { __typename timestamp message } } } }"#
    ))

  public var id: PrefixedID
  public var tail: GraphQLNullable<Int32>
  public var since: GraphQLNullable<DateTime>

  public init(
    id: PrefixedID,
    tail: GraphQLNullable<Int32>,
    since: GraphQLNullable<DateTime>
  ) {
    self.id = id
    self.tail = tail
    self.since = since
  }

  @_spi(Unsafe) public var __variables: Variables? { [
    "id": id,
    "tail": tail,
    "since": since
  ] }

  nonisolated public struct Data: TowerAPI.SelectionSet {
    @_spi(Unsafe) public let __data: DataDict
    @_spi(Unsafe) public init(_dataDict: DataDict) { __data = _dataDict }

    @_spi(Execution) public static var __parentType: any ApolloAPI.ParentType { TowerAPI.Objects.Query }
    @_spi(Execution) public static var __selections: [ApolloAPI.Selection] { [
      .field("docker", Docker.self),
    ] }
    @_spi(Execution) public static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
      DockerLogsQuery.Data.self
    ] }

    /// #### Required Permissions:
    ///
    /// - Action: **READ_ANY**
    /// - Resource: **DOCKER**
    public var docker: Docker { __data["docker"] }

    /// Docker
    ///
    /// Parent Type: `Docker`
    nonisolated public struct Docker: TowerAPI.SelectionSet {
      @_spi(Unsafe) public let __data: DataDict
      @_spi(Unsafe) public init(_dataDict: DataDict) { __data = _dataDict }

      @_spi(Execution) public static var __parentType: any ApolloAPI.ParentType { TowerAPI.Objects.Docker }
      @_spi(Execution) public static var __selections: [ApolloAPI.Selection] { [
        .field("__typename", String.self),
        .field("logs", Logs.self, arguments: [
          "id": .variable("id"),
          "tail": .variable("tail"),
          "since": .variable("since")
        ]),
      ] }
      @_spi(Execution) public static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
        DockerLogsQuery.Data.Docker.self
      ] }

      /// #### Required Permissions:
      ///
      /// - Action: **READ_ANY**
      /// - Resource: **DOCKER**
      ///
      /// #### Description:
      ///
      /// Access container logs. Requires specifying a target container id through resolver arguments.
      public var logs: Logs { __data["logs"] }

      /// Docker.Logs
      ///
      /// Parent Type: `DockerContainerLogs`
      nonisolated public struct Logs: TowerAPI.SelectionSet {
        @_spi(Unsafe) public let __data: DataDict
        @_spi(Unsafe) public init(_dataDict: DataDict) { __data = _dataDict }

        @_spi(Execution) public static var __parentType: any ApolloAPI.ParentType { TowerAPI.Objects.DockerContainerLogs }
        @_spi(Execution) public static var __selections: [ApolloAPI.Selection] { [
          .field("__typename", String.self),
          .field("containerId", TowerAPI.PrefixedID.self),
          .field("cursor", TowerAPI.DateTime?.self),
          .field("lines", [Line].self),
        ] }
        @_spi(Execution) public static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
          DockerLogsQuery.Data.Docker.Logs.self
        ] }

        public var containerId: TowerAPI.PrefixedID { __data["containerId"] }
        /// Cursor that can be passed back through the since argument to continue streaming logs.
        public var cursor: TowerAPI.DateTime? { __data["cursor"] }
        public var lines: [Line] { __data["lines"] }

        /// Docker.Logs.Line
        ///
        /// Parent Type: `DockerContainerLogLine`
        nonisolated public struct Line: TowerAPI.SelectionSet {
          @_spi(Unsafe) public let __data: DataDict
          @_spi(Unsafe) public init(_dataDict: DataDict) { __data = _dataDict }

          @_spi(Execution) public static var __parentType: any ApolloAPI.ParentType { TowerAPI.Objects.DockerContainerLogLine }
          @_spi(Execution) public static var __selections: [ApolloAPI.Selection] { [
            .field("__typename", String.self),
            .field("timestamp", TowerAPI.DateTime.self),
            .field("message", String.self),
          ] }
          @_spi(Execution) public static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
            DockerLogsQuery.Data.Docker.Logs.Line.self
          ] }

          public var timestamp: TowerAPI.DateTime { __data["timestamp"] }
          public var message: String { __data["message"] }
        }
      }
    }
  }
}
