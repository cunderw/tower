import Foundation
import TowerCore

/// The dataset demo mode's NZBGet presents.
///
/// Shaped like a real stack, following the same rule as `DemoArrFixtures`:
/// every state the UI can render appears somewhere.
///
/// **One history id is `DemoDownloadIDs.northernLightsNZB`**, which the demo
/// Sonarr queue also references. It is in history, not the queue, because
/// that Sonarr row is blocked at import: the download has already finished.
enum DemoDownloadFixtures {
  // MARK: - NZBGet

  /// An active queue with one post-processing item — the state that has no
  /// download speed and reads as stalled unless the UI distinguishes it.
  static func nzbQueue() -> [NZBGroup] {
    [
      NZBGroup(
        id: 40, name: "Winter Ledger (2022) 2160p DEMO", status: .downloading,
        category: "movies", sizeBytes: 64_424_509_440, remainingBytes: 21_474_836_480,
        downloadedBytes: 42_949_672_960, priority: .normal, health: 1, activeDownloads: 8),
      NZBGroup(
        id: 42, name: "The Long Wire S01E14 2160p DEMO", status: .queued,
        category: "tv", sizeBytes: 17_179_869_184, remainingBytes: 17_179_869_184,
        downloadedBytes: 0, priority: .high, health: 1, activeDownloads: 0),
      NZBGroup(
        id: 43, name: "Harbourmaster S01E06 1080p DEMO", status: .unpacking,
        category: "tv", sizeBytes: 3_221_225_472, remainingBytes: 0,
        downloadedBytes: 3_221_225_472, priority: .normal, health: 0.918, activeDownloads: 0),
      NZBGroup(
        id: 44, name: "Kestrel Court S02E01 1080p DEMO", status: .paused,
        category: "tv", sizeBytes: 2_147_483_648, remainingBytes: 2_147_483_648,
        downloadedBytes: 0, priority: .low, health: 1, activeDownloads: 0),
    ]
  }

  /// Three successes and one failure — the failure is the row whose Retry the
  /// demo exists to show working.
  static func nzbHistory() -> [NZBHistoryItem] {
    [
      NZBHistoryItem(
        id: 30, name: "Old Sound S01E09 1080p DEMO", status: "FAILURE/PAR",
        isSuccess: false, category: "tv", sizeBytes: 2_684_354_560,
        completedAt: Date().addingTimeInterval(-5_400), downloadSeconds: 240),
      NZBHistoryItem(
        id: DemoDownloadIDs.northernLightsNZB,
        name: "Northern Lights S02E11 1080p Usenet DEMO", status: "SUCCESS/ALL",
        isSuccess: true, category: "tv", sizeBytes: 4_294_967_296,
        completedAt: Date().addingTimeInterval(-7_200), downloadSeconds: 310),
      NZBHistoryItem(
        id: 31, name: "Tidal S01E03 1080p DEMO", status: "SUCCESS/ALL",
        isSuccess: true, category: "tv", sizeBytes: 3_758_096_384,
        completedAt: Date().addingTimeInterval(-43_200), downloadSeconds: 380),
      NZBHistoryItem(
        id: 32, name: "Signal Hill S01E11 2160p DEMO", status: "SUCCESS/ALL",
        isSuccess: true, category: "tv", sizeBytes: 9_663_676_416,
        completedAt: Date().addingTimeInterval(-129_600), downloadSeconds: 1_100),
    ]
  }
}
