import Foundation
import TowerCore

/// Everything the Radarr screens can ask for.
///
/// One protocol per service, live and demo conformances, exactly as the Unraid
/// repositories work — so the views and stores never learn which they have.
/// The shared *arr surface (queue, calendar, history, health, …) is reached
/// through `arr`, which is the same `ArrClientCore` every *arr service
/// reuses rather than a per-service copy.
public protocol RadarrRepositoryProtocol: ServiceRepository, ArrPickerSource {
  /// The shared *arr endpoints for this instance.
  var arr: ArrClientCore { get }

  func movies() async throws -> [RadarrMovie]
  func movie(id: Int) async throws -> RadarrMovie
  /// TMDb search for the add flow.
  func lookup(term: String) async throws -> [RadarrMovieLookup]
  @discardableResult
  func add(_ request: RadarrAddMovieRequest) async throws -> RadarrMovie
  @discardableResult
  func update(_ movie: RadarrMovie, with edit: RadarrMovieEdit) async throws -> RadarrMovie
  /// `deleteFiles` is the destructive half and is never defaulted on: a delete
  /// that also removed the file when the user only meant to stop tracking it is
  /// not recoverable from inside Tower.
  func delete(id: Int, deleteFiles: Bool, addImportExclusion: Bool) async throws
  /// Interactive search: what the indexers have for this movie.
  func releases(movieID: Int) async throws -> [ArrRelease]
  /// Grabs a release the user picked.
  func grab(_ release: ArrRelease) async throws
  /// Kicks off Radarr's own search for the movie.
  func search(movieID: Int) async throws
}

/// The live conformance, over `ServiceHTTPClient`.
public struct LiveRadarrRepository: RadarrRepositoryProtocol {
  public let instance: ServiceInstance
  public let arr: ArrClientCore
  private let client: ServiceHTTPClient

  public init(instance: ServiceInstance, sessionConfiguration: URLSessionConfiguration? = nil) {
    let client = ServiceHTTPClient(instance: instance, sessionConfiguration: sessionConfiguration)
    self.init(instance: instance, client: client)
  }

  init(instance: ServiceInstance, client: ServiceHTTPClient) {
    self.instance = instance
    self.client = client
    self.arr = ArrClientCore(client: client, apiPath: "api/v3")
  }

  public func movies() async throws -> [RadarrMovie] {
    let dtos: [MovieDTO] = try await client.send("api/v3/movie", as: [MovieDTO].self)
    // Sorted by Radarr's own sort title so Tower's list order matches the
    // service's — a library sorted differently in two places reads as a bug.
    return dtos.map(\.domain).sorted {
      $0.sortTitle.localizedCaseInsensitiveCompare($1.sortTitle) == .orderedAscending
    }
  }

  public func movie(id: Int) async throws -> RadarrMovie {
    try await client.send("api/v3/movie/\(id)", as: MovieDTO.self).domain
  }

  public func lookup(term: String) async throws -> [RadarrMovieLookup] {
    let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return [] }
    let dtos: [MovieDTO] = try await client.send(
      "api/v3/movie/lookup",
      query: [URLQueryItem(name: "term", value: trimmed)],
      as: [MovieDTO].self)
    return dtos.map(\.lookupDomain)
  }

  @discardableResult
  public func add(_ request: RadarrAddMovieRequest) async throws -> RadarrMovie {
    let body = AddMovieBody(request: request)
    return try await client.send("api/v3/movie", method: .post, body: body, as: MovieDTO.self)
      .domain
  }

  @discardableResult
  public func update(_ movie: RadarrMovie, with edit: RadarrMovieEdit) async throws -> RadarrMovie {
    // PUT merges a fixed set of fields onto the stored record, so the edit is
    // applied to the movie as fetched rather than sent as a patch.
    let current: MovieDTO = try await client.send("api/v3/movie/\(movie.id)", as: MovieDTO.self)
    let body = current.applying(edit)
    return try await client.send(
      "api/v3/movie/\(movie.id)", method: .put, body: body, as: MovieDTO.self
    ).domain
  }

  public func delete(id: Int, deleteFiles: Bool, addImportExclusion: Bool) async throws {
    try await client.send(
      "api/v3/movie/\(id)",
      method: .delete,
      query: [
        URLQueryItem(name: "deleteFiles", value: String(deleteFiles)),
        URLQueryItem(name: "addImportExclusion", value: String(addImportExclusion)),
      ])
  }

  public func releases(movieID: Int) async throws -> [ArrRelease] {
    let dtos: [ReleaseDTO] = try await client.send(
      "api/v3/release",
      query: [URLQueryItem(name: "movieId", value: String(movieID))],
      as: [ReleaseDTO].self)
    return dtos.map(\.domain)
  }

  public func grab(_ release: ArrRelease) async throws {
    // The grab endpoint takes the release's guid and the indexer that offered
    // it — the same release from two indexers is two different grabs.
    let body = GrabReleaseBody(guid: release.id, indexerId: release.indexerID ?? 0)
    try await client.send("api/v3/release", method: .post, body: body)
  }

  public func search(movieID: Int) async throws {
    try await arr.runCommand("MoviesSearch", parameters: ["movieIds": .ints([movieID])])
  }
}

/// The picker endpoints, answered from the shared core by default. A live
/// repository never overrides these; a demo or fake one does.
extension RadarrRepositoryProtocol {
  public func qualityProfiles() async throws -> [ArrQualityProfile] {
    try await arr.qualityProfiles()
  }

  public func queue() async throws -> ArrQueuePage {
    try await arr.queue()
  }

  public func removeQueueItem(
    id: Int, removeFromClient: Bool, blocklist: Bool
  ) async throws {
    try await arr.removeQueueItem(
      id: id, removeFromClient: removeFromClient, blocklist: blocklist)
  }

  public func calendar(start: Date, end: Date) async throws -> [ArrCalendarEntry] {
    try await arr.calendar(start: start, end: end)
  }

  public func history(page: Int) async throws -> ArrHistoryPage {
    try await arr.history(page: page)
  }

  public func health() async throws -> [ArrHealthCheck] {
    try await arr.health()
  }

  public func diskSpace() async throws -> [ArrDiskSpace] {
    try await arr.diskSpace()
  }

  public func systemStatus() async throws -> ArrSystemStatus {
    try await arr.systemStatus()
  }

  @discardableResult
  public func runCommand(_ name: String) async throws -> ArrCommand {
    try await arr.runCommand(name)
  }

  public func rootFolders() async throws -> [ArrRootFolder] {
    try await arr.rootFolders()
  }

  public func tags() async throws -> [ArrTag] {
    try await arr.tags()
  }
}
