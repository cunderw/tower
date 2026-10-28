// @generated
// This file was automatically generated and should not be edited.

@_exported import ApolloAPI
@_spi(Execution) @_spi(Unsafe) import ApolloAPI

nonisolated public struct DashboardContainersQuery: GraphQLQuery {
  public static let operationName: String = "DashboardContainers"
  public static let operationDocument: ApolloAPI.OperationDocument = .init(
    definition: .init(
      #"query DashboardContainers { docker { __typename containers { __typename id state } } }"#
    ))

  public init() {}

  nonisolated public struct Data: TowerAPI.SelectionSet {
    @_spi(Unsafe) public let __data: DataDict
    @_spi(Unsafe) public init(_dataDict: DataDict) { __data = _dataDict }

    @_spi(Execution) public static var __parentType: any ApolloAPI.ParentType { TowerAPI.Objects.Query }
    @_spi(Execution) public static var __selections: [ApolloAPI.Selection] { [
      .field("docker", Docker.self),
    ] }
    @_spi(Execution) public static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
      DashboardContainersQuery.Data.self
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
        .field("containers", [Container].self),
      ] }
      @_spi(Execution) public static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
        DashboardContainersQuery.Data.Docker.self
      ] }

      /// #### Required Permissions:
      ///
      /// - Action: **READ_ANY**
      /// - Resource: **DOCKER**
      public var containers: [Container] { __data["containers"] }

      /// Docker.Container
      ///
      /// Parent Type: `DockerContainer`
      nonisolated public struct Container: TowerAPI.SelectionSet {
        @_spi(Unsafe) public let __data: DataDict
        @_spi(Unsafe) public init(_dataDict: DataDict) { __data = _dataDict }

        @_spi(Execution) public static var __parentType: any ApolloAPI.ParentType { TowerAPI.Objects.DockerContainer }
        @_spi(Execution) public static var __selections: [ApolloAPI.Selection] { [
          .field("__typename", String.self),
          .field("id", TowerAPI.PrefixedID.self),
          .field("state", GraphQLEnum<TowerAPI.ContainerState>.self),
        ] }
        @_spi(Execution) public static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
          DashboardContainersQuery.Data.Docker.Container.self
        ] }

        public var id: TowerAPI.PrefixedID { __data["id"] }
        public var state: GraphQLEnum<TowerAPI.ContainerState> { __data["state"] }
      }
    }
  }
}
