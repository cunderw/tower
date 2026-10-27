import Foundation
import Testing
@testable import TowerCore

@Test func displayNameStripsTheLeadingSlash() {
  #expect(Container.stub(names: ["/code-server"]).displayName == "code-server")
}

@Test func displayNameFallsBackToImageWhenUnnamed() {
  #expect(Container.stub(names: [], image: "linuxserver/code-server").displayName == "linuxserver/code-server")
}

@Test func stateMapsKnownValues() {
  #expect(ContainerState(rawValue: "RUNNING") == .running)
  #expect(ContainerState(rawValue: "PAUSED") == .paused)
  #expect(ContainerState(rawValue: "EXITED") == .exited)
}

@Test func stateMapsUnrecognizedToUnknown() {
  // The server may add a case in the future; this must degrade to
  // `.unknown` rather than fail to construct at all.
  #expect(ContainerState(rawValue: "RESTARTING") == .unknown)
}

@Test func isRunningOnlyForRunning() {
  #expect(Container.stub(state: .running).isRunning)
  #expect(!Container.stub(state: .paused).isRunning)
  #expect(!Container.stub(state: .exited).isRunning)
}

@Test func portSummaryFormatsPublicToPrivate() {
  let port = ContainerPort(ip: "0.0.0.0", privatePort: 80, publicPort: 13_378, type: "TCP")
  #expect(port.summary == "13378 → 80/TCP")
}

@Test func portSummaryOmitsMissingPublicPort() {
  // Internal-only port: Docker never published this one to the host, so
  // there is no "public → " half to show.
  let port = ContainerPort(ip: nil, privatePort: 80, publicPort: nil, type: "TCP")
  #expect(port.summary == "80/TCP")
}

@Test func applyingStateUpdateReplacesOnlyStateAndStatus() {
  let original = Container.stub(
    id: "1", image: "linuxserver/sonarr", state: .exited, status: "Exited (0) 3 hours ago"
  )
  let update = ContainerStateUpdate(id: "1", state: .running, status: "Up less than a second")

  let updated = original.applyingStateUpdate(update)

  #expect(updated.state == .running)
  #expect(updated.status == "Up less than a second")
  // Everything else — the fields the mutation's selection set never asked
  // about — must survive untouched.
  #expect(updated.id == original.id)
  #expect(updated.image == original.image)
  #expect(updated.names == original.names)
}

extension Container {
  static func stub(
    id: String = "1", names: [String] = ["/container"], image: String = "image:latest",
    state: ContainerState = .running, status: String = "Up 2 hours", autoStart: Bool = false,
    isUpdateAvailable: Bool? = nil, isOrphaned: Bool = false,
    webUiURL: URL? = nil, iconURL: URL? = nil, projectURL: URL? = nil,
    supportURL: URL? = nil, registryURL: URL? = nil, templatePath: String? = nil,
    networkMode: String? = nil, ports: [ContainerPort] = []
  ) -> Container {
    Container(
      id: id, names: names, image: image, state: state, status: status, autoStart: autoStart,
      isUpdateAvailable: isUpdateAvailable, isOrphaned: isOrphaned, webUiURL: webUiURL,
      iconURL: iconURL, projectURL: projectURL, supportURL: supportURL, registryURL: registryURL,
      templatePath: templatePath, networkMode: networkMode, ports: ports
    )
  }
}
