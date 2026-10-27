import Foundation
import Testing
import TowerCore
import TowerData

// Proves `LiveDockerRepository.containers()` end to end against a real
// Unraid GraphQL API, following `LiveSystemRepositoryTests.swift`'s
// `LiveServerCredentials`/`.enabled(if:)` pattern — opt-in only, reported as
// *skipped* (not passed or failed) whenever `UNRAID_URL`/`UNRAID_API_KEY`
// aren't set, so this never runs on a clean checkout or in CI:
// ```
// set -a; source .env.local; set +a
// cd TowerKit && swift test --filter LiveDockerRepositoryTests
// ```
//
// `LiveDockerRepository` has no error/decoding-guard tests of its own here —
// that behavior is structurally identical to `LiveSystemRepository`'s (same
// `.networkOnly`/errors-check/nil-data-guard shape), and already proven via
// `URLProtocol` stubbing in `LiveSystemRepositoryTests.swift`; duplicating
// that stub harness per repository would test the same code path twice, not
// two different behaviors. This file adds only what stubbing can't prove:
// that the real query and mapping succeed against the actual server.

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
