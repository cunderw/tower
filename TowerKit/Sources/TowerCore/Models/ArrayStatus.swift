import Foundation

public struct ArrayCapacity: Equatable, Sendable {
  public let free: Int64
  public let used: Int64
  public let total: Int64

  public init(free: Int64, used: Int64, total: Int64) {
    self.free = free
    self.used = used
    self.total = total
  }

  public var usedFraction: Double {
    guard total > 0 else { return 0 }
    return min(1, max(0, Double(used) / Double(total)))
  }
}

// `Hashable` is a plain synthesis — every stored property below is
// already `Hashable`. Nothing in the app requires it (the dashboard's disk
// rows push `ArrayDisk.ID`, never the disk); it stays as public API.
public struct ArrayDisk: Identifiable, Equatable, Hashable, Sendable {
  public let id: String
  /// Array slot. Parity1 is 0, Parity2 is 29, data disks 1-28, caches 30-53.
  /// Used only for stable display ordering.
  ///
  /// **Optional on purpose.** `0` is Parity1's real slot, not a safe
  /// sentinel, so a query that does not select `idx` must be able to say
  /// "unknown" rather than alias every disk onto a valid slot number.
  /// Sort with `($0.idx ?? .max) < ($1.idx ?? .max)` so unknowns sink to
  /// the end instead of jumping to the front.
  public let idx: Int?
  public let name: String?
  public let device: String?
  public let status: String?
  public let temp: Int?
  /// Raw device size in kilobytes. Distinct from `fsSize`, which is the
  /// filesystem's own view and is absent on parity disks.
  public let size: Int64?
  public let fsFree: Int64?
  public let fsUsed: Int64?
  public let fsSize: Int64?
  public let fsType: String?
  public let rotational: Bool?
  public let numReads: Int64?
  public let numWrites: Int64?
  public let numErrors: Int64?
  public let type: String?

  public init(
    id: String, idx: Int?, name: String?, device: String?, status: String?,
    temp: Int?, size: Int64?, fsFree: Int64?, fsUsed: Int64?, fsSize: Int64?,
    fsType: String?, rotational: Bool?, numReads: Int64?, numWrites: Int64?,
    numErrors: Int64?, type: String?
  ) {
    self.id = id; self.idx = idx; self.name = name; self.device = device
    self.status = status; self.temp = temp; self.size = size
    self.fsFree = fsFree; self.fsUsed = fsUsed; self.fsSize = fsSize
    self.fsType = fsType; self.rotational = rotational
    self.numReads = numReads; self.numWrites = numWrites; self.numErrors = numErrors
    self.type = type
  }

  public var displayName: String { name ?? device ?? id }
  public var isHealthy: Bool { status == "DISK_OK" }

  /// `"DISK_OK"` → `"OK"`, `"DISK_NP_MISSING"` → `"NP MISSING"`: strip the
  /// `DISK_` prefix, then, per underscore-separated component, uppercase
  /// just the first character and leave the rest untouched. Deliberately
  /// *not* `String.capitalized` — every `ArrayDiskStatus` raw value
  /// (`DISK_OK`, `DISK_DSBL`, `DISK_NP`, …) is already all-caps, and
  /// `.capitalized` lowercases everything after each word's first letter,
  /// which would turn the worked example above into `"Ok"` rather than
  /// `"OK"`.
  ///
  /// Shared by `DiskDetailView`'s Status row and `DiskListCard`'s row
  /// subtitle so both screens humanise the raw status
  /// identically rather than each keeping its own copy.
  public var statusText: String? {
    guard let status else { return nil }
    let stripped = status.hasPrefix("DISK_") ? String(status.dropFirst(5)) : status
    return stripped
      .split(separator: "_")
      .map { word -> String in
        guard let first = word.first else { return "" }
        return first.uppercased() + word.dropFirst()
      }
      .joined(separator: " ")
  }

  /// `nil` whenever there's no genuine reading to report: a parity disk has
  /// no filesystem at all (`fsUsed`/`fsSize` both nil), and a disk mid-format
  /// — or one whose filesystem is mounted but hasn't been sampled yet —
  /// reports `fsSize` without `fsUsed`. Either way, `0` would be
  /// indistinguishable from a genuinely empty, healthy disk, so this is
  /// `Double?` rather than defaulting to `0`; callers must `if let` rather
  /// than checking `fsSize` alone.
  public var usedFraction: Double? {
    guard let fsUsed, let fsSize, fsSize > 0 else { return nil }
    return min(1, max(0, Double(fsUsed) / Double(fsSize)))
  }

  /// Parity disks carry no filesystem, so `fsSize` is nil for them — fall
  /// back to the raw device size so the detail screen still shows a capacity.
  public var capacityKilobytes: Int64? { fsSize ?? size }
}

public struct SystemInfo: Equatable, Sendable {
  public let distro: String?
  public let release: String?
  public let bootTimestamp: String?
  public let cpuBrand: String?
  public let cpuCores: Int?
  public let cpuThreads: Int?
  public let cpuPercent: Double?
  public let memoryPercent: Double?
  /// Bytes, not kilobytes — `metrics.memory` is the one place the API
  /// reports raw bytes.
  public let memoryUsedBytes: Int64?
  public let memoryTotalBytes: Int64?

  public init(
    distro: String?, release: String?, bootTimestamp: String?,
    cpuBrand: String?, cpuCores: Int?, cpuThreads: Int?,
    cpuPercent: Double?, memoryPercent: Double?,
    memoryUsedBytes: Int64?, memoryTotalBytes: Int64?
  ) {
    self.distro = distro; self.release = release; self.bootTimestamp = bootTimestamp
    self.cpuBrand = cpuBrand; self.cpuCores = cpuCores; self.cpuThreads = cpuThreads
    self.cpuPercent = cpuPercent; self.memoryPercent = memoryPercent
    self.memoryUsedBytes = memoryUsedBytes; self.memoryTotalBytes = memoryTotalBytes
  }
}

public struct ArrayStatus: Equatable, Sendable {
  public let state: String
  public let capacity: ArrayCapacity?
  public let disks: [ArrayDisk]
  public let parities: [ArrayDisk]
  public let caches: [ArrayDisk]
  public let system: SystemInfo?

  public init(
    state: String, capacity: ArrayCapacity?, disks: [ArrayDisk],
    parities: [ArrayDisk], caches: [ArrayDisk], system: SystemInfo?
  ) {
    self.state = state; self.capacity = capacity; self.disks = disks
    self.parities = parities; self.caches = caches; self.system = system
  }

  public var isStarted: Bool { state == "STARTED" }

  /// Looks up a disk by identifier across all three groups — data, parity,
  /// cache — without the caller needing to know which one it lives in.
  ///
  /// Backs the identifier-based disk detail navigation:
  /// `DiskDetailView` re-resolves its disk from the latest snapshot on every
  /// render via this rather than freezing a value pushed at navigation time,
  /// so a poll behind an open detail screen actually reaches it. Returns
  /// `nil` when the id no longer matches anything — a disk can drop out of
  /// the array while its screen is open, and that is a real state for the
  /// caller to render, not a defensive nicety.
  public func disk(id: ArrayDisk.ID) -> ArrayDisk? {
    disks.first { $0.id == id } ?? parities.first { $0.id == id } ?? caches.first { $0.id == id }
  }
}
