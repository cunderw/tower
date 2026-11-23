// @generated
// This file was automatically generated and should not be edited.

@_exported import ApolloAPI
@_spi(Execution) @_spi(Unsafe) import ApolloAPI

nonisolated public struct ParityHistoryQuery: GraphQLQuery {
  public static let operationName: String = "ParityHistory"
  public static let operationDocument: ApolloAPI.OperationDocument = .init(
    definition: .init(
      #"query ParityHistory { parityHistory { __typename date duration speed status errors } }"#
    ))

  public init() {}

  nonisolated public struct Data: TowerAPI.SelectionSet {
    @_spi(Unsafe) public let __data: DataDict
    @_spi(Unsafe) public init(_dataDict: DataDict) { __data = _dataDict }

    @_spi(Execution) public static var __parentType: any ApolloAPI.ParentType { TowerAPI.Objects.Query }
    @_spi(Execution) public static var __selections: [ApolloAPI.Selection] { [
      .field("parityHistory", [ParityHistory].self),
    ] }
    @_spi(Execution) public static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
      ParityHistoryQuery.Data.self
    ] }

    /// #### Required Permissions:
    ///
    /// - Action: **READ_ANY**
    /// - Resource: **ARRAY**
    public var parityHistory: [ParityHistory] { __data["parityHistory"] }

    /// ParityHistory
    ///
    /// Parent Type: `ParityCheck`
    nonisolated public struct ParityHistory: TowerAPI.SelectionSet {
      @_spi(Unsafe) public let __data: DataDict
      @_spi(Unsafe) public init(_dataDict: DataDict) { __data = _dataDict }

      @_spi(Execution) public static var __parentType: any ApolloAPI.ParentType { TowerAPI.Objects.ParityCheck }
      @_spi(Execution) public static var __selections: [ApolloAPI.Selection] { [
        .field("__typename", String.self),
        .field("date", TowerAPI.DateTime?.self),
        .field("duration", Int?.self),
        .field("speed", String?.self),
        .field("status", GraphQLEnum<TowerAPI.ParityCheckStatus>.self),
        .field("errors", Int?.self),
      ] }
      @_spi(Execution) public static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
        ParityHistoryQuery.Data.ParityHistory.self
      ] }

      /// Date of the parity check
      public var date: TowerAPI.DateTime? { __data["date"] }
      /// Duration of the parity check in seconds
      public var duration: Int? { __data["duration"] }
      /// Speed of the parity check, in MB/s
      public var speed: String? { __data["speed"] }
      /// Status of the parity check
      public var status: GraphQLEnum<TowerAPI.ParityCheckStatus> { __data["status"] }
      /// Number of errors during the parity check
      public var errors: Int? { __data["errors"] }
    }
  }
}
