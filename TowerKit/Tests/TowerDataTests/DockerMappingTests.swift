import ApolloTestSupport
import Testing
@testable import TowerAPI
import TowerAPITestMocks
@testable import TowerData
import TowerCore

// These tests exercise `Container.init(from:)`/`ContainerPort.init(from:)`,
// the Apollo → domain mapping behind `LiveDockerRepository.containers()`. See
// `DashboardMappingTests.swift` for the canonical writeup of the Apollo
// `Mock<O>` crash this file's helpers guard against: omitting an
// entity-typed parameter of a generated `Mock<O>` and letting its declared
// default (`Mock<O>()`) fire is a reproducible runtime crash, not a compile
// error, under the active toolchain. `DockerContainer.hostConfig` (single,
// optional) and `.ports` (list) are this query's two entity-typed fields, so
// every mock built below passes both explicitly — never omitted, even when
// the value itself is `nil`/`[]`.

private func emptyInfo() -> Mock<TowerAPITestMocks.Info> {
  Mock<TowerAPITestMocks.Info>(
    cpu: Mock<TowerAPITestMocks.InfoCpu>(),
    os: Mock<TowerAPITestMocks.InfoOs>()
  )
}

private func emptyMetrics() -> Mock<TowerAPITestMocks.Metrics> {
  Mock<TowerAPITestMocks.Metrics>()
}

private func emptyVms() -> Mock<TowerAPITestMocks.Vms> {
  Mock<TowerAPITestMocks.Vms>(domains: [])
}

private func zeroCapacity() -> Mock<TowerAPITestMocks.ArrayCapacity> {
  Mock<TowerAPITestMocks.ArrayCapacity>(
    kilobytes: Mock<TowerAPITestMocks.Capacity>(free: "0", total: "0", used: "0")
  )
}

private func emptyArray() -> Mock<TowerAPITestMocks.UnraidArray> {
  Mock<TowerAPITestMocks.UnraidArray>(
    capacity: zeroCapacity(),
    parityCheckStatus: Mock<TowerAPITestMocks.ParityCheck>(status: .case(.neverRun)),
    state: .case(.started)
  )
}

/// Assembles the full `Query` mock from already-explicit pieces — only
/// `docker` varies test to test, since this query selects nothing else.
private func makeQuery(docker: Mock<TowerAPITestMocks.Docker>) -> Mock<TowerAPITestMocks.Query> {
  Mock<TowerAPITestMocks.Query>(
    array: emptyArray(), docker: docker, info: emptyInfo(), metrics: emptyMetrics(),
    shares: [], vms: emptyVms()
  )
}

/// An explicit (not defaulted) `DockerContainer` mock. `hostConfig` and
/// `ports` have no default here — every call site must decide both, per the
/// file-level comment above — while the remaining scalar fields (safe,
/// same-module Swift defaults, no Apollo cross-module default involved) get
/// sensible fallbacks a given test can override.
private func containerMock(
  autoStart: Bool = false,
  hostConfig: Mock<TowerAPITestMocks.ContainerHostConfig>?,
  iconUrl: String? = nil,
  id: TowerAPI.PrefixedID = "1",
  image: String = "library/image",
  isOrphaned: Bool = false,
  isUpdateAvailable: Bool? = nil,
  names: [String] = ["/container"],
  ports: [Mock<TowerAPITestMocks.ContainerPort>],
  projectUrl: String? = nil,
  registryUrl: String? = nil,
  state: GraphQLEnum<TowerAPI.ContainerState> = .case(.running),
  status: String = "Up 2 hours",
  supportUrl: String? = nil,
  templatePath: String? = nil,
  webUiUrl: String? = nil
) -> Mock<TowerAPITestMocks.DockerContainer> {
  Mock<TowerAPITestMocks.DockerContainer>(
    autoStart: autoStart, hostConfig: hostConfig, iconUrl: iconUrl, id: id, image: image,
    isOrphaned: isOrphaned, isUpdateAvailable: isUpdateAvailable, names: names, ports: ports,
    projectUrl: projectUrl, registryUrl: registryUrl, state: state, status: status,
    supportUrl: supportUrl, templatePath: templatePath, webUiUrl: webUiUrl
  )
}

@Test func mapsNameImageAndState() async throws {
  let mock = makeQuery(docker: Mock<TowerAPITestMocks.Docker>(containers: [
    containerMock(hostConfig: nil, image: "linuxserver/sonarr", names: ["/sonarr"], ports: [], state: .case(.paused)),
  ]))

  let data = await DockerContainersQuery.Data.from(mock)
  let container = try #require(data.docker.containers.map(Container.init(from:)).first)

  #expect(container.displayName == "sonarr")
  #expect(container.image == "linuxserver/sonarr")
  #expect(container.state == .paused)
}

@Test func isUpdateAvailableStaysNilWhenNotDetermined() async throws {
  // The not-reported-is-not-false rule applied to a `Bool`: the schema declares
  // `isUpdateAvailable` nullable, and `nil` means "not determined" — it must
  // not collapse to `false`, since `false` renders as "no update available",
  // a claim we cannot make.
  let mock = makeQuery(docker: Mock<TowerAPITestMocks.Docker>(containers: [
    containerMock(hostConfig: nil, isUpdateAvailable: nil, ports: []),
  ]))

  let data = await DockerContainersQuery.Data.from(mock)
  let container = try #require(data.docker.containers.map(Container.init(from:)).first)

  #expect(container.isUpdateAvailable == nil)
}

/// The other half: a real, determined `true` reading must still come
/// through as `true`, not get swallowed by whatever handles the `nil` case
/// above — proven independently so a regression that mapped every reading to
/// `nil` would be caught, not just the "stays nil" direction.
@Test func isUpdateAvailableStaysTrueWhenDetermined() async throws {
  let mock = makeQuery(docker: Mock<TowerAPITestMocks.Docker>(containers: [
    containerMock(hostConfig: nil, isUpdateAvailable: true, ports: []),
  ]))

  let data = await DockerContainersQuery.Data.from(mock)
  let container = try #require(data.docker.containers.map(Container.init(from:)).first)

  #expect(container.isUpdateAvailable == true)
}

@Test func mapsPortsIncludingNilPublicPort() async throws {
  let published = Mock<TowerAPITestMocks.ContainerPort>(
    ip: "0.0.0.0", privatePort: "80", publicPort: "13378", type: .case(.tcp)
  )
  // Internal-only port: Docker exposes it inside the container network but
  // never published it to the host, so `publicPort` is genuinely absent.
  let internalOnly = Mock<TowerAPITestMocks.ContainerPort>(
    ip: nil, privatePort: "9000", publicPort: nil, type: .case(.udp)
  )
  let mock = makeQuery(docker: Mock<TowerAPITestMocks.Docker>(containers: [
    containerMock(hostConfig: nil, ports: [published, internalOnly]),
  ]))

  let data = await DockerContainersQuery.Data.from(mock)
  let container = try #require(data.docker.containers.map(Container.init(from:)).first)

  #expect(container.ports.count == 2)
  let first = try #require(container.ports.first)
  #expect(first.ip == "0.0.0.0")
  #expect(first.privatePort == 80)
  #expect(first.publicPort == 13_378)
  #expect(first.type == "TCP")

  let second = try #require(container.ports.last)
  #expect(second.privatePort == 9_000)
  #expect(second.publicPort == nil)
  #expect(second.type == "UDP")
}

/// The degrading path that keeping `Port` a `String` relies on: a value
/// Tower can't read as a number costs that one half of one port row, not the
/// whole containers query. With `Port` mapped to `Int`, this response would throw
/// out of Apollo's decode step and the Docker list would render nothing at all.
@Test func anUnreadablePortDegradesToNilRatherThanFailingTheWholeQuery() async throws {
  let unreadable = Mock<TowerAPITestMocks.ContainerPort>(
    ip: "0.0.0.0", privatePort: "not a port", publicPort: "13378", type: .case(.tcp)
  )
  let mock = makeQuery(docker: Mock<TowerAPITestMocks.Docker>(containers: [
    containerMock(hostConfig: nil, image: "linuxserver/sonarr", names: ["/sonarr"], ports: [unreadable]),
  ]))

  let data = await DockerContainersQuery.Data.from(mock)
  let container = try #require(data.docker.containers.map(Container.init(from:)).first)

  // The container itself survived, which is the point.
  #expect(container.displayName == "sonarr")
  let port = try #require(container.ports.first)
  #expect(port.privatePort == nil)
  #expect(port.publicPort == 13_378)
  // And the row still renders what it does know.
  #expect(port.summary == "13378/TCP")
}

@Test func mapsEmptyNamesArrayFallingBackToImage() async throws {
  let mock = makeQuery(docker: Mock<TowerAPITestMocks.Docker>(containers: [
    containerMock(hostConfig: nil, image: "linuxserver/orphan", names: [], ports: []),
  ]))

  let data = await DockerContainersQuery.Data.from(mock)
  let container = try #require(data.docker.containers.map(Container.init(from:)).first)

  #expect(container.names.isEmpty)
  #expect(container.displayName == "linuxserver/orphan")
}

@Test func mapsNetworkModeFromHostConfig() async throws {
  let mock = makeQuery(docker: Mock<TowerAPITestMocks.Docker>(containers: [
    containerMock(
      hostConfig: Mock<TowerAPITestMocks.ContainerHostConfig>(networkMode: "bridge"),
      ports: []
    ),
  ]))

  let data = await DockerContainersQuery.Data.from(mock)
  let container = try #require(data.docker.containers.map(Container.init(from:)).first)

  #expect(container.networkMode == "bridge")
}

@Test func networkModeIsNilWhenHostConfigIsNil() async throws {
  // `hostConfig` is a nullable entity field — some containers report none —
  // and this is the one place that nullability threads through to
  // `networkMode` rather than crashing or fabricating a mode.
  let mock = makeQuery(docker: Mock<TowerAPITestMocks.Docker>(containers: [
    containerMock(hostConfig: nil, ports: []),
  ]))

  let data = await DockerContainersQuery.Data.from(mock)
  let container = try #require(data.docker.containers.map(Container.init(from:)).first)

  #expect(container.networkMode == nil)
}

// MARK: - Container links must be openable

@Test func aSchemelessContainerURLBecomesNoLinkRatherThanADeadOne() async throws {
  // Four of these render as `Link`s on the container row and detail screen. A
  // scheme-less address parses into a URL that `Link` cannot open and `openURL`
  // ignores without reporting anything — a link that does nothing when tapped.
  // A homelab container template with a malformed `WebUI` is exactly how this
  // arrives.
  let mock = makeQuery(docker: Mock<TowerAPITestMocks.Docker>(containers: [
    containerMock(
      hostConfig: nil, iconUrl: "cdn.example.invalid/icon.png", ports: [],
      projectUrl: "github.com/example/project", registryUrl: "hub.docker.com/r/example",
      // Host-and-path, not "192.0.2.10:8080" — that one fails `URL(string:)`
      // outright (a scheme cannot start with a digit), so it would be nil with
      // or without `OpenableURL` and the assertion below would prove nothing.
      supportUrl: "forums.example.invalid/thread", webUiUrl: "nas.example.invalid/webui"),
  ]))

  let data = await DockerContainersQuery.Data.from(mock)
  let container = try #require(data.docker.containers.map(Container.init(from:)).first)

  #expect(container.webUiURL == nil)
  #expect(container.iconURL == nil)
  #expect(container.projectURL == nil)
  #expect(container.supportURL == nil)
  #expect(container.registryURL == nil)
}

@Test func absoluteContainerURLsSurviveUnchanged() async throws {
  let mock = makeQuery(docker: Mock<TowerAPITestMocks.Docker>(containers: [
    containerMock(
      hostConfig: nil, iconUrl: "https://cdn.example.invalid/icon.png", ports: [],
      projectUrl: "https://github.com/example/project",
      registryUrl: "https://hub.docker.com/r/example",
      supportUrl: "https://forums.example.invalid/thread",
      webUiUrl: "http://192.0.2.10:8080/"),
  ]))

  let data = await DockerContainersQuery.Data.from(mock)
  let container = try #require(data.docker.containers.map(Container.init(from:)).first)

  // `http` as well as `https`: a container's web UI on a LAN is routinely plain
  // HTTP, and refusing it would break the most common link of the five.
  #expect(container.webUiURL?.absoluteString == "http://192.0.2.10:8080/")
  #expect(container.iconURL != nil)
  #expect(container.projectURL != nil)
  #expect(container.supportURL != nil)
  #expect(container.registryURL != nil)
}
