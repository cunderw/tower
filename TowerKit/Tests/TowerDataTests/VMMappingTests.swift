import ApolloTestSupport
import Testing
@testable import TowerAPI
import TowerAPITestMocks
@testable import TowerData
import TowerCore

// These tests exercise `VMDomain.init(from:)`, the Apollo → domain mapping
// behind `LiveVMRepository.domains()`. The repository's own behaviour — the
// GraphQL-error and nil-data guards, nil-versus-empty preservation, sort
// order, and the `Boolean!` refusal path — is covered in
// `VMRepositoryStubTests.swift` against the real `domains()`/action methods
// rather than re-derived here; a test that recomputes what the repository
// does proves only that the test can do arithmetic.
//
// See `DashboardMappingTests.swift` for the canonical writeup of the Apollo
// `Mock<O>` crash the helpers below guard against: every
// entity-typed mock field is constructed explicitly rather than left to a
// cross-module default argument.

private func emptyInfo() -> Mock<TowerAPITestMocks.Info> {
  Mock<TowerAPITestMocks.Info>(
    cpu: Mock<TowerAPITestMocks.InfoCpu>(),
    os: Mock<TowerAPITestMocks.InfoOs>()
  )
}

private func emptyArray() -> Mock<TowerAPITestMocks.UnraidArray> {
  Mock<TowerAPITestMocks.UnraidArray>(
    capacity: Mock<TowerAPITestMocks.ArrayCapacity>(
      kilobytes: Mock<TowerAPITestMocks.Capacity>(free: "0", total: "0", used: "0")
    ),
    parityCheckStatus: Mock<TowerAPITestMocks.ParityCheck>(status: .case(.neverRun)),
    state: .case(.started)
  )
}

/// Assembles the full `Query` mock from already-explicit pieces — only `vms`
/// varies test to test, since `VMs.graphql` selects nothing else.
private func makeQuery(vms: Mock<TowerAPITestMocks.Vms>) -> Mock<TowerAPITestMocks.Query> {
  Mock<TowerAPITestMocks.Query>(
    array: emptyArray(),
    docker: Mock<TowerAPITestMocks.Docker>(containers: []),
    info: emptyInfo(),
    metrics: Mock<TowerAPITestMocks.Metrics>(),
    shares: [],
    vms: vms
  )
}

private func domainMock(
  id: TowerAPI.PrefixedID = "hash:uuid",
  name: String? = "VM",
  state: GraphQLEnum<TowerAPI.VmState> = .case(.running)
) -> Mock<TowerAPITestMocks.VmDomain> {
  Mock<TowerAPITestMocks.VmDomain>(id: id, name: name, state: state)
}

/// Runs one `VmDomain` mock through the real mapping initializer.
private func mapOne(_ domain: Mock<TowerAPITestMocks.VmDomain>) async throws -> VMDomain {
  let data = await VMsQuery.Data.from(makeQuery(vms: Mock<TowerAPITestMocks.Vms>(domains: [domain])))
  return try #require(data.vms.domains?.first.map(VMDomain.init(from:)))
}

@Test func mapsIDNameAndState() async throws {
  let domain = try await mapOne(domainMock(id: "hash:uuid-1", name: "Media Server", state: .case(.running)))

  #expect(domain.id == "hash:uuid-1")
  #expect(domain.name == "Media Server")
  #expect(domain.state == .running)
}

@Test func mapsEveryVmStateCaseThroughApollo() async throws {
  // Proves the raw strings in `VMState.init(rawValue:)` match what Apollo
  // actually produces for each schema case, not just what the schema file
  // says. `VMDomainTests` covers the same mapping from hand-written strings;
  // this covers the wire.
  let expected: [(GraphQLEnum<TowerAPI.VmState>, VMState)] = [
    (.case(.nostate), .nostate),
    (.case(.running), .running),
    (.case(.idle), .idle),
    (.case(.paused), .paused),
    (.case(.shutdown), .shutdown),
    (.case(.shutoff), .shutoff),
    (.case(.crashed), .crashed),
    (.case(.pmsuspended), .pmSuspended),
  ]
  for (wire, domain) in expected {
    #expect(try await mapOne(domainMock(state: wire)).state == domain)
  }
}

@Test func mapsUnrecognizedStateToUnknown() async throws {
  // `GraphQLEnum.unknown` is what Apollo produces for a server-side addition
  // to `VmState`. It must degrade to `.unknown` rather than fail the fetch —
  // one new state on a future Unraid release would otherwise blank the tab.
  let domain = try await mapOne(domainMock(state: .unknown("BLOCKED")))

  #expect(domain.state == .unknown)
  #expect(domain.state.activity == .indeterminate)
}

@Test func mapsEmptyNameToNilSoDisplayNameFallsBack() async throws {
  // The wire sends `""` for absent strings; `""` is the absence of a name,
  // not a name. Handled at this boundary so the model never carries one.
  let domain = try await mapOne(domainMock(id: "hash:00000000-0000-4000-8000-000000000001", name: ""))

  #expect(domain.name == nil)
  #expect(domain.displayName == "00000000-0000-4000-8000-000000000001")
}

@Test func mapsNilNameWithoutInventingOne() async throws {
  let domain = try await mapOne(domainMock(id: "hash:00000000-0000-4000-8000-000000000001", name: nil))

  #expect(domain.name == nil)
  #expect(domain.displayName == "00000000-0000-4000-8000-000000000001")
}
