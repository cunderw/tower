@_spi(Execution) import Apollo
import Foundation
import Testing
import TowerCore
@testable import TowerData

// Issue #55. Apollo keys a cached field by its arguments, so a `setState`
// result written to the normalized cache carries the `decryptionPassword`
// argument in its keys until the app quits.

/// Every record key, field key and value in `store`, reached from the three
/// operation roots. Apollo has no call that lists every record, and Tower sets
/// no `cacheKeyInfo`, so every record that an operation writes hangs off a root.
private func cacheContents(of store: ApolloStore) async throws -> [String] {
  try await store.withinReadTransaction { transaction in
    var texts: [String] = []
    var visited: Set<String> = []
    var pending: Set<String> = ["QUERY_ROOT", "MUTATION_ROOT", "SUBSCRIPTION_ROOT"]
    while !pending.isEmpty {
      visited.formUnion(pending)
      let records = try await transaction.readOnlyCache.loadRecords(forKeys: pending)
      pending = []
      for record in records.values {
        texts.append(record.key)
        for (fieldKey, value) in record.fields {
          texts.append(fieldKey)
          texts.append(String(describing: value))
          for key in referencedKeys(in: value) where !visited.contains(key) {
            pending.insert(key)
          }
        }
      }
    }
    return texts
  }
}

/// The record keys that `value` references, at any depth of nested lists.
private func referencedKeys(in value: Record.Value) -> [String] {
  if let reference = value as? CacheReference {
    return [reference.key]
  }
  if let list = value as? [Record.Value] {
    return list.flatMap(referencedKeys(in:))
  }
  return []
}

@Test func setArrayStateLeavesThePassphraseOutOfTheCache() async throws {
  let endpoint = URL(string: "http://stub-array-cache.test/graphql")!
  StubURLProtocol.stub(
    url: endpoint, operationName: "SetArrayState",
    json: #"{"data": {"array": {"__typename": "ArrayMutations", "setState": {"__typename": "UnraidArray", "id": "server:array", "state": "STARTED"}}}}"#
  )
  let server = Server(name: "Stub", url: URL(string: "http://stub-array-cache.test")!, apiKey: "test-key")
  let provider = ApolloClientProvider(server: server, sessionConfiguration: StubURLProtocol.configuration())
  let repository = LiveSystemRepository(provider: provider)
  let passphrase = "Passphrase55Token"

  let state = try await repository.setArrayState(.start, passphrase: passphrase)

  #expect(state == "STARTED")
  let leaks = try await cacheContents(of: provider.client.store).filter { $0.contains(passphrase) }
  #expect(leaks.isEmpty, "the cache holds the passphrase in \(leaks)")
}
