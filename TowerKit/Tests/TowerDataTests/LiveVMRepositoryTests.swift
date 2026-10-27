import Foundation
import Testing
import TowerCore
import TowerData

// Proves `LiveVMRepository.domains()` end to end against a real Unraid
// GraphQL API, following `LiveDockerRepositoryTests.swift`'s
// `LiveServerCredentials`/`.enabled(if:)` pattern — opt-in only, reported as
// *skipped* (not passed or failed) whenever `UNRAID_URL`/`UNRAID_API_KEY`
// aren't set, so this never runs on a clean checkout:
// ```
// set -a; source .env.local; set +a
// cd TowerKit && swift test --filter LiveVMRepositoryTests
// ```
//
// **Read-only by design.** There is deliberately no live test for any of the
// seven actions: a VM on a real server can be something someone depends
// on, and `forceStop`/`reset` are the equivalent of pulling its power cord.
// The refusal and per-action-field behaviour is proven against
// `StubURLProtocol` in `VMRepositoryStubTests.swift`, which costs nothing and
// cannot take down a machine.

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
struct LiveVMRepositoryTests {
  @Test func domainsSucceedsAgainstARealServer() async throws {
    let server = try #require(LiveServerCredentials.server)
    let repository = LiveVMRepository(provider: ApolloClientProvider(server: server))

    let inventory = try await repository.domains()
    let domains = try #require(inventory.domains, "live server reported no VM subsystem at all")

    #expect(!domains.isEmpty)
    // Sort stability, against real data rather than a
    // hand-built fixture.
    let displayNames = domains.map(\.displayName)
    #expect(
      displayNames == displayNames.sorted {
        $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
      }
    )
    // Every VM must be titleable: `name` is nullable, and a blank row is not
    // an acceptable rendering of one.
    #expect(displayNames.allSatisfy { !$0.isEmpty })
  }
}
