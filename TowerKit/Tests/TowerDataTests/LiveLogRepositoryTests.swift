import Foundation
import Testing
import TowerCore
import TowerData

// Proves `LiveLogRepository` end to end against a real Unraid GraphQL API —
// opt-in only, skipped whenever `UNRAID_URL`/`UNRAID_API_KEY` aren't set:
// ```
// set -a; source .env.local; set +a
// cd TowerKit && swift test --filter LiveLogRepositoryTests
// ```
//
// Read-only by nature: Unraid exposes no log mutations.
//
// **Never prints log contents.** A server's syslog can contain hostnames, IPs,
// share names, and API-key prefixes, and this suite's output ends up in build
// logs. Assertions here are about shape and counts only.

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
struct LiveLogRepositoryTests {
  private func repository() throws -> LiveLogRepository {
    let server = try #require(LiveServerCredentials.server)
    return LiveLogRepository(provider: ApolloClientProvider(server: server))
  }

  @Test func logFilesSucceedsAndIsSortedByName() async throws {
    let files = try await repository().logFiles()

    #expect(!files.isEmpty)
    let names = files.map(\.name)
    #expect(names == names.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending })
    #expect(names.allSatisfy { !$0.isEmpty })
    // Paths are the server's own and are never constructed client-side; every one
    // must be absolute, or the viewer would be asking for something else.
    #expect(files.allSatisfy { $0.path.hasPrefix("/") })
    #expect(files.allSatisfy { $0.sizeBytes >= 0 })
    print("Live log files: \(files.count), empty: \(files.filter(\.isEmpty).count)")
  }

  @Test func aBoundedRequestReturnsNoMoreLinesThanAskedFor() async throws {
    // `lines` is a maximum. The one thing this screen must not do is fetch an
    // unbounded syslog, so the cap has to be respected by the server.
    let repository = try repository()
    let files = try await repository.logFiles()
    let nonEmpty = try #require(files.first { !$0.isEmpty }, "live server reported no non-empty log file")

    let contents = try await repository.logFile(path: nonEmpty.path, lines: 5)

    #expect(contents.lines.count <= 5)
    #expect(contents.path == nonEmpty.path)
    #expect(contents.totalLines >= contents.lines.count)
    // No line may be a phantom produced by the trailing-newline split.
    #expect(contents.lines.count == LogFileContents.splitIntoLines(contents.lines.joined(separator: "\n") + "\n").count)
  }

  @Test func anEmptyLogFileReturnsNoLinesRatherThanFailing() async throws {
    // Unraid's log directory can hold 0-byte files. Opening one is a real
    // thing a user does.
    let repository = try repository()
    let files = try await repository.logFiles()
    guard let empty = files.first(where: \.isEmpty) else { return }

    let contents = try await repository.logFile(path: empty.path, lines: 200)

    #expect(contents.lines.isEmpty)
    #expect(!contents.isTruncated)
  }
}
