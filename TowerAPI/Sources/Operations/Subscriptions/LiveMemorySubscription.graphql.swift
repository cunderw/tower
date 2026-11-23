// @generated
// This file was automatically generated and should not be edited.

@_exported import ApolloAPI
@_spi(Execution) @_spi(Unsafe) import ApolloAPI

nonisolated public struct LiveMemorySubscription: GraphQLSubscription {
  public static let operationName: String = "LiveMemory"
  public static let operationDocument: ApolloAPI.OperationDocument = .init(
    definition: .init(
      #"subscription LiveMemory { systemMetricsMemory { __typename percentTotal used total } }"#
    ))

  public init() {}

  nonisolated public struct Data: TowerAPI.SelectionSet {
    @_spi(Unsafe) public let __data: DataDict
    @_spi(Unsafe) public init(_dataDict: DataDict) { __data = _dataDict }

    @_spi(Execution) public static var __parentType: any ApolloAPI.ParentType { TowerAPI.Objects.Subscription }
    @_spi(Execution) public static var __selections: [ApolloAPI.Selection] { [
      .field("systemMetricsMemory", SystemMetricsMemory.self),
    ] }
    @_spi(Execution) public static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
      LiveMemorySubscription.Data.self
    ] }

    /// #### Required Permissions:
    ///
    /// - Action: **READ_ANY**
    /// - Resource: **INFO**
    public var systemMetricsMemory: SystemMetricsMemory { __data["systemMetricsMemory"] }

    /// SystemMetricsMemory
    ///
    /// Parent Type: `MemoryUtilization`
    nonisolated public struct SystemMetricsMemory: TowerAPI.SelectionSet {
      @_spi(Unsafe) public let __data: DataDict
      @_spi(Unsafe) public init(_dataDict: DataDict) { __data = _dataDict }

      @_spi(Execution) public static var __parentType: any ApolloAPI.ParentType { TowerAPI.Objects.MemoryUtilization }
      @_spi(Execution) public static var __selections: [ApolloAPI.Selection] { [
        .field("__typename", String.self),
        .field("percentTotal", Double.self),
        .field("used", TowerAPI.BigInt.self),
        .field("total", TowerAPI.BigInt.self),
      ] }
      @_spi(Execution) public static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
        LiveMemorySubscription.Data.SystemMetricsMemory.self
      ] }

      /// Memory usage percentage
      public var percentTotal: Double { __data["percentTotal"] }
      /// Used memory in bytes
      public var used: TowerAPI.BigInt { __data["used"] }
      /// Total system memory in bytes
      public var total: TowerAPI.BigInt { __data["total"] }
    }
  }
}
