import Foundation
import Testing
import TowerCore
import TowerData

// `LiveDockerRepositoryTests`, the suite at the bottom, proves
// `LiveDockerRepository.containers()` end to end against a real
// Unraid GraphQL API, following `LiveSystemRepositoryTests.swift`'s
// `LiveServerCredentials`/`.enabled(if:)` pattern — opt-in only, reported as
// *skipped* (not passed or failed) whenever `UNRAID_URL`/`UNRAID_API_KEY`
// aren't set, so this never runs on a clean checkout or in CI:
// ```
// set -a; source .env.local; set +a
// cd TowerKit && swift test --filter LiveDockerRepositoryTests
// ```
//
// The stubbed tests at the top cover the one error mapping `containers()` has
// that `LiveSystemRepository` does not: an error at exactly
// `docker.containers` means the Docker service is off (issue #10). Its plain
// errors-check/nil-data-guard shape is the same as `LiveSystemRepository`'s,
// already proven in `LiveSystemRepositoryTests.swift`, and is not repeated.
// The live suite adds what stubbing can't prove: that the real query and
// mapping succeed against the actual server.

/// A `LiveDockerRepository` whose endpoint answers `json` to every request.
/// `host` must be unique per test — see `StubURLProtocol`.
private func makeStubbedRepository(host: String, json: String) -> LiveDockerRepository {
  let endpoint = URL(string: "http://\(host)/graphql")!
  StubURLProtocol.stub(url: endpoint, json: json)
  let server = Server(name: "Stub", url: URL(string: "http://\(host)")!, apiKey: "test-key")
  return LiveDockerRepository(provider: ApolloClientProvider(server: server, sessionConfiguration: StubURLProtocol.configuration()))
}

/// The `AppError` `containers()` throws for `json`, or `nil` if it returned.
private func containersError(host: String, json: String) async -> AppError? {
  do {
    _ = try await makeStubbedRepository(host: host, json: json).containers()
    return nil
  } catch {
    return error as? AppError
  }
}

@Test func containersReportsDockerUnavailableForAnErrorAtTheContainersField() async {
  // What the server sends with the Docker service off. The tab shows "Docker
  // Unavailable" for this case instead of the generic error screen.
  let error = await containersError(
    host: "stub-docker-unavailable.test",
    json: #"""
    {"data": null, "errors": [{"message": "Docker socket unavailable.", "path": ["docker", "containers"]}]}
    """#
  )
  #expect(error == .serviceUnavailable("Docker"))
}

@Test func containersStillReportsAForbiddenContainersFieldAsUnauthorized() async {
  // An auth error at the same path is a key problem, not a disabled service.
  let error = await containersError(
    host: "stub-docker-containers-forbidden.test",
    json: #"""
    {"data": null, "errors": [{"message": "Forbidden resource", "path": ["docker", "containers"], "extensions": {"code": "FORBIDDEN"}}]}
    """#
  )
  #expect(error == .unauthorized)
}

@Test func containersReportsAnErrorBelowTheContainersFieldAsGraphQL() async {
  // One container's field failing is not the service being off. The path is
  // matched exactly, not by its `docker.containers` prefix.
  let error = await containersError(
    host: "stub-docker-container-field-error.test",
    json: #"""
    {"data": null, "errors": [{"message": "Failed to read name", "path": ["docker", "containers", 0, "name"]}]}
    """#
  )
  #expect(error == .graphQL(["Failed to read name"]))
}

private enum LiveServerCredentials {
  static var server: Server? {
    let environment = ProcessInfo.processInfo.environment
    guard let urlString = environment["UNRAID_URL"], let url = URL(string: urlString),
          let apiKey = environment["UNRAID_API_KEY"], !apiKey.isEmpty
    else { return nil }
    return Server(name: "Live", url: url, apiKey: apiKey)
  }
}

@Suite(.enabled(if: LiveServerCredentials.server != nil))
struct LiveDockerRepositoryTests {
  @Test func containersSucceedsAgainstARealServerSortedByDisplayName() async throws {
    let server = try #require(LiveServerCredentials.server)
    let repository = LiveDockerRepository(provider: ApolloClientProvider(server: server))

    let containers = try await repository.containers()

    #expect(!containers.isEmpty)
    // Sort stability, proven against real data rather
    // than a hand-built fixture.
    #expect(containers.map(\.displayName) == containers.map(\.displayName).sorted())
  }

  /// `logs(id:tail:since:)`, end to end against the real server. Some
  /// containers log nothing for long stretches, so this asks each running
  /// container in turn and stops at the first that returns lines; it fails
  /// only if every running container is silent. Doesn't hardcode message
  /// content (that changes every run) — only the shape the mapping layer
  /// promises: `tail` is a maximum, not an exact count (asking Unraid for 3 can
  /// return 2), and every line carries a message regardless of whether its
  /// timestamp parsed.
  @Test func logsSucceedsAgainstARealServerForARunningContainer() async throws {
    let server = try #require(LiveServerCredentials.server)
    let repository = LiveDockerRepository(provider: ApolloClientProvider(server: server))

    let running = try await repository.containers().filter(\.isRunning)
    try #require(!running.isEmpty, "live server reported no running container")

    var sawLines = false
    for container in running {
      let logs = try await repository.logs(id: container.id, tail: 5, since: nil)
      #expect(logs.lines.count <= 5)
      #expect(logs.lines.allSatisfy { !$0.message.isEmpty })
      if !logs.lines.isEmpty {
        sawLines = true
        break
      }
    }
    #expect(sawLines, "no running container returned any log lines")
  }
}
