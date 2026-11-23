// @generated
// This file was automatically generated and should not be edited.

@_exported import ApolloAPI
@_spi(Execution) @_spi(Unsafe) import ApolloAPI

nonisolated public struct UpdateContainerMutation: GraphQLMutation {
  public static let operationName: String = "UpdateContainer"
  public static let operationDocument: ApolloAPI.OperationDocument = .init(
    definition: .init(
      #"mutation UpdateContainer($id: PrefixedID!) { docker { __typename updateContainer(id: $id) { __typename ...DockerContainerFields } } }"#,
      fragments: [DockerContainerFields.self]
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
      UpdateContainerMutation.Data.self
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
        .field("updateContainer", UpdateContainer.self, arguments: ["id": .variable("id")]),
      ] }
      @_spi(Execution) public static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
        UpdateContainerMutation.Data.Docker.self
      ] }

      /// #### Required Permissions:
      ///
      /// - Action: **UPDATE_ANY**
      /// - Resource: **DOCKER**
      ///
      /// #### Description:
      ///
      /// Update a container to the latest image
      public var updateContainer: UpdateContainer { __data["updateContainer"] }

      /// Docker.UpdateContainer
      ///
      /// Parent Type: `DockerContainer`
      nonisolated public struct UpdateContainer: TowerAPI.SelectionSet {
        @_spi(Unsafe) public let __data: DataDict
        @_spi(Unsafe) public init(_dataDict: DataDict) { __data = _dataDict }

        @_spi(Execution) public static var __parentType: any ApolloAPI.ParentType { TowerAPI.Objects.DockerContainer }
        @_spi(Execution) public static var __selections: [ApolloAPI.Selection] { [
          .field("__typename", String.self),
          .fragment(DockerContainerFields.self),
        ] }
        @_spi(Execution) public static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
          UpdateContainerMutation.Data.Docker.UpdateContainer.self,
          DockerContainerFields.self
        ] }

        public var id: TowerAPI.PrefixedID { __data["id"] }
        public var names: [String] { __data["names"] }
        public var image: String { __data["image"] }
        public var state: GraphQLEnum<TowerAPI.ContainerState> { __data["state"] }
        public var status: String { __data["status"] }
        public var autoStart: Bool { __data["autoStart"] }
        /// #### Required Permissions:
        ///
        /// - Action: **READ_ANY**
        /// - Resource: **DOCKER**
        public var isUpdateAvailable: Bool? { __data["isUpdateAvailable"] }
        /// Whether the container is orphaned (no template found)
        public var isOrphaned: Bool { __data["isOrphaned"] }
        /// #### Required Permissions:
        ///
        /// - Action: **READ_ANY**
        /// - Resource: **DOCKER**
        ///
        /// #### Description:
        ///
        /// Resolved WebUI URL from template
        public var webUiUrl: String? { __data["webUiUrl"] }
        /// #### Required Permissions:
        ///
        /// - Action: **READ_ANY**
        /// - Resource: **DOCKER**
        ///
        /// #### Description:
        ///
        /// Icon URL
        public var iconUrl: String? { __data["iconUrl"] }
        /// #### Required Permissions:
        ///
        /// - Action: **READ_ANY**
        /// - Resource: **DOCKER**
        ///
        /// #### Description:
        ///
        /// Project/Product homepage URL
        public var projectUrl: String? { __data["projectUrl"] }
        /// #### Required Permissions:
        ///
        /// - Action: **READ_ANY**
        /// - Resource: **DOCKER**
        ///
        /// #### Description:
        ///
        /// Support page/thread URL
        public var supportUrl: String? { __data["supportUrl"] }
        /// #### Required Permissions:
        ///
        /// - Action: **READ_ANY**
        /// - Resource: **DOCKER**
        ///
        /// #### Description:
        ///
        /// Registry/Docker Hub URL
        public var registryUrl: String? { __data["registryUrl"] }
        public var templatePath: String? { __data["templatePath"] }
        public var hostConfig: HostConfig? { __data["hostConfig"] }
        public var ports: [Port] { __data["ports"] }

        public struct Fragments: FragmentContainer {
          @_spi(Unsafe) public let __data: DataDict
          @_spi(Unsafe) public init(_dataDict: DataDict) { __data = _dataDict }

          public var dockerContainerFields: DockerContainerFields { _toFragment() }
        }

        public typealias HostConfig = DockerContainerFields.HostConfig

        public typealias Port = DockerContainerFields.Port
      }
    }
  }
}
