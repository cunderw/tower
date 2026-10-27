import Foundation
import Testing
import TowerCore
import TowerData

// Exercises `LiveShareRepository.shares()` itself — its GraphQL-error and
// nil-data guards, and its sort order — through `StubURLProtocol` rather than by
// re-running its `map`/`sorted` in the test, which would assert nothing about
// the shipped code. `ShareMappingTests.swift` covers `Share.init(from:)`.

private func makeRepository(host: String, json: String) -> LiveShareRepository {
  let endpoint = URL(string: "http://\(host)/graphql")!
  StubURLProtocol.stub(url: endpoint, json: json)
  let server = Server(name: "Stub", url: URL(string: "http://\(host)")!, apiKey: "test-key")
  return LiveShareRepository(provider: ApolloClientProvider(server: server, sessionConfiguration: StubURLProtocol.configuration()))
}

private func shareJSON(id: String, name: String?, used: Int64 = 1, free: Int64 = 1) -> String {
  let nameJSON = name.map { "\"\($0)\"" } ?? "null"
  return """
  {"__typename": "Share", "id": "\(id)", "name": \(nameJSON), "nameOrig": null, "comment": null, \
  "include": [], "exclude": [], "cache": null, "allocator": "highwater", "splitLevel": "", \
  "floor": "0", "cow": "auto", "used": \(used), "free": \(free)}
  """
}

private func sharesResponse(_ shares: [String]) -> String {
  #"{"data": {"shares": [\#(shares.joined(separator: ", "))]}}"#
}

@Test func sharesSortsByDisplayNameCaseInsensitively() async throws {
  // The server does not guarantee `shares` order, and a list that reshuffles
  // under the 30-second poll is unusable. Case-insensitive so a capitalised
  // share doesn't sort ahead of every lowercase one — a byte-order sort would
  // put "Backups" before "appdata".
  let repository = makeRepository(
    host: "stub-shares-sort.test",
    json: sharesResponse([
      shareJSON(id: "hash:syslog", name: "syslog"),
      shareJSON(id: "hash:Backups", name: "Backups"),
      shareJSON(id: "hash:appdata", name: "appdata"),
    ])
  )

  let shares = try await repository.shares()

  #expect(shares.map(\.displayName) == ["appdata", "Backups", "syslog"])
}

@Test func sharesSortsAnUnnamedShareByItsFallbackName() async throws {
  // An unnamed share sorts by what the row displays (the share-name half of its
  // id), not by `name`, which is nil.
  let repository = makeRepository(
    host: "stub-shares-sort-unnamed.test",
    json: sharesResponse([
      shareJSON(id: "hash:zeta", name: "Alpha"),
      shareJSON(id: "hash:beta", name: nil),
    ])
  )

  let shares = try await repository.shares()

  #expect(shares.map(\.displayName) == ["Alpha", "beta"])
}

@Test func sharesReturnsEmptyForAServerWithNoShares() async throws {
  // A real state, and not an error: `shares` is a non-null list, so there is no
  // "unavailable" case here the way `vms.domains` has one.
  let repository = makeRepository(host: "stub-shares-empty.test", json: sharesResponse([]))

  let shares = try await repository.shares()

  #expect(shares.isEmpty)
}

@Test func sharesThrowsGraphQLErrorPreservingMessagesInOrder() async throws {
  let repository = makeRepository(
    host: "stub-shares-errors.test",
    json: #"{"data": null, "errors": [{"message": "first"}, {"message": "second"}]}"#
  )

  do {
    _ = try await repository.shares()
    Issue.record("expected shares() to throw")
  } catch let error as AppError {
    #expect(error == .graphQL(["first", "second"]))
  }
}

@Test func sharesThrowsDecodingWhenDataIsMissingWithoutGraphQLErrors() async throws {
  let repository = makeRepository(host: "stub-shares-nil-data.test", json: #"{"data": null}"#)

  do {
    _ = try await repository.shares()
    Issue.record("expected shares() to throw")
  } catch let error as AppError {
    guard case .decoding = error else {
      Issue.record("expected .decoding, got \(error)")
      return
    }
  }
}

@Test func sharesCarriesTheRealBigIntPoolFiguresOffTheWire() async throws {
  // 72_000_000_000 KB is an array-sized figure and overflows `Int32` — the
  // reason `BigInt` is mapped to `Int64` at all. Proven off the wire
  // rather than from a mock, since a scalar-mapping regression would show up
  // exactly here.
  let repository = makeRepository(
    host: "stub-shares-bigint.test",
    json: sharesResponse([
      shareJSON(id: "hash:backups", name: "backups", used: 72_000_000_000, free: 24_000_000_000),
    ])
  )

  let shares = try await repository.shares()
  let share = try #require(shares.first)

  #expect(share.poolUsedKilobytes == 72_000_000_000)
  #expect(share.poolFreeKilobytes == 24_000_000_000)
}
