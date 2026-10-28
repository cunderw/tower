import ApolloTestSupport
import Testing
@testable import TowerAPI
import TowerAPITestMocks
@testable import TowerData
import TowerCore

// These tests exercise `DashboardSnapshot.init(from:)`, the Apollo → domain
// mapping behind `LiveSystemRepository.dashboard()`. See
// `SystemRepositoryTests.swift` for why these two files split the mapping
// coverage, and for the fuller explanation of why Apollo's generated
// `Mock<O>` graph (via `RootSelectionSet.from(_:)`) is used here instead of
// hand-built domain structs.
//
// IMPORTANT — Apollo `Mock<O>` crash (this is the canonical
// writeup; `SystemRepositoryTests.swift` points here rather than repeating
// it — if you're adding a new fixture-building test file, put the same
// pointer there instead of a third copy of this comment): omitting an
// entity-typed parameter of a generated `Mock<O>` and letting its declared
// default (`Mock<O>()`) fire reproducibly crashes at runtime with "Fatal
// error: ... expected DataDict for entity, got Optional<Hashable>" under
// Xcode 26.6 / Swift 6.3.3 with apollo-ios 2.3.0 — a cross-module
// default-argument evaluation bug, not a defect in our code.
// The fix is always to construct entity-typed mock fields explicitly, as
// the helpers below do.
//
// The bug is broader than that single-entity case: omitting `Docker`'s own
// `containers: [Mock<DockerContainer>] = []` argument (i.e. constructing
// bare `Mock<Docker>()`) reproduces it too, as a *different* fatal error
// ("expected list of data for entity") — even though the structurally
// identical `UnraidArray.disks`/`.parities`/`.caches: [Mock<ArrayDisk>] = []`
// and `Vms.domains: [Mock<VmDomain>]? = nil` are safe to omit on that
// toolchain. The bug is evidently per-generated-type, not a rule derivable
// from a field's shape alone — so
// every `Docker` mock in this file passes `containers:` explicitly, and as
// a matter of local policy every other entity-typed field below (single or
// list) does too, rather than trusting which specific omissions happen to
// be safe on this apollo-ios version.

/// An explicit (not defaulted) empty `Info`, safe from the cross-module
/// default-argument bug described above.
private func emptyInfo() -> Mock<TowerAPITestMocks.Info> {
  Mock<TowerAPITestMocks.Info>(
    cpu: Mock<TowerAPITestMocks.InfoCpu>(),
    os: Mock<TowerAPITestMocks.InfoOs>()
  )
}

/// An explicit (not defaulted) empty `Metrics`. `Metrics.cpu`/`.memory`
/// themselves default to a literal `nil` (they're genuinely nullable in the
/// schema), so no further explicit nesting is required here.
private func emptyMetrics() -> Mock<TowerAPITestMocks.Metrics> {
  Mock<TowerAPITestMocks.Metrics>()
}

/// An explicit (not defaulted) empty `Docker`. `containers:` must be passed
/// explicitly here — see the file-level comment above.
private func emptyDocker() -> Mock<TowerAPITestMocks.Docker> {
  Mock<TowerAPITestMocks.Docker>(containers: [])
}

/// An explicit (not defaulted) empty `Vms`.
private func emptyVms() -> Mock<TowerAPITestMocks.Vms> {
  Mock<TowerAPITestMocks.Vms>(domains: [])
}

/// An explicit (not defaulted) `ArrayCapacity` wrapping the given kilobyte
/// strings.
private func capacity(free: String, total: String, used: String) -> Mock<TowerAPITestMocks.ArrayCapacity> {
  Mock<TowerAPITestMocks.ArrayCapacity>(
    kilobytes: Mock<TowerAPITestMocks.Capacity>(free: free, total: total, used: used)
  )
}

private func zeroCapacity() -> Mock<TowerAPITestMocks.ArrayCapacity> {
  capacity(free: "0", total: "0", used: "0")
}

/// An explicit (not defaulted) `ParityCheck` reporting an idle, never-run
/// server — the safe baseline for tests that don't care about parity.
private func neverRunParityCheck() -> Mock<TowerAPITestMocks.ParityCheck> {
  Mock<TowerAPITestMocks.ParityCheck>(status: .case(.neverRun))
}

/// An explicit (not defaulted) `UnraidArray` with a zeroed capacity and an
/// idle parity check — the safe baseline for tests that don't care about
/// the array itself.
private func emptyArray() -> Mock<TowerAPITestMocks.UnraidArray> {
  Mock<TowerAPITestMocks.UnraidArray>(
    capacity: zeroCapacity(),
    parityCheckStatus: neverRunParityCheck(),
    state: .case(.started)
  )
}

/// Assembles the full `Query` mock from already-explicit pieces. Every
/// parameter is required (no defaults) so this function can never itself
/// become a source of the cross-module default-argument bug described
/// above — callers build every argument via one of the explicit helpers
/// above, or inline, at their own call site.
private func makeQuery(
  array: Mock<TowerAPITestMocks.UnraidArray>,
  docker: Mock<TowerAPITestMocks.Docker>,
  info: Mock<TowerAPITestMocks.Info>,
  metrics: Mock<TowerAPITestMocks.Metrics>,
  shares: [Mock<TowerAPITestMocks.Share>],
  vms: Mock<TowerAPITestMocks.Vms>
) -> Mock<TowerAPITestMocks.Query> {
  Mock<TowerAPITestMocks.Query>(
    array: array, docker: docker, info: info, metrics: metrics, shares: shares, vms: vms
  )
}

/// Maps `mock` the way `LiveSystemRepository.dashboard()` does: the core
/// query and both counts queries each read their own selection of the one
/// `Query` mock, and the three results compose into one snapshot.
/// `SystemRepositoryTests.swift` uses it too.
///
/// That is why every mock here still passes `docker:` and `vms:`, although
/// the core `DashboardQuery` no longer selects either: the counts queries
/// read them, and omitting an entity argument is the crash described above.
func dashboardSnapshot(from mock: Mock<TowerAPITestMocks.Query>) async -> DashboardSnapshot {
  let core = await DashboardQuery.Data.from(mock)
  let containers = await DashboardContainersQuery.Data.from(mock)
  let vms = await DashboardVMsQuery.Data.from(mock)
  return DashboardSnapshot(from: core, containers: containers.containerCounts, vms: vms.vmCounts)
}

@Test func mapsContainerAndVMCountsFromStates() async throws {
  let mock = makeQuery(
    array: emptyArray(),
    docker: Mock<TowerAPITestMocks.Docker>(containers: [
      Mock<TowerAPITestMocks.DockerContainer>(state: .case(.running)),
      Mock<TowerAPITestMocks.DockerContainer>(state: .case(.running)),
      Mock<TowerAPITestMocks.DockerContainer>(state: .case(.exited)),
    ]),
    info: emptyInfo(),
    metrics: emptyMetrics(),
    shares: [],
    vms: Mock<TowerAPITestMocks.Vms>(domains: [
      Mock<TowerAPITestMocks.VmDomain>(state: .case(.running)),
      Mock<TowerAPITestMocks.VmDomain>(state: .case(.shutoff)),
    ])
  )

  let snapshot = await dashboardSnapshot(from: mock)

  // 2 of 3 containers RUNNING, 1 of 2 VMs RUNNING — asserted against
  // fixtures where the running count is strictly less than the total, so a
  // regression that reports the total instead of the running count would
  // be caught.
  #expect(snapshot.services.containersRunning == 2)
  #expect(snapshot.services.containersTotal == 3)
  #expect(snapshot.services.vmsRunning == 1)
  #expect(snapshot.services.vmsTotal == 2)
}

@Test func treatsNilVMDomainsAsUnavailableNotZero() async throws {
  // `vms.domains` is a nullable list in the schema (`domains: [VmDomain!]`,
  // not `[VmDomain!]!`) — null means VM reporting is unavailable (libvirt
  // stopped or errored), not "zero VMs configured". Collapsing it to `0`/`0`
  // would be indistinguishable from a healthy, VM-less server, and
  // `mapsEmptyVMDomainsAsGenuineZero` below proves the two inputs produce
  // different results.
  let mock = makeQuery(
    array: emptyArray(),
    docker: emptyDocker(),
    info: emptyInfo(),
    metrics: emptyMetrics(),
    shares: [],
    vms: Mock<TowerAPITestMocks.Vms>(domains: nil)
  )

  let snapshot = await dashboardSnapshot(from: mock)

  #expect(snapshot.services.vmsRunning == nil)
  #expect(snapshot.services.vmsTotal == nil)
  #expect(snapshot.services.vmsSummary == "Unavailable")
}

/// The other half of that distinction: an explicit empty
/// list (a healthy server that simply has no VMs defined) must map to real
/// `0`/`0` counts, not the `nil`/`nil` "unavailable" reading the test above
/// asserts for a genuinely absent `domains`.
@Test func mapsEmptyVMDomainsAsGenuineZero() async throws {
  let mock = makeQuery(
    array: emptyArray(),
    docker: emptyDocker(),
    info: emptyInfo(),
    metrics: emptyMetrics(),
    shares: [],
    vms: emptyVms()
  )

  let snapshot = await dashboardSnapshot(from: mock)

  #expect(snapshot.services.vmsRunning == 0)
  #expect(snapshot.services.vmsTotal == 0)
  #expect(snapshot.services.vmsSummary == "0 of 0 running")
}

@Test func mapsSharesTotalAsRawShareCount() async throws {
  // `sharesTotal` is a plain count of `shares`, nothing more. `share.used`
  // (and `share.free`) are deliberately never aggregated: they report the
  // used/free space of the storage *pool* a share resides on, not the share
  // itself, so every share on the same pool returns a byte-identical value
  // and summing across shares multiplies each pool's total by its share
  // count, which can produce a "usage" figure several times the array's
  // size. See `ServiceCounts.init(from:)`.
  let mock = makeQuery(
    array: emptyArray(),
    docker: emptyDocker(),
    info: emptyInfo(),
    metrics: emptyMetrics(),
    shares: [
      Mock<TowerAPITestMocks.Share>(id: "s1"),
      Mock<TowerAPITestMocks.Share>(id: "s2"),
      Mock<TowerAPITestMocks.Share>(id: "s3"),
    ],
    vms: emptyVms()
  )

  let snapshot = await dashboardSnapshot(from: mock)

  #expect(snapshot.services.sharesTotal == 3)
}

@Test func mapsParityStatusFromAnIdleServer() async throws {
  // Unraid's idle shape: status COMPLETED with errors null.
  // `running`/`paused` are deliberately unselected — `isActive`
  // derives from `status` alone, never from these — so they're not part of
  // this fixture at all.
  let mock = makeQuery(
    array: Mock<TowerAPITestMocks.UnraidArray>(
      capacity: zeroCapacity(),
      parityCheckStatus: Mock<TowerAPITestMocks.ParityCheck>(
        errors: nil, status: .case(.completed)
      ),
      state: .case(.started)
    ),
    docker: emptyDocker(),
    info: emptyInfo(),
    metrics: emptyMetrics(),
    shares: [],
    vms: emptyVms()
  )

  let snapshot = await dashboardSnapshot(from: mock)

  #expect(snapshot.parity.state == .completed)
  #expect(!snapshot.parity.isActive)
  #expect(snapshot.parity.errors == nil)
}

@Test func mapsParityStatusFromARunningCheck() async throws {
  let mock = makeQuery(
    array: Mock<TowerAPITestMocks.UnraidArray>(
      capacity: zeroCapacity(),
      parityCheckStatus: Mock<TowerAPITestMocks.ParityCheck>(
        correcting: true, progress: 42, status: .case(.running)
      ),
      state: .case(.started)
    ),
    docker: emptyDocker(),
    info: emptyInfo(),
    metrics: emptyMetrics(),
    shares: [],
    vms: emptyVms()
  )

  let snapshot = await dashboardSnapshot(from: mock)

  #expect(snapshot.parity.state == .running)
  #expect(snapshot.parity.isActive)
  #expect(snapshot.parity.progressFraction == 0.42)
  #expect(snapshot.parity.correcting)
}

@Test func mapsDiskIOAndFilesystemFields() async throws {
  let disk = Mock<TowerAPITestMocks.ArrayDisk>(
    fsFree: 1_000, fsSize: 4_000, fsType: "xfs", fsUsed: 3_000,
    id: "d1", idx: 3, name: "disk1", numErrors: 2, numReads: 123_456,
    numWrites: 7_890, rotational: false, status: .case(.diskOk), temp: 36,
    type: .case(.data)
  )
  let mock = makeQuery(
    array: Mock<TowerAPITestMocks.UnraidArray>(
      capacity: zeroCapacity(), disks: [disk],
      parityCheckStatus: neverRunParityCheck(), state: .case(.started)
    ),
    docker: emptyDocker(),
    info: emptyInfo(),
    metrics: emptyMetrics(),
    shares: [],
    vms: emptyVms()
  )

  let snapshot = await dashboardSnapshot(from: mock)
  let mapped = try #require(snapshot.array.disks.first)

  #expect(mapped.fsType == "xfs")
  #expect(mapped.rotational == false)
  #expect(mapped.numReads == 123_456)
  #expect(mapped.numWrites == 7_890)
  #expect(mapped.numErrors == 2)
}

@Test func mapsParityDeviceAndIOFieldsButLeavesFilesystemNil() async throws {
  // Unraid's parity disks report `device`, `rotational`, and IO counters, so
  // `Dashboard.graphql` selects them for `parities` too; leaving them out
  // hides real data. Only the
  // filesystem-size fields are genuinely null for parity, since parity
  // disks carry no filesystem.
  let parity = Mock<TowerAPITestMocks.ArrayDisk>(
    device: "sde", fsFree: nil, fsSize: nil, fsType: nil, fsUsed: nil,
    id: "p1", idx: 0, name: "parity", numErrors: 0, numReads: 0,
    numWrites: 0, rotational: true, status: .case(.diskOk), temp: 37,
    type: .case(.parity)
  )
  let mock = makeQuery(
    array: Mock<TowerAPITestMocks.UnraidArray>(
      capacity: zeroCapacity(), parities: [parity],
      parityCheckStatus: neverRunParityCheck(), state: .case(.started)
    ),
    docker: emptyDocker(),
    info: emptyInfo(),
    metrics: emptyMetrics(),
    shares: [],
    vms: emptyVms()
  )

  let snapshot = await dashboardSnapshot(from: mock)
  let mapped = try #require(snapshot.array.parities.first)

  #expect(mapped.device == "sde")
  #expect(mapped.rotational == true)
  #expect(mapped.numReads == 0)
  #expect(mapped.numWrites == 0)
  #expect(mapped.numErrors == 0)
  #expect(mapped.fsFree == nil)
  #expect(mapped.fsUsed == nil)
  #expect(mapped.fsSize == nil)
  #expect(mapped.fsType == nil)
}

@Test func mapsCacheDeviceAndFilesystemFields() async throws {
  // `caches` carries both `device` and the filesystem fields — unlike
  // parity, a cache disk genuinely has a filesystem.
  let cache = Mock<TowerAPITestMocks.ArrayDisk>(
    device: "nvme0n1", fsFree: 500, fsSize: 1_000_000_000, fsType: "xfs",
    fsUsed: 400, id: "c1", idx: 30, name: "cache", numErrors: 0,
    numReads: 0, numWrites: 0, rotational: false, status: .case(.diskOk),
    temp: 30, type: .case(.cache)
  )
  let mock = makeQuery(
    array: Mock<TowerAPITestMocks.UnraidArray>(
      caches: [cache], capacity: zeroCapacity(),
      parityCheckStatus: neverRunParityCheck(), state: .case(.started)
    ),
    docker: emptyDocker(),
    info: emptyInfo(),
    metrics: emptyMetrics(),
    shares: [],
    vms: emptyVms()
  )

  let snapshot = await dashboardSnapshot(from: mock)
  let mapped = try #require(snapshot.array.caches.first)

  #expect(mapped.device == "nvme0n1")
  #expect(mapped.rotational == false)
  #expect(mapped.fsType == "xfs")
  #expect(mapped.fsFree == 500)
  #expect(mapped.fsUsed == 400)
  #expect(mapped.fsSize == 1_000_000_000)
}

@Test func mapsMemoryBytesFromMetrics() async throws {
  let mock = makeQuery(
    array: emptyArray(),
    docker: emptyDocker(),
    info: emptyInfo(),
    metrics: Mock<TowerAPITestMocks.Metrics>(
      cpu: Mock<TowerAPITestMocks.CpuUtilization>(percentTotal: 5.5),
      memory: Mock<TowerAPITestMocks.MemoryUtilization>(
        percentTotal: 60.0, total: 34_359_738_368, used: 12_884_901_888
      )
    ),
    shares: [],
    vms: emptyVms()
  )

  let snapshot = await dashboardSnapshot(from: mock)

  #expect(snapshot.array.system?.memoryUsedBytes == 12_884_901_888)
  #expect(snapshot.array.system?.memoryTotalBytes == 34_359_738_368)
  // Unchanged sibling field, to prove `used`/`total` land alongside
  // `percentTotal` rather than replacing it.
  #expect(snapshot.array.system?.memoryPercent == 60.0)
}

@Test func sortsDisksByIdxRegardlessOfWireOrder() async throws {
  // All three of `disks`/`parities`/`caches` get the same sort-by-`idx`
  // transform in the mapping code — proven independently here so a
  // regression that sorted only `disks` (or reordered the other two by
  // wire order) would be caught, not just the one array.
  let mock = makeQuery(
    array: Mock<TowerAPITestMocks.UnraidArray>(
      caches: [
        Mock<TowerAPITestMocks.ArrayDisk>(id: "c-high", idx: 31, type: .case(.cache)),
        Mock<TowerAPITestMocks.ArrayDisk>(id: "c-low", idx: 30, type: .case(.cache)),
      ],
      capacity: zeroCapacity(),
      disks: [
        Mock<TowerAPITestMocks.ArrayDisk>(id: "d-high", idx: 5, type: .case(.data)),
        Mock<TowerAPITestMocks.ArrayDisk>(id: "d-low", idx: 1, type: .case(.data)),
      ],
      parities: [
        Mock<TowerAPITestMocks.ArrayDisk>(id: "p-high", idx: 29, type: .case(.parity)),
        Mock<TowerAPITestMocks.ArrayDisk>(id: "p-low", idx: 0, type: .case(.parity)),
      ],
      parityCheckStatus: neverRunParityCheck(), state: .case(.started)
    ),
    docker: emptyDocker(),
    info: emptyInfo(),
    metrics: emptyMetrics(),
    shares: [],
    vms: emptyVms()
  )

  let snapshot = await dashboardSnapshot(from: mock)

  #expect(snapshot.array.disks.map(\.id) == ["d-low", "d-high"])
  // `p-low`'s `idx` is `0` — Parity1's real slot, not a sentinel — so this
  // also proves a legitimate `idx` of `0` sorts to the front rather than
  // being confused with "unknown".
  #expect(snapshot.array.parities.map(\.id) == ["p-low", "p-high"])
  #expect(snapshot.array.caches.map(\.id) == ["c-low", "c-high"])
}
