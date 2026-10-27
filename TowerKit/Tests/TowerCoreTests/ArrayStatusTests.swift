import Testing
@testable import TowerCore

@Test func usedPercentIsComputedFromCapacity() {
  let capacity = ArrayCapacity(free: 24_000_000_000, used: 72_000_000_000, total: 96_000_000_000)
  #expect(abs(capacity.usedFraction - 0.75) < 0.01)
}

@Test func usedPercentIsZeroWhenTotalIsZero() {
  #expect(ArrayCapacity(free: 0, used: 0, total: 0).usedFraction == 0)
}

@Test func usedFractionClampsAboveOneAndBelowZero() {
  // A disk reporting used > size would otherwise drive a ProgressView past
  // its bounds; Unraid has been seen to report transient inconsistencies.
  #expect(ArrayCapacity(free: 0, used: 500, total: 100).usedFraction == 1)
  #expect(ArrayCapacity(free: 0, used: -50, total: 100).usedFraction == 0)
}

@Test func diskUsedFractionIsNilWhenMissingOrZeroSized() throws {
  #expect(ArrayDisk.stub(fsUsed: nil, fsSize: nil).usedFraction == nil)
  #expect(ArrayDisk.stub(fsUsed: 100, fsSize: 0).usedFraction == nil)
  let fraction = try #require(ArrayDisk.stub(fsUsed: 3_000, fsSize: 4_000).usedFraction)
  #expect(abs(fraction - 0.75) < 0.001)
}

/// The hazard: a disk mid-format, or one whose filesystem is
/// mounted but not yet sampled, reports `fsSize` without `fsUsed`.
/// `usedFraction` must not collapse that into a fabricated `0` — it has to
/// come back `nil` even though `fsSize` alone is present.
@Test func diskUsedFractionIsNilWhenSizeIsPresentButUsedIsNot() {
  #expect(ArrayDisk.stub(fsUsed: nil, fsSize: 4_000).usedFraction == nil)
}

@Test func diskIsHealthyOnlyWhenStatusIsDiskOK() {
  #expect(ArrayDisk.stub(status: "DISK_OK").isHealthy)
  #expect(!ArrayDisk.stub(status: "DISK_DSBL").isHealthy)
}

/// Lives in `TowerCore`, not `DiskDetailView`, so `DiskListCard`'s
/// row can share the exact same humanising rule rather than reimplementing
/// it — this is the one place it's unit-tested.
@Test func statusTextStripsDiskPrefixAndJoinsUnderscoresWithSpaces() {
  #expect(ArrayDisk.stub(status: "DISK_OK").statusText == "OK")
  #expect(ArrayDisk.stub(status: "DISK_DSBL").statusText == "DSBL")
  #expect(ArrayDisk.stub(status: "DISK_NP_MISSING").statusText == "NP MISSING")
}

@Test func statusTextIsNilWhenStatusIsNil() {
  #expect(ArrayDisk.stub(status: nil).statusText == nil)
}

/// A raw value with no `DISK_` prefix at all should still humanise rather
/// than crash or pass through untouched — `dropFirst(5)` is guarded by
/// `hasPrefix`, not assumed.
@Test func statusTextHandlesAValueWithNoDiskPrefix() {
  #expect(ArrayDisk.stub(status: "UNKNOWN").statusText == "UNKNOWN")
}

@Test func arrayIsStartedOnlyForStartedState() {
  #expect(ArrayStatus.stub(state: "STARTED").isStarted)
  #expect(!ArrayStatus.stub(state: "STOPPED").isStarted)
}

@Test func displayNameFallsBackFromNameToDeviceToID() {
  #expect(ArrayDisk.stub(id: "a", name: "disk1", device: "sdb").displayName == "disk1")
  #expect(ArrayDisk.stub(id: "a", name: nil, device: "sdb").displayName == "sdb")
  #expect(ArrayDisk.stub(id: "a", name: nil, device: nil).displayName == "a")
}

/// Backs the identifier-based disk detail navigation:
/// the destination doesn't know which group its `ArrayDisk.ID` came from, so
/// the lookup has to search all three regardless of where the id lives.
@Test func diskLookupFindsAnIDInAnyOfTheThreeGroups() {
  let data = ArrayDisk.stub(id: "data1")
  let parity = ArrayDisk.stub(id: "parity1")
  let cache = ArrayDisk.stub(id: "cache1")
  let array = ArrayStatus.stub(disks: [data], parities: [parity], caches: [cache])

  #expect(array.disk(id: "data1") == data)
  #expect(array.disk(id: "parity1") == parity)
  #expect(array.disk(id: "cache1") == cache)
}

/// The other half of the same lookup: a disk that has dropped out of the
/// array (or never existed) must come back `nil`, not crash — this is what
/// `DiskDetailView`'s not-found `ContentUnavailableView` branch is keyed on.
@Test func diskLookupIsNilWhenIDMatchesNothing() {
  let array = ArrayStatus.stub(disks: [.stub(id: "data1")])
  #expect(array.disk(id: "missing") == nil)
}

extension ArrayDisk {
  static func stub(
    id: String = "disk1", idx: Int? = nil, name: String? = "disk1", device: String? = "sdb",
    status: String? = "DISK_OK", temp: Int? = 36, size: Int64? = nil, fsFree: Int64? = 1_000,
    fsUsed: Int64? = 3_000, fsSize: Int64? = 4_000, fsType: String? = nil,
    rotational: Bool? = nil, numReads: Int64? = nil, numWrites: Int64? = nil,
    numErrors: Int64? = nil, type: String? = "DATA"
  ) -> ArrayDisk {
    ArrayDisk(id: id, idx: idx, name: name, device: device, status: status, temp: temp,
              size: size, fsFree: fsFree, fsUsed: fsUsed, fsSize: fsSize, fsType: fsType,
              rotational: rotational, numReads: numReads, numWrites: numWrites,
              numErrors: numErrors, type: type)
  }
}

extension ArrayStatus {
  static func stub(
    state: String = "STARTED", capacity: ArrayCapacity? = nil,
    disks: [ArrayDisk] = [], parities: [ArrayDisk] = [],
    caches: [ArrayDisk] = [], system: SystemInfo? = nil
  ) -> ArrayStatus {
    ArrayStatus(state: state, capacity: capacity, disks: disks,
                parities: parities, caches: caches, system: system)
  }
}
