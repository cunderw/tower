import Foundation
import Testing
import TowerCore
import TowerData

// Proves `LiveShareRepository.shares()` end to end against a real Unraid
// GraphQL API, following `LiveDockerRepositoryTests.swift`'s
// `LiveServerCredentials`/`.enabled(if:)` pattern — opt-in only, reported as
// *skipped* whenever `UNRAID_URL`/`UNRAID_API_KEY` aren't set:
// ```
// set -a; source .env.local; set +a
// cd TowerKit && swift test --filter LiveShareRepositoryTests
// ```
//
// Shares have no mutations in Unraid's schema, so everything here is read-only
// by nature rather than by restraint.

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
struct LiveShareRepositoryTests {
  @Test func sharesSucceedsAgainstARealServer() async throws {
    let server = try #require(LiveServerCredentials.server)
    let repository = LiveShareRepository(provider: ApolloClientProvider(server: server))

    let shares = try await repository.shares()

    #expect(!shares.isEmpty)
    let displayNames = shares.map(\.displayName)
    #expect(
      displayNames == displayNames.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    )
    // Every share must be titleable: `name` is nullable and a blank row is not
    // an acceptable rendering of a share that exists.
    #expect(displayNames.allSatisfy { !$0.isEmpty })
  }

  /// The assertion behind the Shares screen showing no usage: the pool figures
  /// are **not** per-share, and the proof is that shares on the same pool
  /// report byte-identical values. If Unraid ever starts reporting real
  /// per-share usage, this test fails — which is the notification worth
  /// having, since the Shares UI leaves the figure out on the strength of this.
  @Test func poolFiguresAreSharedBetweenShares() async throws {
    let server = try #require(LiveServerCredentials.server)
    let repository = LiveShareRepository(provider: ApolloClientProvider(server: server))

    let shares = try await repository.shares()
    let usedFigures = shares.compactMap(\.poolUsedKilobytes)

    // Shares on one pool report the same figure, so there are fewer distinct
    // figures than shares. Per-share usage would make them all differ.
    #expect(usedFigures.count > 1)
    #expect(Set(usedFigures).count < usedFigures.count, "every share reported its own 'used' figure")
  }
}
