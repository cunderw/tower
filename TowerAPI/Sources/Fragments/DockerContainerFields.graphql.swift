// @generated
// This file was automatically generated and should not be edited.

@_exported import ApolloAPI
@_spi(Execution) @_spi(Unsafe) import ApolloAPI

nonisolated public struct DockerContainerFields: TowerAPI.SelectionSet, Fragment {
  public static var fragmentDefinition: StaticString {
    #"fragment DockerContainerFields on DockerContainer { __typename id names image state status autoStart isUpdateAvailable isOrphaned webUiUrl iconUrl projectUrl supportUrl registryUrl templatePath hostConfig { __typename networkMode } ports { __typename ip privatePort publicPort type } }"#
  }

  @_spi(Unsafe) public let __data: DataDict
  @_spi(Unsafe) public init(_dataDict: DataDict) { __data = _dataDict }

  @_spi(Execution) public static var __parentType: any ApolloAPI.ParentType { TowerAPI.Objects.DockerContainer }
  @_spi(Execution) public static var __selections: [ApolloAPI.Selection] { [
    .field("__typename", String.self),
    .field("id", TowerAPI.PrefixedID.self),
    .field("names", [String].self),
    .field("image", String.self),
    .field("state", GraphQLEnum<TowerAPI.ContainerState>.self),
    .field("status", String.self),
    .field("autoStart", Bool.self),
    .field("isUpdateAvailable", Bool?.self),
    .field("isOrphaned", Bool.self),
    .field("webUiUrl", String?.self),
    .field("iconUrl", String?.self),
    .field("projectUrl", String?.self),
    .field("supportUrl", String?.self),
    .field("registryUrl", String?.self),
    .field("templatePath", String?.self),
    .field("hostConfig", HostConfig?.self),
    .field("ports", [Port].self),
  ] }
  @_spi(Execution) public static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
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

  /// HostConfig
  ///
  /// Parent Type: `ContainerHostConfig`
  nonisolated public struct HostConfig: TowerAPI.SelectionSet {
    @_spi(Unsafe) public let __data: DataDict
    @_spi(Unsafe) public init(_dataDict: DataDict) { __data = _dataDict }

    @_spi(Execution) public static var __parentType: any ApolloAPI.ParentType { TowerAPI.Objects.ContainerHostConfig }
    @_spi(Execution) public static var __selections: [ApolloAPI.Selection] { [
      .field("__typename", String.self),
      .field("networkMode", String.self),
    ] }
    @_spi(Execution) public static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
      DockerContainerFields.HostConfig.self
    ] }

    public var networkMode: String { __data["networkMode"] }
  }

  /// Port
  ///
  /// Parent Type: `ContainerPort`
  nonisolated public struct Port: TowerAPI.SelectionSet {
    @_spi(Unsafe) public let __data: DataDict
    @_spi(Unsafe) public init(_dataDict: DataDict) { __data = _dataDict }

    @_spi(Execution) public static var __parentType: any ApolloAPI.ParentType { TowerAPI.Objects.ContainerPort }
    @_spi(Execution) public static var __selections: [ApolloAPI.Selection] { [
      .field("__typename", String.self),
      .field("ip", String?.self),
      .field("privatePort", TowerAPI.Port?.self),
      .field("publicPort", TowerAPI.Port?.self),
      .field("type", GraphQLEnum<TowerAPI.ContainerPortType>.self),
    ] }
    @_spi(Execution) public static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
      DockerContainerFields.Port.self
    ] }

    public var ip: String? { __data["ip"] }
    public var privatePort: TowerAPI.Port? { __data["privatePort"] }
    public var publicPort: TowerAPI.Port? { __data["publicPort"] }
    public var type: GraphQLEnum<TowerAPI.ContainerPortType> { __data["type"] }
  }
}
