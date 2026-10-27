import Foundation
import TowerCore

/// Everything the NZBGet screens can ask for.
///
/// **Nothing in this protocol says JSON-RPC.** It reads like every other
/// repository protocol — methods taking ids and returning `TowerCore` values —
/// and a store written against it cannot tell which transport is underneath.
public protocol NZBGetRepositoryProtocol: ServiceRepository {
  func queue() async throws -> [NZBGroup]
  func history() async throws -> [NZBHistoryItem]
  func status() async throws -> NZBServerStatus

  func pause(ids: [Int]) async throws
  func resume(ids: [Int]) async throws
  func setPriority(_ priority: NZBPriority, ids: [Int]) async throws
  func delete(ids: [Int]) async throws

  /// Global pause — NZBGet's own switch, not a loop over the queue.
  func pauseAll() async throws
  func resumeAll() async throws
  /// Bytes per second; `nil` removes the cap.
  func setSpeedLimit(bytesPerSecond: Int64?) async throws

  func retryHistory(ids: [Int]) async throws
  func deleteHistory(ids: [Int]) async throws
}

/// The live conformance, over JSON-RPC.
public struct LiveNZBGetRepository: NZBGetRepositoryProtocol {
  public let instance: ServiceInstance
  private let client: NZBGetClient

  public init(instance: ServiceInstance, sessionConfiguration: URLSessionConfiguration? = nil) {
    self.instance = instance
    self.client = NZBGetClient(instance: instance, sessionConfiguration: sessionConfiguration)
  }

  // MARK: - Reading

  public func queue() async throws -> [NZBGroup] {
    // `listgroups(0)` — the parameter is a row limit, and 0 means all of them.
    let dtos: [NZBGroupDTO] = try await client.call(
      "listgroups", params: [.int(0)], as: [NZBGroupDTO].self)
    var groups = dtos.map(\.domain)

    // NZBGet has no per-group ETA — it reports one server-wide rate, because it
    // downloads the queue in order rather than in parallel. So the estimate is
    // derived here: the first active group gets the whole rate, and the ones
    // behind it are estimated after everything ahead of them finishes. That is
    // both more honest than showing nothing and closer than dividing the rate
    // between them, which is what a naive per-row calculation would do.
    if let status = try? await self.status(), status.downloadRateBytesPerSecond > 0 {
      var bytesAhead: Int64 = 0
      let rate = Double(status.downloadRateBytesPerSecond)
      groups = groups.map { group in
        var group = group
        guard !group.status.isPaused, !group.status.isPostProcessing else { return group }
        bytesAhead += group.remainingBytes
        group.estimatedSecondsRemaining = Double(bytesAhead) / rate
        return group
      }
    }
    return groups
  }

  public func history() async throws -> [NZBHistoryItem] {
    // `history(false)` — the flag asks for hidden entries, which are NZBGet's
    // internal bookkeeping and not something to show.
    let dtos: [NZBHistoryDTO] = try await client.call(
      "history", params: [.bool(false)], as: [NZBHistoryDTO].self)
    // Newest first. NZBGet returns oldest-first on some builds.
    return dtos.map(\.domain).sorted {
      ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast)
    }
  }

  public func status() async throws -> NZBServerStatus {
    let dto: NZBStatusDTO = try await client.call("status", as: NZBStatusDTO.self)
    // The version is a nicety on the status screen, so a build that refuses it
    // costs the label rather than the screen.
    let version = try? await client.call("version", as: String.self)
    return dto.domain(version: version)
  }

  // MARK: - Queue actions

  public func pause(ids: [Int]) async throws {
    try await edit("GroupPause", ids: ids)
  }

  public func resume(ids: [Int]) async throws {
    try await edit("GroupResume", ids: ids)
  }

  public func setPriority(_ priority: NZBPriority, ids: [Int]) async throws {
    // The priority rides in `editqueue`'s *text* parameter, as a string — one
    // of the few places NZBGet's API takes a number that way.
    try await edit("GroupSetPriority", text: String(priority.rawValue), ids: ids)
  }

  public func delete(ids: [Int]) async throws {
    try await edit("GroupFinalDelete", ids: ids)
  }

  public func retryHistory(ids: [Int]) async throws {
    try await edit("HistoryRedownload", ids: ids)
  }

  public func deleteHistory(ids: [Int]) async throws {
    try await edit("HistoryFinalDelete", ids: ids)
  }

  /// `editqueue(command, offset, text, ids)`.
  ///
  /// The `offset` parameter is only meaningful for the move commands, and is 0
  /// for everything here — but it is positional and cannot be omitted, which is
  /// the mistake this one helper exists to prevent making six times.
  private func edit(_ command: String, text: String = "", ids: [Int]) async throws {
    guard !ids.isEmpty else { return }
    try await client.command(
      "editqueue", params: [.string(command), .int(0), .string(text), .intArray(ids)])
  }

  // MARK: - Global actions

  public func pauseAll() async throws {
    try await client.command("pausedownload")
  }

  public func resumeAll() async throws {
    try await client.command("resumedownload")
  }

  public func setSpeedLimit(bytesPerSecond: Int64?) async throws {
    // `rate` takes **kilobytes** per second, and 0 means unlimited. Passing
    // bytes here would cap a user at a thousandth of what they asked for.
    // A positive limit rounds up to at least 1 KB/s: truncating a smaller one
    // to 0 would remove the cap instead of setting it.
    let bytes = bytesPerSecond ?? 0
    let kilobytes = bytes > 0 ? max(1, bytes / 1_024) : 0
    try await client.command("rate", params: [.int(Int(kilobytes))])
  }
}
