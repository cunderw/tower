import Foundation
import Testing
@testable import TowerCore

/// Matching a configured service to the container running it, both ways.
private func makeContainer(
  id: String = "c1",
  name: String = "radarr",
  image: String = "linuxserver/radarr",
  state: ContainerState = .running,
  ports: [ContainerPort] = []
) -> Container {
  Container(
    id: id, names: ["/\(name)"], image: image, state: state, status: "Up 3 days",
    autoStart: true, isUpdateAvailable: false, isOrphaned: false,
    webUiURL: nil, iconURL: nil, projectURL: nil, supportURL: nil, registryURL: nil,
    templatePath: nil, networkMode: "bridge", ports: ports
  )
}

private func makeInstance(
  kind: ServiceKind = .radarr,
  name: String = "Radarr",
  url: String
) -> ServiceInstance {
  ServiceInstance(
    kind: kind, name: name, baseURL: URL(string: url)!, credentials: .apiKey("k"))
}

private let serverURL = URL(string: "http://192.0.2.10")!
private func port(_ publicPort: Int, private privatePort: Int) -> ContainerPort {
  ContainerPort(ip: "0.0.0.0", privatePort: privatePort, publicPort: publicPort, type: "TCP")
}

// MARK: - The match

@Test func aServiceFindsTheContainerPublishingItsPort() {
  let containers = [makeContainer(ports: [port(7878, private: 7878)])]
  let instance = makeInstance(url: "http://192.0.2.10:7878")

  let match = ServiceContainerLink.container(
    for: instance, in: containers, serverURL: serverURL)

  #expect(match?.id == "c1")
}

@Test func aContainerFindsTheServiceConfiguredAgainstIt() {
  let container = makeContainer(ports: [port(7878, private: 7878)])
  let instances = [makeInstance(name: "Radarr", url: "http://192.0.2.10:7878")]

  let match = ServiceContainerLink.instance(
    for: container, in: instances, serverURL: serverURL)

  #expect(match?.name == "Radarr")
}

@Test func twoInstancesOfOneKindEachLinkToTheirOwnContainer() {
  // The case that makes kind-alone matching wrong, and it is the standard
  // setup: a 4K Radarr alongside a regular one.
  let containers = [
    makeContainer(id: "std", name: "radarr", ports: [port(7878, private: 7878)]),
    makeContainer(id: "uhd", name: "radarr-4k", ports: [port(7879, private: 7878)]),
  ]
  let standard = makeInstance(name: "Radarr", url: "http://192.0.2.10:7878")
  let uhd = makeInstance(name: "Radarr 4K", url: "http://192.0.2.10:7879")

  #expect(
    ServiceContainerLink.container(for: standard, in: containers, serverURL: serverURL)?.id
      == "std")
  #expect(
    ServiceContainerLink.container(for: uhd, in: containers, serverURL: serverURL)?.id == "uhd")
}

@Test func theKindMustAgreeEvenWhenTheAddressDoes() {
  // A Sonarr configured on the port a Radarr container publishes is a
  // misconfiguration, not a match — linking them would put Restart next to the
  // wrong service.
  let containers = [makeContainer(image: "linuxserver/radarr", ports: [port(7878, private: 7878)])]
  let sonarr = makeInstance(kind: .sonarr, name: "Sonarr", url: "http://192.0.2.10:7878")

  #expect(ServiceContainerLink.container(for: sonarr, in: containers, serverURL: serverURL) == nil)
}

// MARK: - No link is the right answer

@Test func aServiceBehindADifferentHostnameDoesNotMatch() {
  // A reverse proxy or a Tailscale name. **No link is correct** — the container
  // screen carries Restart, so a wrong link is worse than none.
  let containers = [makeContainer(ports: [port(7878, private: 7878)])]
  let proxied = makeInstance(url: "https://radarr.example.invalid")

  #expect(ServiceContainerLink.container(for: proxied, in: containers, serverURL: serverURL) == nil)
}

@Test func aDifferentPortOnTheSameHostDoesNotMatch() {
  let containers = [makeContainer(ports: [port(7878, private: 7878)])]
  let elsewhere = makeInstance(url: "http://192.0.2.10:9999")

  #expect(
    ServiceContainerLink.container(for: elsewhere, in: containers, serverURL: serverURL) == nil)
}

@Test func anUnrecognisedImageNeverMatches() {
  let containers = [makeContainer(image: "someone/radarr-exporter", ports: [port(7878, private: 7878)])]
  let instance = makeInstance(url: "http://192.0.2.10:7878")

  #expect(ServiceContainerLink.container(for: instance, in: containers, serverURL: serverURL) == nil)
  #expect(
    ServiceContainerLink.instance(
      for: containers[0], in: [instance], serverURL: serverURL) == nil)
}

// MARK: - Stopped containers

@Test func aStoppedContainerStillResolvesItsService() {
  // The case the link exists for: the service says "unreachable", and the
  // container that explains why is by definition not running. A stopped
  // container publishes no ports, so this also exercises the default-port
  // fallback.
  let containers = [makeContainer(state: .exited, ports: [])]
  let instance = makeInstance(url: "http://192.0.2.10:7878")

  #expect(
    ServiceContainerLink.container(for: instance, in: containers, serverURL: serverURL)?.id == "c1")
  #expect(
    ServiceContainerLink.instance(
      for: containers[0], in: [instance], serverURL: serverURL)?.name == "Radarr")
}

@Test func aStoppedContainerIsStillNotOfferedAsAnAddCandidate() {
  // The opposite requirement, and the reason the running filter lives on
  // `candidates(in:)` rather than in the shared helper: a candidate
  // whose connection test can only fail teaches the user nothing.
  #expect(
    ServiceDiscovery.candidates(
      in: [makeContainer(state: .exited, ports: [])], serverURL: serverURL).isEmpty)
}

// MARK: - Address shapes

@Test func anAddressWithoutAPortMatchesTheSchemesDefault() {
  // `http://tower` and `http://tower:80` are the same address; a user who typed
  // the short form should still get the link.
  let containers = [makeContainer(ports: [port(80, private: 7878)])]
  let instance = makeInstance(url: "http://192.0.2.10")

  #expect(
    ServiceContainerLink.container(for: instance, in: containers, serverURL: serverURL)?.id == "c1")
}

@Test func hostComparisonIgnoresCase() {
  // A hostname, not an IP — an IP has no case, so asserting on one would pass
  // whether or not the comparison were case-insensitive.
  let containers = [makeContainer(ports: [port(7878, private: 7878)])]
  let instance = makeInstance(url: "http://Tower.local:7878")
  let lowercased = URL(string: "http://tower.local")!

  #expect(
    ServiceContainerLink.container(
      for: instance, in: containers, serverURL: lowercased)?.id == "c1")
}
