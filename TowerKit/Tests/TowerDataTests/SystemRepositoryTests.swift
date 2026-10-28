import ApolloTestSupport
import Testing
@testable import TowerAPI
import TowerAPITestMocks
@testable import TowerData
import TowerCore

// These tests exercise `DashboardSnapshot.init(from:)`, the Apollo → domain
// mapping behind `LiveSystemRepository.dashboard()`. Kept alongside
// `DashboardMappingTests.swift` rather than folded into it: that file's tests
// focus on IO/filesystem fields, disk sort order, parity status, and service
// counts, and none of them assert `state`/`capacity`/`system` together as one
// integrated read, the capacity-string-parse-failure fallback, or the
// disk-level identity fields (`id`/`displayName`/`temp`/`isHealthy`/
// `usedFraction`) this file covers — genuinely different slices of the same
// mapping, not a repeat of what's already proven there.
//
// Apollo's generated test mocks (`TowerAPITestMocks`) build a `Mock<O>` graph
// per GraphQL object type, which `RootSelectionSet.from(_:)` executes
// through the same `GraphQLExecutor` that parses a real network response —
// so these fixtures exercise the exact nullability and type-coercion rules a
// real network response would.
//
// IMPORTANT: every entity-typed `Mock<O>` parameter below (single or list)
// is passed explicitly, never left to its declared default — see
// `DashboardMappingTests.swift`'s file header for the reproducible
// cross-module crash that omitting one triggers, and why the
// rule covers list-typed entity fields too. Writing the same value
// explicitly at the call site avoids it entirely; see the helpers below.

private func emptyInfo() -> Mock<TowerAPITestMocks.Info> {
  Mock<TowerAPITestMocks.Info>(
    cpu: Mock<TowerAPITestMocks.InfoCpu>(),
    os: Mock<TowerAPITestMocks.InfoOs>()
  )
}

private func emptyMetrics() -> Mock<TowerAPITestMocks.Metrics> {
  Mock<TowerAPITestMocks.Metrics>()
}

private func emptyDocker() -> Mock<TowerAPITestMocks.Docker> {
  Mock<TowerAPITestMocks.Docker>(containers: [])
}

private func emptyVms() -> Mock<TowerAPITestMocks.Vms> {
  Mock<TowerAPITestMocks.Vms>(domains: [])
}

private func capacity(free: String, total: String, used: String) -> Mock<TowerAPITestMocks.ArrayCapacity> {
  Mock<TowerAPITestMocks.ArrayCapacity>(
    kilobytes: Mock<TowerAPITestMocks.Capacity>(free: free, total: total, used: used)
  )
}

private func neverRunParityCheck() -> Mock<TowerAPITestMocks.ParityCheck> {
  Mock<TowerAPITestMocks.ParityCheck>(status: .case(.neverRun))
}

@Test func mapsArrayStateAndCapacity() async throws {
  let mock = Mock<TowerAPITestMocks.Query>(
    array: Mock<TowerAPITestMocks.UnraidArray>(
      capacity: capacity(free: "24000000000", total: "96000000000", used: "72000000000"),
      parityCheckStatus: neverRunParityCheck(),
      state: .case(.started)
    ),
    docker: emptyDocker(),
    info: Mock<TowerAPITestMocks.Info>(
      cpu: Mock<TowerAPITestMocks.InfoCpu>(brand: "Example 8-Core CPU", cores: 8, threads: 16),
      os: Mock<TowerAPITestMocks.InfoOs>(
        distro: "Unraid OS",
        release: "7.3.0",
        uptime: "2026-01-01T00:00:00.250Z"
      )
    ),
    metrics: Mock<TowerAPITestMocks.Metrics>(
      cpu: Mock<TowerAPITestMocks.CpuUtilization>(percentTotal: 5.5),
      memory: Mock<TowerAPITestMocks.MemoryUtilization>(percentTotal: 60.0, total: 2000, used: 1000)
    ),
    shares: [],
    vms: emptyVms()
  )

  let snapshot = await dashboardSnapshot(from: mock)

  #expect(snapshot.array.state == "STARTED")
  #expect(snapshot.array.isStarted)
  // Assert the actual parsed value, not merely non-nil: a regression that
  // truncates to Int32, swaps free/used/total, or drops precision would
  // still pass a `!= nil` check.
  #expect(snapshot.array.capacity?.free == 24_000_000_000)
  #expect(snapshot.array.capacity?.used == 72_000_000_000)
  #expect(snapshot.array.capacity?.total == 96_000_000_000)
  #expect(snapshot.array.system?.release == "7.3.0")
  #expect(snapshot.array.system?.cpuBrand == "Example 8-Core CPU")
  #expect(snapshot.array.system?.cpuCores == 8)
  #expect(snapshot.array.system?.cpuPercent == 5.5)
  #expect(snapshot.array.system?.memoryPercent == 60.0)
}

@Test func capacityStringsThatDoNotParseBecomeNilNotZero() async throws {
  let mock = Mock<TowerAPITestMocks.Query>(
    array: Mock<TowerAPITestMocks.UnraidArray>(
      capacity: capacity(free: "x", total: "z", used: "y"),
      parityCheckStatus: neverRunParityCheck(),
      state: .case(.stopped)
    ),
    docker: emptyDocker(),
    info: emptyInfo(),
    metrics: emptyMetrics(),
    shares: [],
    vms: emptyVms()
  )

  let snapshot = await dashboardSnapshot(from: mock)

  // A regression that defaults an unparseable capacity to
  // `ArrayCapacity(free: 0, used: 0, total: 0)` instead of `nil` would
  // render a healthy array as 0% used — a distinct, worse symptom than
  // "capacity unavailable". `capacity == nil` is itself the complete proof:
  // a `nil` optional and a zero-valued `ArrayCapacity` are different values,
  // so there is no additional property to check once this holds.
  #expect(snapshot.array.capacity == nil)
  #expect(snapshot.array.state == "STOPPED")
}

@Test func mapsDisksPreservingTemperatureAndHealth() async throws {
  let disk = Mock<TowerAPITestMocks.ArrayDisk>(
    device: "sdb",
    fsFree: 1000,
    fsSize: 4000,
    fsUsed: 3000,
    id: "d1",
    name: "disk1",
    status: .case(.diskOk),
    temp: 36,
    type: .case(.data)
  )
  let mock = Mock<TowerAPITestMocks.Query>(
    array: Mock<TowerAPITestMocks.UnraidArray>(
      capacity: capacity(free: "0", total: "0", used: "0"),
      disks: [disk],
      parityCheckStatus: neverRunParityCheck(),
      state: .case(.started)
    ),
    docker: emptyDocker(),
    info: emptyInfo(),
    metrics: emptyMetrics(),
    shares: [],
    vms: emptyVms()
  )

  let mapped = try #require(await dashboardSnapshot(from: mock).array.disks.first)

  #expect(mapped.id == "d1")
  #expect(mapped.displayName == "disk1")
  // `displayName` prefers `name` over `device`, so a swap of those two
  // fields at the mapping site would be invisible without asserting
  // `device` directly. Assert `type` by value for the same reason.
  #expect(mapped.device == "sdb")
  #expect(mapped.type == "DATA")
  #expect(mapped.temp == 36)
  #expect(mapped.isHealthy)
  let fraction = try #require(mapped.usedFraction)
  #expect(abs(fraction - 0.75) < 0.001)
}

@Test func mapsParitiesAndCachesFromTheirOwnDistinctGeneratedTypes() async throws {
  // `parities` and `caches` are selected through `Array.Parity` and
  // `Array.Cach`, generated types distinct from `Array.Disk`, even though all
  // three select the same fields and map to the same `ArrayDisk` domain
  // struct. A mapping that dropped or crossed fields for one of the other two
  // selections would be invisible if only `disks` were exercised.
  let parityDisk = Mock<TowerAPITestMocks.ArrayDisk>(
    id: "p1", name: "parity1", status: .case(.diskOk), temp: 30, type: .case(.parity)
  )
  let cacheDisk = Mock<TowerAPITestMocks.ArrayDisk>(
    fsFree: 500, fsSize: 2000, fsUsed: 1500,
    id: "c1", name: "cache1", status: .case(.diskOk), temp: 40, type: .case(.cache)
  )
  let mock = Mock<TowerAPITestMocks.Query>(
    array: Mock<TowerAPITestMocks.UnraidArray>(
      caches: [cacheDisk],
      capacity: capacity(free: "0", total: "0", used: "0"),
      parities: [parityDisk],
      parityCheckStatus: neverRunParityCheck(),
      state: .case(.started)
    ),
    docker: emptyDocker(),
    info: emptyInfo(),
    metrics: emptyMetrics(),
    shares: [],
    vms: emptyVms()
  )

  let snapshot = await dashboardSnapshot(from: mock)

  let parity = try #require(snapshot.array.parities.first)
  #expect(parity.id == "p1")
  #expect(parity.displayName == "parity1")
  #expect(parity.temp == 30)
  #expect(parity.isHealthy)
  #expect(parity.type == "PARITY")
  // Parity carries no fs* data on the wire and the mock sets none, so a
  // mapping that filled them from another disk would show here as non-nil.
  #expect(parity.fsFree == nil)
  #expect(parity.fsUsed == nil)
  #expect(parity.fsSize == nil)

  let cache = try #require(snapshot.array.caches.first)
  #expect(cache.id == "c1")
  #expect(cache.displayName == "cache1")
  #expect(cache.temp == 40)
  #expect(cache.type == "CACHE")
  let fraction = try #require(cache.usedFraction)
  #expect(abs(fraction - 0.75) < 0.001)
}
