// @generated
// This file was automatically generated and should not be edited.

@_exported import ApolloAPI
@_spi(Execution) @_spi(Unsafe) import ApolloAPI

nonisolated public struct DashboardVMsQuery: GraphQLQuery {
  public static let operationName: String = "DashboardVMs"
  public static let operationDocument: ApolloAPI.OperationDocument = .init(
    definition: .init(
      #"query DashboardVMs { vms { __typename domains { __typename id state } } }"#
    ))

  public init() {}

  nonisolated public struct Data: TowerAPI.SelectionSet {
    @_spi(Unsafe) public let __data: DataDict
    @_spi(Unsafe) public init(_dataDict: DataDict) { __data = _dataDict }

    @_spi(Execution) public static var __parentType: any ApolloAPI.ParentType { TowerAPI.Objects.Query }
    @_spi(Execution) public static var __selections: [ApolloAPI.Selection] { [
      .field("vms", Vms.self),
    ] }
    @_spi(Execution) public static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
      DashboardVMsQuery.Data.self
    ] }

    /// #### Required Permissions:
    ///
    /// - Action: **READ_ANY**
    /// - Resource: **VMS**
    ///
    /// #### Description:
    ///
    /// Get information about all VMs on the system
    public var vms: Vms { __data["vms"] }

    /// Vms
    ///
    /// Parent Type: `Vms`
    nonisolated public struct Vms: TowerAPI.SelectionSet {
      @_spi(Unsafe) public let __data: DataDict
      @_spi(Unsafe) public init(_dataDict: DataDict) { __data = _dataDict }

      @_spi(Execution) public static var __parentType: any ApolloAPI.ParentType { TowerAPI.Objects.Vms }
      @_spi(Execution) public static var __selections: [ApolloAPI.Selection] { [
        .field("__typename", String.self),
        .field("domains", [Domain]?.self),
      ] }
      @_spi(Execution) public static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
        DashboardVMsQuery.Data.Vms.self
      ] }

      public var domains: [Domain]? { __data["domains"] }

      /// Vms.Domain
      ///
      /// Parent Type: `VmDomain`
      nonisolated public struct Domain: TowerAPI.SelectionSet {
        @_spi(Unsafe) public let __data: DataDict
        @_spi(Unsafe) public init(_dataDict: DataDict) { __data = _dataDict }

        @_spi(Execution) public static var __parentType: any ApolloAPI.ParentType { TowerAPI.Objects.VmDomain }
        @_spi(Execution) public static var __selections: [ApolloAPI.Selection] { [
          .field("__typename", String.self),
          .field("id", TowerAPI.PrefixedID.self),
          .field("state", GraphQLEnum<TowerAPI.VmState>.self),
        ] }
        @_spi(Execution) public static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
          DashboardVMsQuery.Data.Vms.Domain.self
        ] }

        /// The unique identifier for the vm (uuid)
        public var id: TowerAPI.PrefixedID { __data["id"] }
        /// Current domain vm state
        public var state: GraphQLEnum<TowerAPI.VmState> { __data["state"] }
      }
    }
  }
}
