import Apollo
import Foundation
import TowerAPI
import TowerCore

/// Reads Unraid's array/system status. Apollo's generated types never
/// escape this module — `LiveSystemRepository` is the boundary where
/// `DashboardQuery.Data` gets mapped into the `TowerCore` domain model.
public protocol SystemRepositoryProtocol: Sendable {
  func testConnection() async throws -> Bool
  func dashboard() async throws -> DashboardSnapshot
}

public struct LiveSystemRepository: SystemRepositoryProtocol {
  private let provider: ApolloClientProvider

  public init(provider: ApolloClientProvider) {
    self.provider = provider
  }

  public func testConnection() async throws -> Bool {
    let response = try await provider.client.fetch(
      query: TestConnectionQuery(),
      cachePolicy: .networkOnly
    )
    if let errors = response.errors, !errors.isEmpty {
      throw AppError.from(graphQLErrors: errors)
    }
    // `info` and `info.os` are non-null in the schema; only `platform`
    // itself (and the whole response, on a decode/transport failure) can
    // be missing.
    return response.data?.info.os.platform != nil
  }

  public func dashboard() async throws -> DashboardSnapshot {
    let response = try await provider.client.fetch(
      query: DashboardQuery(),
      cachePolicy: .networkOnly
    )
    if let errors = response.errors?.excludingVMDomainFailures(), !errors.isEmpty {
      throw AppError.from(graphQLErrors: errors)
    }
    guard let data = response.data else {
      throw AppError.decoding("Empty response for Dashboard.")
    }
    return DashboardSnapshot(from: data)
  }
}

/// Structural shape shared by `DashboardQuery`'s `disks`, `parities`, and
/// `caches` selections. `parities`/`caches` select the same fields as
/// `disks`, so all three generated types have identical
/// field sets — they differ only in nominal type, since Apollo generates a
/// distinct type per selection set even when the shape matches byte for
/// byte. This lets the three `ArrayDisk.init(from:)` overloads that would
/// otherwise be needed collapse into the one generic initialiser below,
/// instead of three copies that would silently drift apart under a future
/// edit to just one of them.
///
/// Deliberately **not** public, and so are its conformances below — same
/// reason as `DashboardSnapshot.init(from:)` below: this protocol mentions
/// Apollo-generated types, which must never leak past this module's
/// boundary.
private protocol DashboardDiskFields {
  var id: TowerAPI.PrefixedID { get }
  var idx: Int { get }
  var name: String? { get }
  var device: String? { get }
  var status: GraphQLEnum<TowerAPI.ArrayDiskStatus>? { get }
  var temp: Int? { get }
  var size: TowerAPI.BigInt? { get }
  var fsFree: TowerAPI.BigInt? { get }
  var fsUsed: TowerAPI.BigInt? { get }
  var fsSize: TowerAPI.BigInt? { get }
  var fsType: String? { get }
  var rotational: Bool? { get }
  var numReads: TowerAPI.BigInt? { get }
  var numWrites: TowerAPI.BigInt? { get }
  var numErrors: TowerAPI.BigInt? { get }
  var type: GraphQLEnum<TowerAPI.ArrayDiskType> { get }
}

extension DashboardQuery.Data.Array.Disk: DashboardDiskFields {}
extension DashboardQuery.Data.Array.Parity: DashboardDiskFields {}
extension DashboardQuery.Data.Array.Cach: DashboardDiskFields {}

extension ArrayDisk {
  /// `DashboardQuery`'s `disks`, `parities`, and `caches` selections all
  /// route through here — see `DashboardDiskFields` above for why one body
  /// serves all three. `fsFree`/`fsUsed`/`fsSize`/`fsType` are only ever
  /// genuinely `nil` for parity disks, which carry no filesystem; that's
  /// what Unraid reports, not a gap in this selection.
  ///
  /// `fileprivate`, not the file's usual bare `init(from:)`: `private`
  /// would restrict this to `ArrayDisk`'s own extensions, but its caller
  /// (`DashboardSnapshot.init(from:)` below) lives in *that* type's own
  /// extension in this same file — `fileprivate` is what
  /// `DashboardDiskFields` being a private parameter type requires.
  fileprivate init(from disk: some DashboardDiskFields) {
    self.init(
      id: disk.id,
      idx: disk.idx,
      name: disk.name,
      device: disk.device,
      status: disk.status?.rawValue,
      temp: disk.temp,
      size: disk.size,
      fsFree: disk.fsFree,
      fsUsed: disk.fsUsed,
      fsSize: disk.fsSize,
      fsType: disk.fsType,
      rotational: disk.rotational,
      numReads: disk.numReads,
      numWrites: disk.numWrites,
      numErrors: disk.numErrors,
      type: disk.type.rawValue
    )
  }
}

extension DashboardSnapshot {
  /// Maps Apollo's generated `DashboardQuery.Data` into the domain model.
  ///
  /// Deliberately **not** public: its parameter is an Apollo-generated type,
  /// and a public signature mentioning one would let callers construct a
  /// domain model straight from hand-rolled GraphQL data, skipping the
  /// error and nil-data guards in `dashboard()` that are supposed to be the
  /// only way in.
  init(from data: DashboardQuery.Data) {
    let array = data.array
    let kilobytes = array.capacity.kilobytes

    let capacity: ArrayCapacity? = {
      guard let free = Int64(kilobytes.free),
            let used = Int64(kilobytes.used),
            let total = Int64(kilobytes.total)
      else { return nil }
      return ArrayCapacity(free: free, used: used, total: total)
    }()

    let system = SystemInfo(
      distro: data.info.os.distro,
      release: data.info.os.release,
      bootTimestamp: data.info.os.uptime,
      cpuBrand: data.info.cpu.brand,
      cpuCores: data.info.cpu.cores,
      cpuThreads: data.info.cpu.threads,
      cpuPercent: data.metrics.cpu?.percentTotal,
      memoryPercent: data.metrics.memory?.percentTotal,
      memoryUsedBytes: data.metrics.memory?.used,
      memoryTotalBytes: data.metrics.memory?.total
    )

    // Map first, then sort by `idx` so display order is stable across
    // refreshes — the server does not guarantee array order. Unknown slots
    // (`nil`) sink to the end via `?? .max`; they must never sort to the
    // front the way `?? 0` would, since `0` is Parity1's real slot.
    let status = ArrayStatus(
      state: array.state.rawValue,
      capacity: capacity,
      disks: array.disks.map(ArrayDisk.init(from:)).sorted { ($0.idx ?? .max) < ($1.idx ?? .max) },
      parities: array.parities.map(ArrayDisk.init(from:)).sorted { ($0.idx ?? .max) < ($1.idx ?? .max) },
      caches: array.caches.map(ArrayDisk.init(from:)).sorted { ($0.idx ?? .max) < ($1.idx ?? .max) },
      system: system
    )

    self.init(
      array: status,
      parity: ParityStatus(from: array.parityCheckStatus),
      services: ServiceCounts(from: data)
    )
  }
}

extension ParityStatus {
  /// Deliberately **not** public — see `DashboardSnapshot.init(from:)` above.
  init(from status: DashboardQuery.Data.Array.ParityCheckStatus) {
    self.init(
      state: ParityCheckState(rawValue: status.status.rawValue),
      progressPercent: status.progress,
      errors: status.errors,
      speed: status.speed,
      lastRunTimestamp: status.date,
      durationSeconds: status.duration,
      // `correcting` arrives as null on an idle server; absence of an
      // in-flight check reads as "not correcting", not "unknown".
      correcting: status.correcting ?? false
    )
  }
}

extension ServiceCounts {
  /// Deliberately **not** public — see `DashboardSnapshot.init(from:)` above.
  init(from data: DashboardQuery.Data) {
    let containers = data.docker.containers
    // `vms.domains` is a nullable list in the schema (`domains: [VmDomain!]`)
    // — null means VM reporting is unavailable (libvirt stopped or errored),
    // not "zero VMs configured". Keep that distinction all the way through:
    // an empty array still yields real `0`/`0` counts below, but a null
    // `domains` must produce `nil`/`nil` rather than collapsing to the same
    // zeros a healthy, VM-less server reports.
    let domains = data.vms.domains

    self.init(
      containersRunning: containers.filter { $0.state == .running }.count,
      containersTotal: containers.count,
      vmsRunning: domains?.filter { $0.state == .running }.count,
      vmsTotal: domains?.count,
      // Deliberately not aggregating `share.used`/`share.free` here (or
      // anywhere): those fields report the used/free space of the storage
      // *pool* a share resides on, not the share itself, so every share on
      // the same pool returns a byte-identical value. Summing across shares
      // multiplies each pool's total by its share count, which can produce a
      // "usage" figure several times the array's size. Per-share usage is
      // not obtainable from this API; see `Share`'s doc comment.
      sharesTotal: data.shares.count
    )
  }
}
