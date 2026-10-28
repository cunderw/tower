import Foundation
import Testing
import TowerCore
import TowerData

// These tests exercise `LiveVMRepository` itself — not just its mapping —
// through `StubURLProtocol` (installed in this provider's own session).
// `VMMappingTests.swift` covers `VMDomain.init(from:)`;
// everything here is behaviour that only exists in the repository:
//
// - `domains()`'s nil-versus-empty preservation and sort order, proven by
//   calling `domains()` rather than by re-running its `map`/`sorted` in the
//   test, which would assert nothing about the shipped code.
// - The **`Boolean!` refusal path**, which has no analogue in the Docker
//   repository: every `VmMutations` action returns a bare boolean, and `false`
//   must become `AppError.actionRefused` rather than silent success. This is
//   the one behaviour in the VM data layer that cannot be reached from a mock
//   graph at all.
// - That each of the seven action methods extracts *its own* field. A
//   copy-paste slip (`reset` reading `$0.vm.reboot`) type-checks fine and
//   would ship a button that runs the wrong action on a real machine.
//
// Imports are `TowerData`'s public API plus `TowerCore` — no `@testable`, no
// Apollo or TowerAPI import — which is itself a small confirmation that the
// layering rule holds from the outside.

/// Builds a `LiveVMRepository` whose GraphQL endpoint returns `json` for every
/// request. `host` must be unique per test so concurrently-running tests never
/// collide on the same stub.
private func makeRepository(host: String, json: String) -> LiveVMRepository {
  let endpoint = URL(string: "http://\(host)/graphql")!
  StubURLProtocol.stub(url: endpoint, json: json)
  let server = Server(name: "Stub", url: URL(string: "http://\(host)")!, apiKey: "test-key")
  return LiveVMRepository(provider: ApolloClientProvider(server: server, sessionConfiguration: StubURLProtocol.configuration()))
}

/// One `vms` response body. `domains` is interpolated raw so a test can pass
/// `null`, `[]`, or a list.
private func vmsResponse(domains: String) -> String {
  #"{"data": {"vms": {"__typename": "Vms", "id": "hash:vms", "domains": \#(domains)}}}"#
}

private func domainJSON(id: String, name: String?, state: String) -> String {
  let nameJSON = name.map { "\"\($0)\"" } ?? "null"
  return #"{"__typename": "VmDomain", "id": "\#(id)", "name": \#(nameJSON), "state": "\#(state)"}"#
}

// MARK: - domains()

@Test func domainsReportsUnavailableWhenTheServerSendsNullDomains() async throws {
  // The single most important assertion in the VM data layer. `domains` is
  // nullable in the schema, and `null` means VM reporting is unavailable —
  // libvirt stopped or errored. Collapsing it to `[]` would make the VMs tab
  // tell a user with the VM manager off that they have no VMs — the same
  // collapse the dashboard guards against, one screen over.
  let repository = makeRepository(host: "stub-vms-null.test", json: vmsResponse(domains: "null"))

  let inventory = try await repository.domains()

  #expect(inventory.domains == nil)
  #expect(inventory.isUnavailable)
}

@Test func domainsReportsUnavailableWhenTheVMManagerIsDisabled() async throws {
  // Issue #8: with the VM manager off, the `domains` resolver throws and the
  // server nulls the field. That is the "VMs Unavailable" state, not a
  // generic load failure.
  let repository = makeRepository(
    host: "stub-vms-disabled.test",
    json: #"""
    {"data": {"vms": {"__typename": "Vms", "id": "hash:vms", "domains": null}},
     "errors": [{"message": "Failed to retrieve VM domains: libvirt is not running", "path": ["vms", "domains"]}]}
    """#
  )

  let inventory = try await repository.domains()

  #expect(inventory.isUnavailable)
}

@Test func domainsReportsAvailableAndEmptyWhenTheServerSendsNoDomains() async throws {
  // The other direction, proven independently: a healthy server with no VMs
  // defined reports `[]`, and that must not read as "unavailable" either.
  let repository = makeRepository(host: "stub-vms-empty.test", json: vmsResponse(domains: "[]"))

  let inventory = try await repository.domains()

  #expect(inventory.domains == [])
  #expect(!inventory.isUnavailable)
}

@Test func domainsSortsByDisplayNameCaseInsensitively() async throws {
  // The server does not guarantee `domains` order, and a list that reshuffles
  // under the 30-second poll is unusable. Case-insensitive because a
  // byte-order sort puts "Windows XP" ahead of "arcade box" — visibly wrong
  // in a list a human is scanning.
  let repository = makeRepository(
    host: "stub-vms-sort.test",
    json: vmsResponse(domains: """
    [
      \(domainJSON(id: "hash:3", name: "Windows XP", state: "SHUTOFF")),
      \(domainJSON(id: "hash:1", name: "arcade box", state: "RUNNING")),
      \(domainJSON(id: "hash:2", name: "Media Server", state: "RUNNING"))
    ]
    """)
  )

  let domains = try #require(try await repository.domains().domains)

  #expect(domains.map(\.displayName) == ["arcade box", "Media Server", "Windows XP"])
}

@Test func domainsSortsUnnamedVMsByTheirFallbackName() async throws {
  // An unnamed VM sorts by what the list actually displays (the UUID half of
  // its id), not by `name`, which is nil — otherwise it would land in an
  // arbitrary position relative to the names around it.
  let repository = makeRepository(
    host: "stub-vms-sort-unnamed.test",
    json: vmsResponse(domains: """
    [
      \(domainJSON(id: "hash:zeta", name: "Alpha", state: "RUNNING")),
      \(domainJSON(id: "hash:beta", name: nil, state: "SHUTOFF"))
    ]
    """)
  )

  let domains = try #require(try await repository.domains().domains)

  #expect(domains.map(\.displayName) == ["Alpha", "beta"])
}

@Test func domainsThrowsGraphQLErrorPreservingMessagesInOrder() async throws {
  // A 200 with an `errors` array is exactly what Unraid sends for a
  // permission failure — not a transport failure.
  let repository = makeRepository(
    host: "stub-vms-errors.test",
    json: #"{"data": null, "errors": [{"message": "first"}, {"message": "second"}]}"#
  )

  do {
    _ = try await repository.domains()
    Issue.record("expected domains() to throw")
  } catch let error as AppError {
    #expect(error == .graphQL(["first", "second"]))
  }
}

@Test func domainsThrowsDecodingWhenDataIsMissingWithoutGraphQLErrors() async throws {
  let repository = makeRepository(host: "stub-vms-nil-data.test", json: #"{"data": null}"#)

  do {
    _ = try await repository.domains()
    Issue.record("expected domains() to throw")
  } catch let error as AppError {
    guard case .decoding = error else {
      Issue.record("expected .decoding, got \(error)")
      return
    }
  }
}

// MARK: - Actions

/// Every action method paired with the mutation field it must extract. The
/// field name doubles as the stub's payload key, which is what makes the
/// wrong-field slip detectable: a method reading a field the response never
/// carried fails to decode instead of silently succeeding.
private let vmActions: [(field: String, run: @Sendable (LiveVMRepository) async throws -> Void)] = [
  ("start", { try await $0.start(id: "hash:vm") }),
  ("stop", { try await $0.stop(id: "hash:vm") }),
  ("forceStop", { try await $0.forceStop(id: "hash:vm") }),
  ("pause", { try await $0.pause(id: "hash:vm") }),
  ("resume", { try await $0.resume(id: "hash:vm") }),
  ("reboot", { try await $0.reboot(id: "hash:vm") }),
  ("reset", { try await $0.reset(id: "hash:vm") }),
]

private func mutationResponse(field: String, value: Bool) -> String {
  #"{"data": {"vm": {"__typename": "VmMutations", "\#(field)": \#(value)}}}"#
}

@Test func everyActionExtractsItsOwnFieldAndSucceedsOnTrue() async throws {
  for action in vmActions {
    let repository = makeRepository(
      host: "stub-vm-\(action.field.lowercased())-true.test",
      json: mutationResponse(field: action.field, value: true)
    )

    // No `#expect` needed beyond "does not throw": the response carries only
    // this action's own field, so a method extracting a different one cannot
    // reach here.
    try await action.run(repository)
  }
}

@Test func everyActionThrowsActionRefusedOnFalse() async throws {
  for action in vmActions {
    let repository = makeRepository(
      host: "stub-vm-\(action.field.lowercased())-false.test",
      json: mutationResponse(field: action.field, value: false)
    )

    do {
      try await action.run(repository)
      Issue.record("expected \(action.field) to throw on a false response")
    } catch let error as AppError {
      guard case .actionRefused(let detail) = error else {
        Issue.record("expected .actionRefused for \(action.field), got \(error)")
        continue
      }
      // The message goes straight to the user, so it has to read as a
      // sentence about their VM rather than as a field name.
      #expect(detail.hasPrefix("Unraid didn't "))
      #expect(detail.hasSuffix(" this VM."))
    }
  }
}

@Test func actionRefusalCarriesTheActionInItsMessage() async throws {
  // Spot-check that the refusal names the action the user pressed, not a
  // generic failure — "Unraid didn't force stop this VM." is the whole value
  // of `.actionRefused` over `.unknown`.
  let repository = makeRepository(
    host: "stub-vm-forcestop-message.test",
    json: mutationResponse(field: "forceStop", value: false)
  )

  do {
    try await repository.forceStop(id: "hash:vm")
    Issue.record("expected forceStop() to throw")
  } catch let error as AppError {
    #expect(error == .actionRefused("Unraid didn't force stop this VM."))
    #expect(error.recoverySuggestion != nil)
  }
}

@Test func actionThrowsGraphQLErrorRatherThanRefusal() async throws {
  // A permission failure arrives as a GraphQL error, not as `false`. The two
  // must stay distinguishable: one means "you can't do that", the other means
  // "that didn't apply here".
  let repository = makeRepository(
    host: "stub-vm-start-errors.test",
    json: #"{"data": null, "errors": [{"message": "Forbidden"}]}"#
  )

  do {
    try await repository.start(id: "hash:vm")
    Issue.record("expected start() to throw")
  } catch let error as AppError {
    #expect(error == .graphQL(["Forbidden"]))
  }
}
