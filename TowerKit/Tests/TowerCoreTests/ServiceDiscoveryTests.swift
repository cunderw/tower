import Foundation
import Testing
@testable import TowerCore

private func makeContainer(
  id: String = "c1",
  name: String = "sonarr",
  image: String,
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

private let serverURL = URL(string: "http://192.0.2.10")!

// MARK: - Matching

@Test(arguments: [
  ("linuxserver/sonarr:latest", ServiceKind.sonarr),
  ("linuxserver/radarr", ServiceKind.radarr),
  ("ghcr.io/hotio/lidarr:release", ServiceKind.lidarr),
  ("lscr.io/linuxserver/prowlarr:develop", ServiceKind.prowlarr),
  ("linuxserver/bazarr", ServiceKind.bazarr),
  ("sctx/overseerr:latest", ServiceKind.overseerr),
  ("tautulli/tautulli", ServiceKind.tautulli),
  ("linuxserver/nzbget", ServiceKind.nzbget),
  // A registry with a port in its host, which also contains a colon.
  ("registry.local:5000/linuxserver/sonarr:latest", ServiceKind.sonarr),
  // Digest-pinned.
  ("linuxserver/radarr@sha256:abc123", ServiceKind.radarr),
  ("LinuxServer/Sonarr:Latest", ServiceKind.sonarr),
])
func knownImagesMatchTheirService(image: String, expected: ServiceKind) {
  #expect(ServiceDiscovery.kind(forImage: image) == expected)
}

@Test(arguments: [
  // Each of these contains a service's name and is not that service. A
  // `contains` match would offer every one of them.
  "linuxserver/radarr-exporter",
  "someone/sonarr-backup",
  "someone/prowlarr-indexer-proxy",
  "linuxserver/plex",
  "postgres:16",
  "linuxserver/sonarr-fork",
  "jellyfin/jellyfin",
])
func unrelatedImagesMatchNothing(image: String) {
  #expect(ServiceDiscovery.kind(forImage: image) == nil)
}

// MARK: - Candidates

@Test func aRunningSonarrYieldsACandidateOnTheServersHost() {
  let containers = [
    makeContainer(
      id: "abc", name: "sonarr", image: "linuxserver/sonarr:latest",
      ports: [ContainerPort(ip: "0.0.0.0", privatePort: 8989, publicPort: 8989, type: "TCP")])
  ]

  let candidates = ServiceDiscovery.candidates(in: containers, serverURL: serverURL)

  #expect(candidates.count == 1)
  #expect(candidates.first?.kind == .sonarr)
  #expect(candidates.first?.containerName == "sonarr")
  #expect(candidates.first?.baseURL.absoluteString == "http://192.0.2.10:8989")
  #expect(candidates.first?.id == "abc")
}

@Test func aRemappedPublishedPortIsUsedRatherThanTheDefault() {
  // Two Sonarrs on one box is exactly why multi-instance exists, and the second
  // one is not on 8989.
  let containers = [
    makeContainer(
      image: "linuxserver/sonarr",
      ports: [ContainerPort(ip: nil, privatePort: 8989, publicPort: 18989, type: "TCP")])
  ]
  #expect(
    ServiceDiscovery.candidates(in: containers, serverURL: serverURL)
      .first?.baseURL.absoluteString == "http://192.0.2.10:18989")
}

@Test func aHostNetworkContainerFallsBackToTheServicesOwnPort() {
  // `network_mode: host` publishes nothing, so there is no mapping to read —
  // the stock port is the only answer available, and it is the right one.
  let containers = [makeContainer(image: "linuxserver/radarr", ports: [])]
  #expect(
    ServiceDiscovery.candidates(in: containers, serverURL: serverURL)
      .first?.baseURL.absoluteString == "http://192.0.2.10:7878")
}

@Test func anUnrelatedPublishedPortIsNotPreferredOverTheServicesOwn() {
  let containers = [
    makeContainer(
      image: "linuxserver/radarr",
      ports: [
        ContainerPort(ip: nil, privatePort: 9117, publicPort: 9117, type: "TCP"),
        ContainerPort(ip: nil, privatePort: 7878, publicPort: 7979, type: "TCP"),
      ])
  ]
  #expect(
    ServiceDiscovery.candidates(in: containers, serverURL: serverURL)
      .first?.baseURL.absoluteString == "http://192.0.2.10:7979")
}

@Test func stoppedContainersAreNotOffered() {
  // A candidate whose test always fails teaches the user nothing about what
  // they typed.
  let containers = [makeContainer(image: "linuxserver/sonarr", state: .exited)]
  #expect(ServiceDiscovery.candidates(in: containers, serverURL: serverURL).isEmpty)
}

@Test func unrecognisedContainersAreNotOffered() {
  let containers = [
    makeContainer(id: "1", name: "plex", image: "linuxserver/plex"),
    makeContainer(id: "2", name: "db", image: "postgres:16"),
    makeContainer(id: "3", name: "radarr-exporter", image: "someone/radarr-exporter"),
  ]
  #expect(ServiceDiscovery.candidates(in: containers, serverURL: serverURL).isEmpty)
}

@Test func twoContainersOfTheSameKindBothBecomeCandidates() {
  let containers = [
    makeContainer(
      id: "hd", name: "radarr", image: "linuxserver/radarr",
      ports: [ContainerPort(ip: nil, privatePort: 7878, publicPort: 7878, type: "TCP")]),
    makeContainer(
      id: "uhd", name: "radarr-4k", image: "linuxserver/radarr",
      ports: [ContainerPort(ip: nil, privatePort: 7878, publicPort: 7879, type: "TCP")]),
  ]

  let candidates = ServiceDiscovery.candidates(in: containers, serverURL: serverURL)

  #expect(candidates.map(\.containerName) == ["radarr", "radarr-4k"])
  #expect(candidates.map(\.baseURL.port) == [7878, 7879])
}

@Test func anIPv6ServerAddressKeepsItsBrackets() {
  let containers = [makeContainer(image: "linuxserver/radarr")]
  let candidates = ServiceDiscovery.candidates(
    in: containers, serverURL: URL(string: "http://[fd00::1]")!)
  #expect(candidates.first?.baseURL.absoluteString == "http://[fd00::1]:7878")
}

@Test func everyKindHasADefaultPort() {
  // The ports are what make a candidate usable at all; a zero or a duplicate
  // would produce an address that silently points at the wrong service.
  let ports = ServiceKind.allCases.map(ServiceDiscovery.defaultPort(for:))
  #expect(ports.allSatisfy { $0 > 0 && $0 < 65_536 })
  #expect(Set(ports).count == ports.count)
}
