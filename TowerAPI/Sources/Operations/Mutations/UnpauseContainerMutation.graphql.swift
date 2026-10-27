// @generated
// This file was automatically generated and should not be edited.

@_exported import ApolloAPI
@_spi(Execution) @_spi(Unsafe) import ApolloAPI

nonisolated public struct UnpauseContainerMutation: GraphQLMutation {
  public static let operationName: String = "UnpauseContainer"
  public static let operationDocument: ApolloAPI.OperationDocument = .init(
    definition: .init(
      #"mutation UnpauseContainer($id: PrefixedID!) { docker { __typename unpause(id: $id) { __typename id state status } } }"#
    ))

  public var id: PrefixedID

  public init(id: PrefixedID) {
    self.id = id
  }

  @_spi(Unsafe) public var __variables: Variables? { ["id": id] }

  nonisolated public struct Data: TowerAPI.SelectionSet {
    @_spi(Unsafe) public let __data: DataDict
    @_spi(Unsafe) public init(_dataDict: DataDict) { __data = _dataDict }

    @_spi(Execution) public static var __parentType: any ApolloAPI.ParentType { TowerAPI.Objects.Mutation }
    @_spi(Execution) public static var __selections: [ApolloAPI.Selection] { [
      .field("docker", Docker.self),
    ] }
    @_spi(Execution) public static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
      UnpauseContainerMutation.Data.self
    ] }

    public var docker: Docker { __data["docker"] }

    /// Docker
    ///
    /// Parent Type: `DockerMutations`
    nonisolated public struct Docker: TowerAPI.SelectionSet {
      @_spi(Unsafe) public let __data: DataDict
      @_spi(Unsafe) public init(_dataDict: DataDict) { __data = _dataDict }

      @_spi(Execution) public static var __parentType: any ApolloAPI.ParentType { TowerAPI.Objects.DockerMutations }
      @_spi(Execution) public static var __selections: [ApolloAPI.Selection] { [
        .field("__typename", String.self),
        .field("unpause", Unpause.self, arguments: ["id": .variable("id")]),
      ] }
      @_spi(Execution) public static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
        UnpauseContainerMutation.Data.Docker.self
      ] }

      /// #### Required Permissions:
      ///
      /// - Action: **UPDATE_ANY**
      /// - Resource: **DOCKER**
      ///
      /// #### Description:
      ///
      /// Unpause (Resume) a container
      public var unpause: Unpause { __data["unpause"] }

      /// Docker.Unpause
      ///
      /// Parent Type: `DockerContainer`
      nonisolated public struct Unpause: TowerAPI.SelectionSet {
        @_spi(Unsafe) public let __data: DataDict
        @_spi(Unsafe) public init(_dataDict: DataDict) { __data = _dataDict }

        @_spi(Execution) public static var __parentType: any ApolloAPI.ParentType { TowerAPI.Objects.DockerContainer }
        @_spi(Execution) public static var __selections: [ApolloAPI.Selection] { [
          .field("__typename", String.self),
          .field("id", TowerAPI.PrefixedID.self),
          .field("state", GraphQLEnum<TowerAPI.ContainerState>.self),
          .field("status", String.self),
        ] }
        @_spi(Execution) public static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
          UnpauseContainerMutation.Data.Docker.Unpause.self
        ] }

        public var id: TowerAPI.PrefixedID { __data["id"] }
        public var state: GraphQLEnum<TowerAPI.ContainerState> { __data["state"] }
        public var status: String { __data["status"] }
      }
    }
  }
}
