import ApolloTestSupport
import Testing
@testable import TowerAPI
import TowerAPITestMocks
@testable import TowerData
import TowerCore

// These tests exercise `Share.init(from:)`, the Apollo → domain mapping behind
// `LiveShareRepository.shares()`. The repository's own guards and sort order are
// covered in `ShareRepositoryStubTests.swift` against the real `shares()`.
//
// `DomainShare` rather than `Share`: this file imports both `TowerCore` and
// `TowerAPITestMocks`, each of which exports a `Share`. See
// `DomainAliases.swift` for why `TowerCore.Share` doesn't disambiguate it.
//
// See `DashboardMappingTests.swift` for the canonical writeup of the Apollo
// `Mock<O>` crash: every entity-typed mock field below is
// constructed explicitly rather than left to a cross-module default argument.

private func makeQuery(shares: [Mock<TowerAPITestMocks.Share>]) -> Mock<TowerAPITestMocks.Query> {
  Mock<TowerAPITestMocks.Query>(
    array: Mock<TowerAPITestMocks.UnraidArray>(
      capacity: Mock<TowerAPITestMocks.ArrayCapacity>(
        kilobytes: Mock<TowerAPITestMocks.Capacity>(free: "0", total: "0", used: "0")
      ),
      parityCheckStatus: Mock<TowerAPITestMocks.ParityCheck>(status: .case(.neverRun)),
      state: .case(.started)
    ),
    docker: Mock<TowerAPITestMocks.Docker>(containers: []),
    info: Mock<TowerAPITestMocks.Info>(
      cpu: Mock<TowerAPITestMocks.InfoCpu>(),
      os: Mock<TowerAPITestMocks.InfoOs>()
    ),
    metrics: Mock<TowerAPITestMocks.Metrics>(),
    shares: shares,
    vms: Mock<TowerAPITestMocks.Vms>(domains: [])
  )
}

private func shareMock(
  allocator: String? = "highwater",
  cache: Bool? = nil,
  comment: String? = nil,
  cow: String? = "auto",
  exclude: [String]? = [],
  floor: String? = "0",
  free: TowerAPI.BigInt? = 1,
  id: TowerAPI.PrefixedID = "hash:share",
  include: [String]? = [],
  name: String? = "share",
  nameOrig: String? = nil,
  splitLevel: String? = nil,
  used: TowerAPI.BigInt? = 1
) -> Mock<TowerAPITestMocks.Share> {
  Mock<TowerAPITestMocks.Share>(
    allocator: allocator, cache: cache, comment: comment, cow: cow, exclude: exclude,
    floor: floor, free: free, id: id, include: include, name: name, nameOrig: nameOrig,
    splitLevel: splitLevel, used: used
  )
}

private func mapOne(_ share: Mock<TowerAPITestMocks.Share>) async throws -> DomainShare {
  let data = await SharesQuery.Data.from(makeQuery(shares: [share]))
  return try #require(data.shares.map(DomainShare.init(from:)).first)
}

@Test func mapsIdentityAndConfiguration() async throws {
  let share = try await mapOne(
    shareMock(
      allocator: "highwater", comment: "saved VM instances", cow: "no",
      floor: "500000000", id: "hash:domains", name: "domains", splitLevel: "1"
    )
  )

  #expect(share.id == "hash:domains")
  #expect(share.displayName == "domains")
  #expect(share.comment == "saved VM instances")
  #expect(share.allocator == "highwater")
  #expect(share.splitLevel == "1")
  #expect(share.copyOnWrite == "no")
  #expect(share.floorKilobytes == 500_000_000)
}

@Test func mapsPoolFiguresIntoPoolNamedFields() async throws {
  // The pool-named fields are what stop pool usage reading as per-share usage,
  // so they get an assertion of their own: whatever `used`/`free` are called
  // on the wire, nothing downstream can read them as per-share numbers.
  let share = try await mapOne(shareMock(free: 588_000_000, used: 412_000_000))

  #expect(share.poolUsedKilobytes == 412_000_000)
  #expect(share.poolFreeKilobytes == 588_000_000)
}

@Test func mapsEveryEmptyStringToNilSoNoBlankRowsRender() async throws {
  // Unraid sends `""` for absent strings on shares that have none — most shares
  // have an empty comment and an empty split level. A `""`
  // that reaches the UI renders as a labelled row with nothing after it.
  let share = try await mapOne(
    shareMock(allocator: "", comment: "", cow: "", floor: "", name: "", nameOrig: "", splitLevel: "")
  )

  #expect(share.name == nil)
  #expect(share.comment == nil)
  #expect(share.allocator == nil)
  #expect(share.copyOnWrite == nil)
  #expect(share.splitLevel == nil)
  #expect(share.originalName == nil)
  #expect(share.floorKilobytes == nil)
}

@Test func dropsAnOriginalNameThatMatchesTheCurrentOne() async throws {
  // When Unraid sends the same value for both, a row reading "Original Name:
  // appdata" directly under a title reading "appdata" is chrome, not
  // information.
  let share = try await mapOne(shareMock(id: "hash:appdata", name: "appdata", nameOrig: "appdata"))

  #expect(share.originalName == nil)
}

@Test func keepsAnOriginalNameThatDiffers() async throws {
  // The case the field is actually for: a renamed share.
  let share = try await mapOne(shareMock(name: "media", nameOrig: "Media"))

  #expect(share.originalName == "Media")
}

@Test func anUnparseableFloorBecomesNilRatherThanZero() async throws {
  // `0` is a real floor ("no minimum"), so degrading a bad value to `0` would
  // turn "Tower couldn't read this" into a specific, wrong claim.
  let unparseable = try await mapOne(shareMock(floor: "not a number"))
  let zero = try await mapOne(shareMock(floor: "0"))

  #expect(unparseable.floorKilobytes == nil)
  #expect(zero.floorKilobytes == 0)
}

@Test func nilDiskListsBecomeEmptyBecauseBothMeanNoDisksNamed() async throws {
  // Unlike `vms.domains`, where nil-versus-empty is the whole point: for
  // `include`/`exclude` a null and an empty list make the same statement, and
  // `usesAllDisks` is what the UI actually asks.
  let share = try await mapOne(shareMock(exclude: nil, include: nil))

  #expect(share.includedDisks.isEmpty)
  #expect(share.excludedDisks.isEmpty)
  #expect(share.usesAllDisks)
}

@Test func mapsNamedDisksThrough() async throws {
  let share = try await mapOne(shareMock(exclude: ["disk3"], include: ["disk1", "disk2"]))

  #expect(share.includedDisks == ["disk1", "disk2"])
  #expect(share.excludedDisks == ["disk3"])
  #expect(!share.usesAllDisks)
}

@Test func aNilCacheFlagStaysNilRatherThanBecomingFalse() async throws {
  // Unraid 7.3 leaves `cache` unset. `false` would render as "not cached",
  // which is a claim about the share's configuration that Tower has no basis
  // for.
  let notReported = try await mapOne(shareMock(cache: nil))
  let cached = try await mapOne(shareMock(cache: true))
  let notCached = try await mapOne(shareMock(cache: false))

  #expect(notReported.isCached == nil)
  #expect(cached.isCached == true)
  #expect(notCached.isCached == false)
}
