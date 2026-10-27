import Foundation
import Testing
import TowerCore
@testable import TowerData

/// Loads a committed fixture: a response body in the shape the service sends,
/// with invented values. Probes assert against these rather than against a
/// literal written from memory, which is how a probe ends up decoding a shape
/// the service never sends.
private func fixture(_ name: String) throws -> Data {
  let url = try #require(
    Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures/ServiceStatus"),
    "missing fixture \(name)")
  return try Data(contentsOf: url)
}

private func makeChecker(
  host: String,
  kind: ServiceKind,
  credentials: ServiceCredentials
) -> (LiveServiceStatusChecker, ServiceInstance) {
  let instance = ServiceInstance(
    kind: kind,
    name: kind.displayName,
    baseURL: URL(string: "http://\(host)")!,
    credentials: credentials
  )
  let checker = LiveServiceStatusChecker(
    sessionConfiguration: ServiceStubURLProtocol.configuration())
  return (checker, instance)
}

/// The eight kinds, each with the fixture its probe should accept and the
/// credentials shape it takes.
private struct Probe: Sendable {
  let kind: ServiceKind
  let fixture: String
  let credentials: ServiceCredentials
  let expectedVersion: String?
  let expectedPath: String
}

private let probes: [Probe] = [
  Probe(kind: .radarr, fixture: "radarr-system-status.json", credentials: .apiKey("k"),
        expectedVersion: "5.14.0.9383", expectedPath: "/api/v3/system/status"),
  Probe(kind: .sonarr, fixture: "sonarr-system-status.json", credentials: .apiKey("k"),
        expectedVersion: "4.0.10.2544", expectedPath: "/api/v3/system/status"),
  // Lidarr is **v1**, not v3. It shares the *arr response shape, which
  // is what made the wrong path easy to miss: the probe 404s, the badge says
  // unreachable, and every Lidarr screen keeps working because the repository
  // uses the right path.
  Probe(kind: .lidarr, fixture: "lidarr-system-status.json", credentials: .apiKey("k"),
        expectedVersion: "2.6.4.4402", expectedPath: "/api/v1/system/status"),
  // Prowlarr shares the *arr shape but is still on v1 — a v3 path 404s.
  Probe(kind: .prowlarr, fixture: "prowlarr-system-status.json", credentials: .apiKey("k"),
        expectedVersion: "1.28.2.4885", expectedPath: "/api/v1/system/status"),
  Probe(kind: .bazarr, fixture: "bazarr-system-status.json", credentials: .apiKey("k"),
        expectedVersion: "1.4.5", expectedPath: "/api/system/status"),
  // Overseerr's /status answers without a key, so it can't prove one is good.
  Probe(kind: .overseerr, fixture: "overseerr-auth-me.json", credentials: .apiKey("k"),
        expectedVersion: nil, expectedPath: "/api/v1/auth/me"),
  Probe(kind: .tautulli, fixture: "tautulli-status.json", credentials: .apiKey("k"),
        expectedVersion: nil, expectedPath: "/api/v2"),
  Probe(kind: .nzbget, fixture: "nzbget-version.json",
        credentials: .usernamePassword(username: "u", password: "p"),
        expectedVersion: "21.1", expectedPath: "/jsonrpc/version"),
]

@Test(arguments: probes)
private func everyKindReportsReachableFromItsOwnFixture(probe: Probe) async throws {
  let host = "\(probe.kind.rawValue)-ok.test"
  let body = try fixture(probe.fixture)
  ServiceStubURLProtocol.stub(
    host: host, reply: ServiceStubURLProtocol.Reply(status: 200, body: body))
  let (checker, instance) = makeChecker(
    host: host, kind: probe.kind, credentials: probe.credentials)

  let status = await checker.status(for: instance)

  #expect(status == .reachable(version: probe.expectedVersion))
  #expect(ServiceStubURLProtocol.requests(host: host).first?.url?.path() == probe.expectedPath)
}

@Test(arguments: probes)
private func everyKindReportsUnreachableWhenTheHostRefuses(probe: Probe) async throws {
  let host = "\(probe.kind.rawValue)-down.test"
  ServiceStubURLProtocol.stub(host: host) { _ in .failure(URLError(.cannotConnectToHost)) }
  let (checker, instance) = makeChecker(
    host: host, kind: probe.kind, credentials: probe.credentials)

  let status = await checker.status(for: instance)
  #expect(status == .unreachable(.serverUnreachable))
}

// MARK: - Rejected credentials are their own state

@Test(arguments: [ServiceKind.radarr, .sonarr, .lidarr, .prowlarr, .bazarr, .overseerr, .nzbget])
func a401MapsToUnauthorizedNotUnreachable(kind: ServiceKind) async throws {
  let host = "\(kind.rawValue)-401.test"
  ServiceStubURLProtocol.stub(host: host, reply: .json(#"{"error":"Unauthorized"}"#, status: 401))
  let credentials: ServiceCredentials = kind == .nzbget
    ? .usernamePassword(username: "u", password: "wrong")
    : .apiKey("wrong")
  let (checker, instance) = makeChecker(host: host, kind: kind, credentials: credentials)

  let status = await checker.status(for: instance)
  #expect(status == .unauthorized)
}

@Test func tautulliRejectsAKeyWithHTTP200AndIsStillUnauthorized() async throws {
  // The one that would silently pass a wrong key as healthy: Tautulli answers
  // 200 and puts the refusal in the body.
  let host = "tautulli-badkey.test"
  ServiceStubURLProtocol.stub(
    host: host,
    reply: ServiceStubURLProtocol.Reply(
      status: 200, body: try fixture("tautulli-invalid-apikey.json")))
  let (checker, instance) = makeChecker(host: host, kind: .tautulli, credentials: .apiKey("wrong"))

  let status = await checker.status(for: instance)
  #expect(status == .unauthorized)
}

@Test(arguments: [ServiceKind.radarr, .sonarr, .lidarr, .prowlarr, .bazarr, .overseerr, .nzbget])
func a403IsUnauthorized(kind: ServiceKind) async throws {
  let host = "\(kind.rawValue)-403.test"
  ServiceStubURLProtocol.stub(host: host, reply: .json(#"{"error":"Forbidden"}"#, status: 403))
  let credentials: ServiceCredentials = kind == .nzbget
    ? .usernamePassword(username: "u", password: "p")
    : .apiKey("k")
  let (checker, instance) = makeChecker(host: host, kind: kind, credentials: credentials)

  #expect(await checker.status(for: instance) == .unauthorized)
}

@Test func aTautulliFailureThatIsNotAboutTheKeyIsNotReportedAsACredentialProblem() async throws {
  let host = "tautulli-othererror.test"
  ServiceStubURLProtocol.stub(
    host: host,
    reply: .json(#"{"response":{"result":"error","message":"Database is locked","data":{}}}"#))
  let (checker, instance) = makeChecker(host: host, kind: .tautulli, credentials: .apiKey("k"))

  let status = await checker.status(for: instance)
  #expect(status == .unreachable(.unknown("Database is locked")))
}

@Test func unauthorizedAndUnreachableAreDistinctStates() async throws {
  // The two failures a user recovers from differently must not collapse into
  // one badge.
  let unauthorizedHost = "distinct-401.test"
  let downHost = "distinct-down.test"
  ServiceStubURLProtocol.stub(host: unauthorizedHost, reply: .json("{}", status: 401))
  ServiceStubURLProtocol.stub(host: downHost) { _ in .failure(URLError(.cannotConnectToHost)) }
  let (checker, rejected) = makeChecker(host: unauthorizedHost, kind: .radarr, credentials: .apiKey("bad"))
  let (_, down) = makeChecker(host: downHost, kind: .radarr, credentials: .apiKey("good"))

  let rejectedStatus = await checker.status(for: rejected)
  let downStatus = await checker.status(for: down)

  #expect(rejectedStatus != downStatus)
  #expect(rejectedStatus == .unauthorized)
  #expect(downStatus.isProblem)
}

// MARK: - Concurrency

@Test func checksRunConcurrentlyRatherThanOneAfterAnother() async throws {
  // Tested against `ServiceStatusChecking`'s own `statuses(for:)` rather than
  // through URLSession: a custom `URLProtocol`'s `startLoading` runs on one
  // shared loader thread, so a stub that blocks there serialises every request
  // no matter what the caller does, and a test at that level measures
  // Foundation instead of Tower.
  //
  // Overlap, not arrival count, is the property: three probes arriving one
  // after another also add up to three. Each probe here waits for company, so a
  // sequential implementation leaves the peak at 1 and fails.
  let overlap = OverlapCounter()
  let instances = (0..<3).map { index in
    ServiceInstance(
      kind: .radarr, name: "Radarr \(index)", baseURL: URL(string: "http://unused.test")!,
      credentials: .apiKey("k"))
  }

  let statuses = await GatedChecker(overlap: overlap, expected: instances.count)
    .statuses(for: instances)

  let peak = await overlap.peak
  #expect(peak == instances.count, "the probes never overlapped — they ran in sequence")
  #expect(statuses.count == instances.count)
}

/// Answers every probe, but only once `expected` of them are in flight at the
/// same time — or after a bounded wait, so a sequential caller fails the test
/// rather than hanging it.
private struct GatedChecker: ServiceStatusChecking {
  let overlap: OverlapCounter
  let expected: Int

  func status(for instance: ServiceInstance) async -> ServiceStatus {
    await overlap.enter()
    for _ in 0..<200 where await overlap.inFlight < expected {
      try? await Task.sleep(for: .milliseconds(10))
    }
    await overlap.leave()
    return .reachable(version: nil)
  }
}

private actor OverlapCounter {
  private(set) var inFlight = 0
  private(set) var peak = 0

  func enter() {
    inFlight += 1
    peak = max(peak, inFlight)
  }

  func leave() {
    inFlight -= 1
  }
}

@Test func oneDeadServiceDoesNotHideTheHealthyOnes() async throws {
  let goodHost = "mixed-good.test"
  let badHost = "mixed-bad.test"
  ServiceStubURLProtocol.stub(
    host: goodHost,
    reply: ServiceStubURLProtocol.Reply(status: 200, body: try fixture("radarr-system-status.json")))
  ServiceStubURLProtocol.stub(host: badHost) { _ in .failure(URLError(.cannotConnectToHost)) }
  let good = ServiceInstance(
    kind: .radarr, name: "Radarr", baseURL: URL(string: "http://\(goodHost)")!,
    credentials: .apiKey("k"))
  let bad = ServiceInstance(
    kind: .sonarr, name: "Sonarr", baseURL: URL(string: "http://\(badHost)")!,
    credentials: .apiKey("k"))
  let checker = LiveServiceStatusChecker(
    sessionConfiguration: ServiceStubURLProtocol.configuration())

  let statuses = await checker.statuses(for: [good, bad])

  #expect(statuses[good.id] == .reachable(version: "5.14.0.9383"))
  #expect(statuses[bad.id]?.isProblem == true)
}

@Test func checkingNothingReturnsNothing() async {
  let checker = LiveServiceStatusChecker(
    sessionConfiguration: ServiceStubURLProtocol.configuration())
  let statuses = await checker.statuses(for: [])
  #expect(statuses.isEmpty)
}
