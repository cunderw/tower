import Foundation
import Observation
import TowerCore
import TowerData

/// The admin-glance section: health, disk space, version, and the handful of
/// commands worth firing by hand.
@MainActor
@Observable
final class ArrMoreStore {
  private(set) var health: [ArrHealthCheck] = []
  private(set) var disks: [ArrDiskSpace] = []
  private(set) var status: ArrSystemStatus?
  private(set) var loadError: AppError?
  private(set) var isLoading = false

  /// The command currently running, and how the last one ended. Both are shown:
  /// a command that reports nothing looks like a button that does nothing,
  /// because from the outside that is exactly what it is.
  private(set) var runningCommand: String?
  private(set) var lastCommandResult: CommandResult?
  private(set) var completedCommands = 0

  struct CommandResult: Equatable {
    let name: String
    let error: AppError?

    var succeeded: Bool { error == nil }
  }

  /// The commands a user actually fires by hand. Deliberately short: the *arr
  /// web UI has a dozen, and most of them are ways to make things worse.
  static let offeredCommands: [(name: String, title: String, systemImage: String)] = [
    ("RssSync", "RSS Sync", "antenna.radiowaves.left.and.right"),
    ("RefreshMonitoredDownloads", "Refresh Downloads", "arrow.clockwise"),
    ("Backup", "Back Up Database", "externaldrive"),
  ]

  private let source: any ArrPickerSource

  init(source: any ArrPickerSource) {
    self.source = source
  }

  var hasLoaded: Bool { status != nil || !health.isEmpty || !disks.isEmpty }

  /// Loads all three concurrently, and **keeps whatever answered**: a service
  /// that reports health but refuses `diskspace` should still show its health,
  /// rather than one failure blanking the screen.
  func load() async {
    guard !isLoading else { return }
    isLoading = true
    defer { isLoading = false }

    async let health = try? await source.health()
    async let disks = try? await source.diskSpace()
    async let status = try? await source.systemStatus()

    self.health = await health ?? []
    self.disks = await disks ?? []
    self.status = await status

    loadError = hasLoaded ? nil : .serverUnreachable
  }

  func run(_ command: String) async {
    guard runningCommand == nil else { return }
    runningCommand = command
    defer { runningCommand = nil }
    do {
      _ = try await source.runCommand(command)
      lastCommandResult = CommandResult(name: command, error: nil)
    } catch {
      lastCommandResult = CommandResult(name: command, error: AppError.wrapping(error))
    }
    completedCommands += 1
  }

  func isRunning(_ command: String) -> Bool { runningCommand == command }
}
