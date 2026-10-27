import Foundation
import TowerCore
import TowerData

/// Demo mode's NZBGet.
///
/// **Mutations are real, in memory**, on the same rule as the demo *arrs: a
/// demo where Pause does nothing is a demo that shows the app not working, and
/// App Review walks this path.
private enum DemoClientLatency {
  static let read = Duration.milliseconds(450)
  static let write = Duration.milliseconds(700)

  static func read() async { try? await Task.sleep(for: read) }
  static func write() async { try? await Task.sleep(for: write) }
}

// MARK: - NZBGet

@MainActor
final class DemoNZBServer {
  private(set) var queue: [NZBGroup] = DemoDownloadFixtures.nzbQueue()
  private(set) var history: [NZBHistoryItem] = DemoDownloadFixtures.nzbHistory()
  private(set) var isPaused = false
  private(set) var speedLimit: Int64?

  func setStatus(_ status: NZBGroupStatus, ids: [Int]) {
    queue = queue.map { ids.contains($0.id) ? $0.settingStatus(status) : $0 }
  }

  func setPriority(_ priority: NZBPriority, ids: [Int]) {
    queue = queue.map { ids.contains($0.id) ? $0.settingPriority(priority) : $0 }
    // NZBGet orders its queue by priority, and the demo has to reorder too or
    // a priority change is invisible here.
    queue = queue.enumerated()
      .sorted {
        $0.element.priority.rawValue == $1.element.priority.rawValue
          ? $0.offset < $1.offset
          : $0.element.priority.rawValue > $1.element.priority.rawValue
      }
      .map(\.element)
  }

  func remove(ids: [Int]) { queue.removeAll { ids.contains($0.id) } }

  func setPaused(_ paused: Bool) { isPaused = paused }
  func setSpeedLimit(_ limit: Int64?) { speedLimit = limit }

  /// A retry puts the item back in the queue and drops the history entry —
  /// which is what NZBGet does.
  func retry(ids: [Int]) {
    for id in ids {
      guard let item = history.first(where: { $0.id == id }) else { continue }
      queue.append(
        NZBGroup(
          id: item.id, name: item.name, status: .queued, category: item.category,
          sizeBytes: item.sizeBytes, remainingBytes: item.sizeBytes, downloadedBytes: 0,
          priority: .normal, health: 1, activeDownloads: 0))
    }
    history.removeAll { ids.contains($0.id) }
  }

  func removeHistory(ids: [Int]) { history.removeAll { ids.contains($0.id) } }
}

struct DemoNZBGetRepository: NZBGetRepositoryProtocol {
  let instance: ServiceInstance
  let server: DemoNZBServer

  func queue() async throws -> [NZBGroup] {
    await DemoClientLatency.read()
    return await server.queue
  }

  func history() async throws -> [NZBHistoryItem] {
    await DemoClientLatency.read()
    return await server.history
  }

  func status() async throws -> NZBServerStatus {
    await DemoClientLatency.read()
    let queue = await server.queue
    let paused = await server.isPaused
    return NZBServerStatus(
      // Derived, so pausing the server visibly drops the rate to zero.
      downloadRateBytesPerSecond: paused ? 0 : 18_874_368,
      remainingBytes: queue.reduce(0) { $0 + $1.remainingBytes },
      downloadedBytes: 549_755_813_888,
      freeDiskSpaceBytes: 3_221_225_472_000,
      isDownloadPaused: paused,
      speedLimitBytesPerSecond: await server.speedLimit,
      uptime: 172_800,
      postJobCount: queue.filter(\.status.isPostProcessing).count,
      version: "21.1")
  }

  func pause(ids: [Int]) async throws {
    await DemoClientLatency.write()
    await server.setStatus(.paused, ids: ids)
  }

  func resume(ids: [Int]) async throws {
    await DemoClientLatency.write()
    await server.setStatus(.queued, ids: ids)
  }

  func setPriority(_ priority: NZBPriority, ids: [Int]) async throws {
    await DemoClientLatency.write()
    await server.setPriority(priority, ids: ids)
  }

  func delete(ids: [Int]) async throws {
    await DemoClientLatency.write()
    await server.remove(ids: ids)
  }

  func pauseAll() async throws {
    await DemoClientLatency.write()
    await server.setPaused(true)
  }

  func resumeAll() async throws {
    await DemoClientLatency.write()
    await server.setPaused(false)
  }

  func setSpeedLimit(bytesPerSecond: Int64?) async throws {
    await DemoClientLatency.write()
    await server.setSpeedLimit(bytesPerSecond)
  }

  func retryHistory(ids: [Int]) async throws {
    await DemoClientLatency.write()
    await server.retry(ids: ids)
  }

  func deleteHistory(ids: [Int]) async throws {
    await DemoClientLatency.write()
    await server.removeHistory(ids: ids)
  }
}

// MARK: - Local mutations

extension NZBGroup {
  fileprivate func settingStatus(_ status: NZBGroupStatus) -> NZBGroup {
    NZBGroup(
      id: id, name: name, status: status, category: category, sizeBytes: sizeBytes,
      remainingBytes: remainingBytes, downloadedBytes: downloadedBytes, priority: priority,
      health: health, activeDownloads: activeDownloads)
  }

  fileprivate func settingPriority(_ priority: NZBPriority) -> NZBGroup {
    NZBGroup(
      id: id, name: name, status: status, category: category, sizeBytes: sizeBytes,
      remainingBytes: remainingBytes, downloadedBytes: downloadedBytes, priority: priority,
      health: health, activeDownloads: activeDownloads)
  }
}
