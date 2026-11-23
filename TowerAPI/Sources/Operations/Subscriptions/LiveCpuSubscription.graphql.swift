// @generated
// This file was automatically generated and should not be edited.

@_exported import ApolloAPI
@_spi(Execution) @_spi(Unsafe) import ApolloAPI

nonisolated public struct LiveCpuSubscription: GraphQLSubscription {
  public static let operationName: String = "LiveCpu"
  public static let operationDocument: ApolloAPI.OperationDocument = .init(
    definition: .init(
      #"subscription LiveCpu { systemMetricsCpu { __typename percentTotal } }"#
    ))

  public init() {}

  nonisolated public struct Data: TowerAPI.SelectionSet {
    @_spi(Unsafe) public let __data: DataDict
    @_spi(Unsafe) public init(_dataDict: DataDict) { __data = _dataDict }

    @_spi(Execution) public static var __parentType: any ApolloAPI.ParentType { TowerAPI.Objects.Subscription }
    @_spi(Execution) public static var __selections: [ApolloAPI.Selection] { [
      .field("systemMetricsCpu", SystemMetricsCpu.self),
    ] }
    @_spi(Execution) public static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
      LiveCpuSubscription.Data.self
    ] }

    /// #### Required Permissions:
    ///
    /// - Action: **READ_ANY**
    /// - Resource: **INFO**
    public var systemMetricsCpu: SystemMetricsCpu { __data["systemMetricsCpu"] }

    /// SystemMetricsCpu
    ///
    /// Parent Type: `CpuUtilization`
    nonisolated public struct SystemMetricsCpu: TowerAPI.SelectionSet {
      @_spi(Unsafe) public let __data: DataDict
      @_spi(Unsafe) public init(_dataDict: DataDict) { __data = _dataDict }

      @_spi(Execution) public static var __parentType: any ApolloAPI.ParentType { TowerAPI.Objects.CpuUtilization }
      @_spi(Execution) public static var __selections: [ApolloAPI.Selection] { [
        .field("__typename", String.self),
        .field("percentTotal", Double.self),
      ] }
      @_spi(Execution) public static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
        LiveCpuSubscription.Data.SystemMetricsCpu.self
      ] }

      /// Total CPU load in percent
      public var percentTotal: Double { __data["percentTotal"] }
    }
  }
}
