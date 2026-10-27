import Foundation
import TowerCore

/// Everything the Prowlarr screens can ask for.
///
/// **Reuses `ArrClientCore` where the v1 API matches**, which is health,
/// system status, and commands — Prowlarr is an *arr and answers those
/// identically. Indexers and their stats, history and management are its own,
/// and are the whole of this protocol.
public protocol ProwlarrRepositoryProtocol: ServiceRepository {
  /// The shared *arr endpoints for this instance.
  var arr: ArrClientCore { get }

  func indexers() async throws -> [ProwlarrIndexer]
  func setEnabled(_ isEnabled: Bool, indexerID: Int) async throws
  func test(indexerID: Int) async throws -> IndexerTestResult
  func delete(indexerID: Int) async throws

  /// Every indexer definition Prowlarr knows, for the add flow.
  func schemas() async throws -> [IndexerSchema]
  @discardableResult
  func save(_ draft: IndexerDraft) async throws -> ProwlarrIndexer
  /// Validates a draft without saving it — Prowlarr's `/indexer/test` accepts
  /// a whole resource, which is how the add form checks credentials first.
  func test(_ draft: IndexerDraft) async throws -> IndexerTestResult

  func stats() async throws -> [IndexerStats]
  func history(indexerID: Int?) async throws -> [ProwlarrHistoryRecord]
}

/// The live conformance.
public struct LiveProwlarrRepository: ProwlarrRepositoryProtocol {
  public let instance: ServiceInstance
  public let arr: ArrClientCore
  private let client: ServiceHTTPClient

  public init(instance: ServiceInstance, sessionConfiguration: URLSessionConfiguration? = nil) {
    let client = ServiceHTTPClient(
      instance: instance, sessionConfiguration: sessionConfiguration)
    self.init(instance: instance, client: client)
  }

  init(instance: ServiceInstance, client: ServiceHTTPClient) {
    self.instance = instance
    self.client = client
    // v1, not v3 — Prowlarr's own version of the shared surface.
    self.arr = ArrClientCore(client: client, apiPath: "api/v1")
  }

  // MARK: - Indexers

  public func indexers() async throws -> [ProwlarrIndexer] {
    let dtos: [IndexerDTO] = try await client.send("api/v1/indexer", as: [IndexerDTO].self)
    var indexers = dtos.map(\.domain).sorted {
      $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
    }

    // `/indexer` says nothing about whether an indexer is currently *failing* —
    // that lives in `/indexerstatus`, and it is the single most useful thing
    // the list can show. Asked for separately, and non-fatally: a Prowlarr that
    // answers the list but not the status should still show the list.
    if let statuses: [IndexerStatusDTO] = try? await client.send(
      "api/v1/indexerstatus", as: [IndexerStatusDTO].self)
    {
      let byID = Dictionary(
        statuses.compactMap { status in status.indexerId.map { ($0, status) } },
        uniquingKeysWith: { first, _ in first })
      indexers = indexers.map { indexer in
        guard let status = byID[indexer.id] else { return indexer }
        var indexer = indexer
        indexer.disabledUntil = status.disabledTill
        // Prowlarr doesn't send a reason here, only timings; the dates are the
        // fact, and the UI words it.
        indexer.failureMessage = status.mostRecentFailure != nil ? "Recent failures" : nil
        return indexer
      }
    }
    return indexers
  }

  public func setEnabled(_ isEnabled: Bool, indexerID: Int) async throws {
    // Prowlarr's PUT rebuilds the indexer from the body, so the indexer is read
    // back first and returned with one field changed. A PATCH-shaped body would
    // clear every field it omitted — including the API key.
    var dto: IndexerDTO = try await client.send(
      "api/v1/indexer/\(indexerID)", as: IndexerDTO.self)
    dto = dto.settingEnabled(isEnabled)
    try await client.send("api/v1/indexer/\(indexerID)", method: .put, body: dto)
  }

  public func delete(indexerID: Int) async throws {
    try await client.send("api/v1/indexer/\(indexerID)", method: .delete)
  }

  public func test(indexerID: Int) async throws -> IndexerTestResult {
    let dto: IndexerDTO = try await client.send(
      "api/v1/indexer/\(indexerID)", as: IndexerDTO.self)
    return try await runTest(body: dto)
  }

  public func test(_ draft: IndexerDraft) async throws -> IndexerTestResult {
    // Any AppError from fetching the profiles (none set up, 401, unreachable)
    // becomes a failed test carrying its message, not a throw: the add form
    // reads a throw as "Prowlarr didn't answer the test".
    let profileID: Int
    do {
      profileID = try await appProfileID()
    } catch let error as AppError {
      return IndexerTestResult(isSuccess: false, messages: [error.message])
    }
    return try await runTest(body: IndexerDTO(draft: draft, appProfileID: profileID))
  }

  /// `POST /indexer/test` answers **200** on success and
  /// **400 with a list of validation failures** on rejection — so a test that
  /// only looked at the status code would report "unreachable" for a wrong
  /// password rather than saying what was wrong.
  private func runTest(body: IndexerDTO) async throws -> IndexerTestResult {
    do {
      try await client.send("api/v1/indexer/test", method: .post, body: body)
      return IndexerTestResult(isSuccess: true, messages: [])
    } catch let error as AppError {
      return IndexerTestResult(isSuccess: false, messages: [error.message])
    }
  }

  // MARK: - Schemas and saving

  public func schemas() async throws -> [IndexerSchema] {
    let dtos: [IndexerDTO] = try await client.send(
      "api/v1/indexer/schema", as: [IndexerDTO].self)
    return dtos.map(\.schema).sorted {
      $0.definitionName.localizedCaseInsensitiveCompare($1.definitionName) == .orderedAscending
    }
  }

  @discardableResult
  public func save(_ draft: IndexerDraft) async throws -> ProwlarrIndexer {
    if let id = draft.id {
      return try await client.send(
        "api/v1/indexer/\(id)", method: .put,
        body: IndexerDTO(draft: draft, appProfileID: nil), as: IndexerDTO.self
      ).domain
    }
    let body = IndexerDTO(draft: draft, appProfileID: try await appProfileID())
    return try await client.send(
      "api/v1/indexer", method: .post, body: body, as: IndexerDTO.self
    ).domain
  }

  /// The app profile a new indexer goes under. Prowlarr's validator requires
  /// one, the schema carries none, and Prowlarr's own add form defaults to the
  /// first profile by name, so this does the same. The comparison is numeric,
  /// as Prowlarr's is, so "Profile 2" comes before "Profile 10".
  private func appProfileID() async throws -> Int {
    let profiles: [AppProfileDTO] = try await client.send(
      "api/v1/appprofile", as: [AppProfileDTO].self)
    let first = profiles
      .compactMap { profile in profile.id.map { (id: $0, name: profile.name ?? "") } }
      .filter { $0.id > 0 }
      .min { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    guard let first else {
      throw AppError.actionRefused(
        "\(instance.name) has no app profiles. Add one in Prowlarr's settings first.")
    }
    return first.id
  }

  // MARK: - Stats and history

  public func stats() async throws -> [IndexerStats] {
    let dto: IndexerStatsResourceDTO = try await client.send(
      "api/v1/indexerstats", as: IndexerStatsResourceDTO.self)
    return (dto.indexers ?? []).map(\.domain)
  }

  public func history(indexerID: Int?) async throws -> [ProwlarrHistoryRecord] {
    var query = [
      URLQueryItem(name: "page", value: "1"),
      URLQueryItem(name: "pageSize", value: "50"),
      URLQueryItem(name: "sortKey", value: "date"),
      URLQueryItem(name: "sortDirection", value: "descending"),
    ]
    if let indexerID {
      query.append(URLQueryItem(name: "indexerId", value: String(indexerID)))
    }
    let dto: ProwlarrHistoryPageDTO = try await client.send(
      "api/v1/history", query: query, as: ProwlarrHistoryPageDTO.self)
    return (dto.records ?? []).map(\.domain)
  }
}

extension IndexerDTO {
  /// A copy with `enable` flipped, preserving every other field — which is the
  /// whole point, since Prowlarr's PUT rebuilds the indexer from the body.
  fileprivate func settingEnabled(_ isEnabled: Bool) -> IndexerDTO {
    var copy = self
    copy.enable = isEnabled
    return copy
  }
}
