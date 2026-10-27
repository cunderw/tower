// @generated
// This file was automatically generated and should not be edited.

import ApolloTestSupport
@testable import TowerAPI

nonisolated public final class DockerContainer: MockObject {
  public static let objectType: ApolloAPI.Object = TowerAPI.Objects.DockerContainer
  public static let _mockFields = MockFields()
  public typealias MockValueCollectionType = Array<Mock<DockerContainer>>

  public struct MockFields: Sendable {
    @Field<Bool>("autoStart") public var autoStart
    @Field<ContainerHostConfig>("hostConfig") public var hostConfig
    @Field<String>("iconUrl") public var iconUrl
    @Field<TowerAPI.PrefixedID>("id") public var id
    @Field<String>("image") public var image
    @Field<Bool>("isOrphaned") public var isOrphaned
    @Field<Bool>("isUpdateAvailable") public var isUpdateAvailable
    @Field<[String]>("names") public var names
    @Field<[ContainerPort]>("ports") public var ports
    @Field<String>("projectUrl") public var projectUrl
    @Field<String>("registryUrl") public var registryUrl
    @Field<GraphQLEnum<TowerAPI.ContainerState>>("state") public var state
    @Field<String>("status") public var status
    @Field<String>("supportUrl") public var supportUrl
    @Field<String>("templatePath") public var templatePath
    @Field<String>("webUiUrl") public var webUiUrl
  }
}

public extension Mock where O == DockerContainer {
  convenience init(
    autoStart: Bool = false,
    hostConfig: Mock<ContainerHostConfig>? = nil,
    iconUrl: String? = nil,
    id: TowerAPI.PrefixedID = .defaultMockValue,
    image: String = "",
    isOrphaned: Bool = false,
    isUpdateAvailable: Bool? = nil,
    names: [String] = [],
    ports: [Mock<ContainerPort>] = [],
    projectUrl: String? = nil,
    registryUrl: String? = nil,
    state: GraphQLEnum<TowerAPI.ContainerState> = .case(.running),
    status: String = "",
    supportUrl: String? = nil,
    templatePath: String? = nil,
    webUiUrl: String? = nil
  ) {
    self.init()
    _setScalar(autoStart, for: \.autoStart)
    _setEntity(hostConfig, for: \.hostConfig)
    _setScalar(iconUrl, for: \.iconUrl)
    _setScalar(id, for: \.id)
    _setScalar(image, for: \.image)
    _setScalar(isOrphaned, for: \.isOrphaned)
    _setScalar(isUpdateAvailable, for: \.isUpdateAvailable)
    _setScalarList(names, for: \.names)
    _setList(ports, for: \.ports)
    _setScalar(projectUrl, for: \.projectUrl)
    _setScalar(registryUrl, for: \.registryUrl)
    _setScalar(state, for: \.state)
    _setScalar(status, for: \.status)
    _setScalar(supportUrl, for: \.supportUrl)
    _setScalar(templatePath, for: \.templatePath)
    _setScalar(webUiUrl, for: \.webUiUrl)
  }
}
