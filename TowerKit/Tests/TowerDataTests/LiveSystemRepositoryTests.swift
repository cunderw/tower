import Foundation
import Testing
import TowerCore
import TowerData

// These tests exercise `LiveSystemRepository.dashboard()` and
// `.testConnection()` end-to-end through a stubbed `URLProtocol`, rather
// than only through `DashboardSnapshot(from:)` directly (see
// `SystemRepositoryTests.swift`/`DashboardMappingTests.swift` for the
// mapping-focused tests). That is what actually proves the GraphQL-error
// check and the nil-data guard fire — `DashboardSnapshot.init(from:)` being
// non-public only matters if the guards wrapping the one remaining path to
// it (`dashboard()`) are themselves verified, not merely present in the
// source.
//
// The stub itself lives in `StubURLProtocol.swift`. `ApolloClientProvider`
// has its own `URLSession`, so the stub is installed in that session's
// `protocolClasses` rather than registered process-wide — see that file for
// why that needs no register/unregister bookkeeping.
//
// Both files import only `TowerData`'s public API (`LiveSystemRepository`,
// `ApolloClientProvider(server:)`) plus `TowerCore` — no `@testable`, no
// Apollo/TowerAPI imports needed here, which is itself a small confirmation
// that the Apollo boundary holds from the outside.

/// Builds a `LiveSystemRepository` whose GraphQL endpoint is stubbed to return
/// `json` for every request. `host` must be unique per test so
/// concurrently-running tests never collide on the same stub.
///
/// The stub is installed in this provider's *own* session's
/// `protocolClasses`, so there is nothing process-wide to register and nothing to
/// unregister afterwards.
private func makeRepository(host: String, json: String) -> LiveSystemRepository {
  let endpoint = URL(string: "http://\(host)/graphql")!
  StubURLProtocol.stub(url: endpoint, json: json)
  let server = Server(name: "Stub", url: URL(string: "http://\(host)")!, apiKey: "test-key")
  return LiveSystemRepository(provider: ApolloClientProvider(server: server, sessionConfiguration: StubURLProtocol.configuration()))
}

// MARK: - dashboard()

@Test func dashboardThrowsGraphQLErrorPreservingMessagesInOrder() async throws {
  // GraphQL errors in a 200 response are thrown as `.graphQL`. A 200 with a
  // GraphQL errors array is exactly what a real
  // Unraid server sends for e.g. a permission failure — this is not a
  // transport-level failure.
  let repository = makeRepository(
    host: "stub-dashboard-errors.test",
    json: #"""
    {"data": null, "errors": [{"message": "Cannot query field \"x\""}, {"message": "second error"}]}
    """#
  )

  do {
    _ = try await repository.dashboard()
    Issue.record("expected dashboard() to throw")
  } catch let error as AppError {
    #expect(error == .graphQL(["Cannot query field \"x\"", "second error"]))
  }
}

@Test func dashboardMapsUnauthenticatedExtensionCodeToUnauthorized() async throws {
  // A wrong API key, proven end to end through Apollo's real `fetch()` — not
  // just the `AppError.from(graphQLErrors:)` unit test — because the defect
  // this guards against is specifically that `errors[i].extensions` decodes
  // correctly off the wire and reaches the mapping. This is the exact JSON
  // shape Unraid sends for a wrong API key: HTTP 200, `data: null`, and an
  // `errors[0].extensions.code` of
  // `"UNAUTHENTICATED"` — Unraid never sends HTTP 401/403 for this.
  let repository = makeRepository(
    host: "stub-dashboard-unauthenticated.test",
    json: #"""
    {"data": null, "errors": [{"message": "API key validation failed", "extensions": {"code": "UNAUTHENTICATED"}}]}
    """#
  )

  do {
    _ = try await repository.dashboard()
    Issue.record("expected dashboard() to throw")
  } catch let error as AppError {
    // Exact-case assertion is the point: without the `extensions.code`
    // mapping, this exact wire response maps to
    // `.graphQL(["API key validation failed"])`, whose `recoverySuggestion` is
    // `nil` — the user sees a raw server string with no fix, on the connect
    // screen, for a wrong API key.
    #expect(error == .unauthorized)
  }
}

@Test func dashboardThrowsDecodingErrorWhenDataIsMissingWithoutGraphQLErrors() async throws {
  // Coverage for the nil-data guard: a response with
  // no `errors` key and no usable `data` (a malformed/partial response,
  // distinct from the GraphQL-errors case above where `errors` is what
  // `dashboard()` is supposed to check first).
  let repository = makeRepository(
    host: "stub-dashboard-nil-data.test",
    json: #"{"data": null}"#
  )

  do {
    _ = try await repository.dashboard()
    Issue.record("expected dashboard() to throw")
  } catch let error as AppError {
    guard case .decoding = error else {
      Issue.record("expected .decoding, got \(error)")
      return
    }
  }
}

/// A Dashboard response whose data is intact apart from `vms.domains`, with
/// `errors` interpolated raw. This is the shape Unraid sends with the VM
/// manager disabled: the `domains` resolver throws, and because the field is
/// nullable the server nulls only it.
private func dashboardResponse(errors: String) -> String {
  #"""
  {"data": {
    "array": {"__typename": "UnraidArray", "state": "STARTED",
      "capacity": {"__typename": "ArrayCapacity", "kilobytes": {"__typename": "Capacity", "free": "100", "used": "300", "total": "400"}},
      "parityCheckStatus": {"__typename": "ParityCheck", "status": "NEVER_RUN", "correcting": null, "progress": null, "errors": null, "speed": null, "date": null, "duration": null},
      "disks": [], "parities": [], "caches": []},
    "info": {"__typename": "Info",
      "os": {"__typename": "InfoOs", "distro": "Unraid", "release": "7.3.0", "uptime": null},
      "cpu": {"__typename": "InfoCpu", "brand": null, "cores": null, "threads": null}},
    "metrics": {"__typename": "Metrics", "cpu": null, "memory": null},
    "docker": {"__typename": "Docker", "containers": [{"__typename": "DockerContainer", "id": "c1", "state": "RUNNING"}]},
    "vms": {"__typename": "Vms", "domains": null},
    "shares": [{"__typename": "Share", "id": "s1"}]
  },
  "errors": \#(errors)}
  """#
}

@Test func dashboardShowsVMsUnavailableWhenTheVMManagerIsDisabled() async throws {
  // Issue #8: a server with the VM manager off answered with this error and
  // the whole dashboard failed. The data is intact apart from `domains`, so
  // the dashboard must load and report VMs as unavailable.
  let repository = makeRepository(
    host: "stub-dashboard-vms-disabled.test",
    json: dashboardResponse(errors: #"""
    [{"message": "Failed to retrieve VM domains: libvirt is not running", "path": ["vms", "domains"]}]
    """#)
  )

  let snapshot = try await repository.dashboard()

  #expect(snapshot.services.vmsRunning == nil)
  #expect(snapshot.services.vmsTotal == nil)
  #expect(snapshot.services.vmsSummary == "Unavailable")
  #expect(snapshot.services.containersTotal == 1)
  #expect(snapshot.services.sharesTotal == 1)
}

@Test func dashboardStillThrowsAnErrorOutsideVMDomainsAlongsideOne() async throws {
  // Only the `vms.domains` failure is expressed by the data. Any other error
  // in the same response still fails the load, with its message alone.
  let repository = makeRepository(
    host: "stub-dashboard-vms-and-other.test",
    json: dashboardResponse(errors: #"""
    [{"message": "Failed to retrieve VM domains: libvirt is not running", "path": ["vms", "domains"]},
     {"message": "Failed to read shares", "path": ["shares"]}]
    """#)
  )

  do {
    _ = try await repository.dashboard()
    Issue.record("expected dashboard() to throw")
  } catch let error as AppError {
    #expect(error == .graphQL(["Failed to read shares"]))
  }
}

@Test func dashboardStillMapsAnAuthErrorUnderVMDomainsToUnauthorized() async throws {
  // A key that may not read VMs is a key problem, not a disabled VM manager.
  let repository = makeRepository(
    host: "stub-dashboard-vms-forbidden.test",
    json: dashboardResponse(errors: #"""
    [{"message": "Forbidden resource", "path": ["vms", "domains"], "extensions": {"code": "FORBIDDEN"}}]
    """#)
  )

  do {
    _ = try await repository.dashboard()
    Issue.record("expected dashboard() to throw")
  } catch let error as AppError {
    #expect(error == .unauthorized)
  }
}

// MARK: - testConnection()

@Test func testConnectionReturnsTrueWhenPlatformIsPresent() async throws {
  let repository = makeRepository(
    host: "stub-test-connection-ok.test",
    json: #"""
    {"data": {"info": {"__typename": "Info", "os": {"__typename": "InfoOs", "platform": "Linux"}}}}
    """#
  )

  #expect(try await repository.testConnection())
}

@Test func testConnectionReturnsFalseWhenPlatformIsNil() async throws {
  let repository = makeRepository(
    host: "stub-test-connection-no-platform.test",
    json: #"""
    {"data": {"info": {"__typename": "Info", "os": {"__typename": "InfoOs", "platform": null}}}}
    """#
  )

  #expect(try await repository.testConnection() == false)
}

@Test func testConnectionThrowsGraphQLErrorPreservingMessages() async throws {
  let repository = makeRepository(
    host: "stub-test-connection-errors.test",
    json: #"{"data": null, "errors": [{"message": "unauthorized"}]}"#
  )

  do {
    _ = try await repository.testConnection()
    Issue.record("expected testConnection() to throw")
  } catch let error as AppError {
    #expect(error == .graphQL(["unauthorized"]))
  }
}

// MARK: - Live server (opt-in)

/// Reads `UNRAID_URL`/`UNRAID_API_KEY` from the environment. `nil` if either
/// is unset, which is what keeps `LiveDashboardTests` skipped by default —
/// on a clean checkout, in CI, or in any session that hasn't sourced
/// `.env.local`. Never log `apiKey`.
private enum LiveServerCredentials {
  static var server: Server? {
    let environment = ProcessInfo.processInfo.environment
    guard let urlString = environment["UNRAID_URL"], let url = URL(string: urlString),
          let apiKey = environment["UNRAID_API_KEY"], !apiKey.isEmpty
    else { return nil }
    return Server(name: "Live", url: url, apiKey: apiKey)
  }
}

/// Proves `dashboard()` end to end against a real Unraid GraphQL API —
/// the query parses, every mapping runs without throwing, and the shapes
/// the mapping code assumes (`vms.domains` nullable, `parities`
/// carrying no filesystem fields, `BigInt` values past `Int32.max`, etc.)
/// hold against an actual server response, not just hand-built fixtures.
///
/// Opt-in only: `.enabled(if:)` reports this suite as *skipped*, not
/// passed or failed, whenever `LiveServerCredentials.server` is `nil` — so
/// it never runs unless invoked with real credentials, e.g.:
/// ```
/// set -a; source .env.local; set +a
/// cd TowerKit && swift test --filter LiveSystemRepositoryTests
/// ```
@Suite(.enabled(if: LiveServerCredentials.server != nil))
struct LiveDashboardTests {
  @Test func dashboardSucceedsAgainstARealServer() async throws {
    let server = try #require(LiveServerCredentials.server)
    let repository = LiveSystemRepository(provider: ApolloClientProvider(server: server))

    let snapshot = try await repository.dashboard()

    // The live server's actual counts vary run to run and aren't a fixed
    // contract to assert on — this is a smoke test that the query and
    // every mapping path complete without throwing, decoding, or crashing.
    #expect(snapshot.services.containersTotal >= 0)
    #expect(snapshot.services.containersRunning <= snapshot.services.containersTotal)
    // `vmsRunning`/`vmsTotal` are `Int?` — nil on a server where
    // VM reporting is unavailable, so only assert the invariant when a real
    // reading came back.
    if let vmsRunning = snapshot.services.vmsRunning, let vmsTotal = snapshot.services.vmsTotal {
      #expect(vmsTotal >= 0)
      #expect(vmsRunning <= vmsTotal)
    }
    #expect(snapshot.services.sharesTotal >= 0)
  }

  /// `Dashboard.graphql` must select `device`/`rotational`/IO counters for
  /// `parities`/`caches`; under-selected, they map to `nil` even though the
  /// live server reports them. This asserts against the real server (not a
  /// fixture) that they arrive, and that the fields genuinely absent for
  /// parity (no filesystem) stay absent.
  @Test func parityAndCacheReportDeviceAndIOFieldsFromTheRealServer() async throws {
    let server = try #require(LiveServerCredentials.server)
    let repository = LiveSystemRepository(provider: ApolloClientProvider(server: server))

    let snapshot = try await repository.dashboard()

    let parity = try #require(snapshot.array.parities.first)
    #expect(parity.device != nil, "live server did not report a parity device — Dashboard.graphql selection may have regressed")
    #expect(parity.rotational != nil, "live server did not report parity rotational-ness")
    #expect(parity.numReads != nil, "live server did not report parity IO counters")
    // Parity genuinely has no filesystem — these must stay nil, not become
    // real values.
    #expect(parity.fsFree == nil)
    #expect(parity.fsUsed == nil)
    #expect(parity.fsSize == nil)
    #expect(parity.fsType == nil)

    let cache = try #require(snapshot.array.caches.first)
    #expect(cache.device != nil, "live server did not report a cache device — Dashboard.graphql selection may have regressed")
  }
}
