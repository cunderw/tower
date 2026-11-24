import Apollo
import Foundation
import TowerAPI
import TowerCore

/// Reads Unraid's array/system status. Apollo's generated types never
/// escape this module — `LiveSystemRepository` is the boundary where
/// `DashboardQuery.Data`, `DashboardContainersQuery.Data` and
/// `DashboardVMsQuery.Data` get mapped into the `TowerCore` domain model.
public protocol SystemRepositoryProtocol: Sendable {
  func testConnection() async throws -> Bool
  func dashboard() async throws -> DashboardSnapshot

  /// The four parity check actions. Each returns once the server accepts the
  /// request, and throws on a GraphQL error. The server's payload is untyped
  /// `JSON` and carries no state Tower reads, so the caller re-fetches
  /// `dashboard()` to learn the new one.
  ///
  /// `correct` writes corrections to parity, rather than only counting
  /// mismatches.
  func startParityCheck(correct: Bool) async throws
  func pauseParityCheck() async throws
  func resumeParityCheck() async throws
  func cancelParityCheck() async throws

  /// Past parity checks, newest first. A row with no readable date sorts last.
  func parityHistory() async throws -> [ParityCheckRecord]

  /// Starts or stops the array (issue #25). Returns the `ArrayState` raw value
  /// the server reports when the call returns, which can still be the old
  /// state while Unraid works, or `nil` when the request timed out. Throws on
  /// a GraphQL error, such as "The array is already started".
  ///
  /// `passphrase` unlocks an encrypted array on start. It goes into the
  /// request body, and the result is not written to Apollo's cache (issue #55).
  func setArrayState(_ action: ArrayAction, passphrase: String?) async throws -> String?
}

public struct LiveSystemRepository: SystemRepositoryProtocol {
  /// How long `setArrayState` waits for an answer. A start or stop can take
  /// minutes on a large array, and nobody has measured whether Unraid answers
  /// before the change is done, so this is far above the session's 60 s.
  public static let defaultArrayStateTimeout: TimeInterval = 300

  private let provider: ApolloClientProvider
  private let arrayStateTimeout: TimeInterval

  /// - Parameter arrayStateTimeout: How long `setArrayState` waits. A test
  ///   passes a short one.
  public init(provider: ApolloClientProvider, arrayStateTimeout: TimeInterval = defaultArrayStateTimeout) {
    self.provider = provider
    self.arrayStateTimeout = arrayStateTimeout
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

  /// Three concurrent requests, not one. Docker and VMs are optional Unraid
  /// services, and a disabled one fails its part of a query: with Docker off,
  /// the non-null `Docker.containers` resolver throws "Docker socket
  /// unavailable.". Before API 4.37 `docker` is non-null too, so the null
  /// reaches the root and the server answers `data: null` (issue #10). Asked
  /// in one query, that took the array, the system info and the shares down
  /// with it. From 4.37 `docker` and `vms` are nullable, and the null stops
  /// there (issue #21).
  ///
  /// So the core query (array, info, metrics, shares) still fails the
  /// dashboard, and the two counts queries can only make their own row read
  /// "Unavailable" — see `serviceCounts(_:map:)`.
  public func dashboard() async throws -> DashboardSnapshot {
    async let core = provider.client.fetch(query: DashboardQuery(), cachePolicy: .networkOnly)
    async let containers = serviceCounts(DashboardContainersQuery()) { $0.containerCounts }
    async let vms = serviceCounts(DashboardVMsQuery()) { $0.vmCounts }

    let response = try await core
    if let errors = response.errors, !errors.isEmpty {
      throw AppError.from(graphQLErrors: errors)
    }
    guard let data = response.data else {
      throw AppError.decoding("Empty response for Dashboard.")
    }
    let counts = await (containers: containers, vms: vms)
    // `serviceCounts` swallows a cancellation along with every other error,
    // so a load cancelled while the counts were in flight would otherwise
    // come back as a snapshot whose rows read "Unavailable", and land over the
    // store's cancelled state.
    try Task.checkCancellation()
    return DashboardSnapshot(from: data, containers: counts.containers, vms: counts.vms)
  }

  public func startParityCheck(correct: Bool) async throws {
    try await performParityAction(StartParityCheckMutation(correct: correct))
  }

  public func pauseParityCheck() async throws {
    try await performParityAction(PauseParityCheckMutation())
  }

  public func resumeParityCheck() async throws {
    try await performParityAction(ResumeParityCheckMutation())
  }

  public func cancelParityCheck() async throws {
    try await performParityAction(CancelParityCheckMutation())
  }

  /// Shared body for the four parity actions. The payload is decoded (Apollo
  /// requires that, which is why `JSON` accepts any value) and then ignored.
  private func performParityAction<Mutation: GraphQLMutation>(
    _ mutation: Mutation
  ) async throws where Mutation.ResponseFormat == SingleResponseFormat {
    let response = try await provider.client.perform(mutation: mutation)
    if let errors = response.errors, !errors.isEmpty {
      throw AppError.from(graphQLErrors: errors)
    }
    guard response.data != nil else {
      throw AppError.decoding("Empty response for \(Mutation.operationName).")
    }
  }

  /// One `setState` request with its own timeout. A request timeout overrides
  /// the session's idle timeout in both directions, so the other requests keep
  /// 60 s.
  ///
  /// `URLError.timedOut` returns `nil` here, not `.serverUnreachable`: the
  /// server took the request, and the caller polls `dashboard()` to learn
  /// what happened.
  ///
  /// `writeResultsToCache: false` keeps the passphrase out of Apollo's
  /// in-memory cache (issue #55). Apollo keys a cached field by its
  /// arguments, so a cached result keeps `decryptionPassword` in its keys
  /// until the app quits.
  public func setArrayState(_ action: ArrayAction, passphrase: String?) async throws -> String? {
    let desiredState: ArrayStateInputState = switch action {
    case .start: .start
    case .stop: .stop
    }
    let input = ArrayStateInput(
      desiredState: .case(desiredState),
      decryptionPassword: passphrase.map { .some($0) } ?? .none
    )
    let response: GraphQLResponse<SetArrayStateMutation>
    do {
      response = try await provider.client.perform(
        mutation: SetArrayStateMutation(input: input),
        requestConfiguration: RequestConfiguration(requestTimeout: arrayStateTimeout, writeResultsToCache: false)
      )
    } catch let error as URLError where error.code == .timedOut {
      return nil
    }
    if let errors = response.errors, !errors.isEmpty {
      throw AppError.from(graphQLErrors: errors)
    }
    guard let data = response.data else {
      throw AppError.decoding("Empty response for SetArrayState.")
    }
    return data.array.setState.state.rawValue
  }

  /// A field error inside one history row does not fail the list. Unraid's
  /// history can hold a line it cannot parse: the live server answers with a
  /// row whose `errors` is NaN, which GraphQL cannot represent as an `Int`,
  /// so the server nulls that one field and adds an `errors` entry at
  /// `parityHistory.<n>.errors`. The null already says "unknown", so that
  /// entry says nothing the data does not. Any other error still throws.
  public func parityHistory() async throws -> [ParityCheckRecord] {
    let response = try await provider.client.fetch(query: ParityHistoryQuery(), cachePolicy: .networkOnly)
    let errors = (response.errors ?? []).excludingParityHistoryFieldFailures()
    if !errors.isEmpty {
      throw AppError.from(graphQLErrors: errors)
    }
    guard let data = response.data else {
      throw AppError.decoding("Empty response for ParityHistory.")
    }
    return ParityCheckRecord.sortedHistory(from: data.parityHistory)
  }

  /// One optional row's counts, or `nil` for "Unavailable". Never throws:
  /// a thrown error, any `errors` entry, or missing data all give `nil`. A
  /// cancellation is swallowed too, which is why `dashboard()` checks for one
  /// itself after awaiting these.
  ///
  /// Auth errors included. The core query ran with the same key, and it
  /// either succeeded, which proves the key is valid, or it threw, in which
  /// case these counts are never read. An auth error here is a key without
  /// permission for that one service, and that is a row Tower cannot read,
  /// not a reason to blank the dashboard.
  private func serviceCounts<Query: GraphQLQuery>(
    _ query: Query,
    map: (Query.Data) -> ServiceTally?
  ) async -> ServiceTally? where Query.ResponseFormat == SingleResponseFormat {
    guard let response = try? await provider.client.fetch(query: query, cachePolicy: .networkOnly),
          response.errors?.isEmpty ?? true,
          let data = response.data
    else { return nil }
    return map(data)
  }
}

/// How many of one service's items are running, out of how many.
struct ServiceTally: Equatable, Sendable {
  let running: Int
  let total: Int
}

extension DashboardContainersQuery.Data {
  /// Deliberately **not** public — see
  /// `DashboardSnapshot.init(from:containers:vms:)` below.
  ///
  /// `docker` is nullable from API 4.37 (issue #21), and a null one is the
  /// "Unavailable" row.
  var containerCounts: ServiceTally? {
    guard let containers = docker?.containers else { return nil }
    return ServiceTally(running: containers.filter { $0.state == .running }.count, total: containers.count)
  }
}

extension DashboardVMsQuery.Data {
  /// Deliberately **not** public — see
  /// `DashboardSnapshot.init(from:containers:vms:)` below.
  ///
  /// `vms.domains` is a nullable list in the schema (`domains: [VmDomain!]`)
  /// — null means VM reporting is unavailable (libvirt stopped or errored),
  /// not "zero VMs configured". Keep that distinction all the way through:
  /// an empty array still yields real `0`/`0` counts, but a null `domains`
  /// must produce `nil` rather than collapsing to the same zeros a healthy,
  /// VM-less server reports.
  var vmCounts: ServiceTally? {
    guard let domains = vms?.domains else { return nil }
    return ServiceTally(running: domains.filter { $0.state == .running }.count, total: domains.count)
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
/// reason as `DashboardSnapshot.init(from:containers:vms:)` below: this
/// protocol mentions Apollo-generated types, which must never leak past this
/// module's boundary.
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
  /// (`DashboardSnapshot.init(from:containers:vms:)` below) lives in *that*
  /// type's own extension in this same file — `fileprivate` is what
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
  /// Maps Apollo's generated `DashboardQuery.Data`, plus the two counts
  /// queries' results (`nil` for unavailable), into the domain model.
  ///
  /// Deliberately **not** public: its parameter is an Apollo-generated type,
  /// and a public signature mentioning one would let callers construct a
  /// domain model straight from hand-rolled GraphQL data, skipping the
  /// error and nil-data guards in `dashboard()` that are supposed to be the
  /// only way in.
  init(from data: DashboardQuery.Data, containers: ServiceTally?, vms: ServiceTally?) {
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
      memoryUsedBytes: data.metrics.memory.map {
        memoryInUseBytes(total: $0.total, available: $0.available)
      },
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
      services: ServiceCounts(from: data, containers: containers, vms: vms)
    )
  }
}

extension ParityStatus {
  /// Deliberately **not** public — see
  /// `DashboardSnapshot.init(from:containers:vms:)` above.
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
  /// Deliberately **not** public — see
  /// `DashboardSnapshot.init(from:containers:vms:)` above.
  init(from data: DashboardQuery.Data, containers: ServiceTally?, vms: ServiceTally?) {
    self.init(
      containersRunning: containers?.running,
      containersTotal: containers?.total,
      vmsRunning: vms?.running,
      vmsTotal: vms?.total,
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

extension ParityCheckRecord {
  /// Deliberately **not** public — see
  /// `DashboardSnapshot.init(from:containers:vms:)` above.
  ///
  /// Newest first. The server does not sort its history: the live one returns
  /// a 1970 row between two 2020 rows. A row with no readable date sorts last,
  /// and rows with equal dates keep the server's order.
  static func sortedHistory(from rows: [ParityHistoryQuery.Data.ParityHistory]) -> [ParityCheckRecord] {
    let dated = rows.enumerated().map { offset, row in
      (offset: offset, row: row, date: historyDate(row.date))
    }
    let sorted = dated.sorted { lhs, rhs in
      switch (lhs.date, rhs.date) {
      case let (left?, right?) where left != right: left > right
      case (.some, .none): true
      case (.none, .some): false
      default: lhs.offset < rhs.offset
      }
    }
    return sorted.enumerated().map { position, entry in
      ParityCheckRecord(
        id: position,
        date: entry.date,
        durationSeconds: entry.row.duration,
        speed: entry.row.speed,
        state: ParityCheckState(rawValue: entry.row.status.rawValue),
        errors: entry.row.errors
      )
    }
  }

  /// Unraid writes the Unix epoch for a history line it could not date. That
  /// is "unknown", not a check that ran in 1970.
  private static func historyDate(_ timestamp: String?) -> Date? {
    guard let timestamp, let date = Formatters.parseTimestamp(timestamp),
          date.timeIntervalSince1970 > 0
    else { return nil }
    return date
  }
}
