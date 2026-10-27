import Foundation
import TowerCore
import TowerData

/// Demo mode's Tautulli — the monitoring capstone of the demo stack.
private enum DemoTautulliLatency {
  static let read = Duration.milliseconds(450)
  static let write = Duration.milliseconds(700)

  static func read() async { try? await Task.sleep(for: read) }
  static func write() async { try? await Task.sleep(for: write) }
}

@MainActor
final class DemoTautulliServer {
  private(set) var sessions: [TautulliSession] = DemoTautulliFixtures.sessions()
  private(set) var history: [TautulliHistoryRecord] = DemoTautulliFixtures.history()
  private var nextHistoryID = 90_100

  /// Terminating a stream in the demo does what it does on a real server: the
  /// stream goes, and it turns up in history as a stopped play.
  func terminate(sessionKey: String) {
    guard let session = sessions.first(where: { $0.sessionKey == sessionKey }) else { return }
    sessions.removeAll { $0.sessionKey == sessionKey }
    history.insert(
      TautulliHistoryRecord(
        id: nextHistoryID, date: Date(), user: session.user, userID: session.userID,
        title: session.title, subtitle: session.subtitle, mediaType: session.mediaType,
        player: session.player, platform: session.platform, decision: session.decision,
        watchStatus: .stopped, percentComplete: session.progressPercent,
        playDurationSeconds: session.viewOffsetMilliseconds / 1_000),
      at: 0)
    nextHistoryID += 1
  }

  /// Derived from the sessions rather than stored, so the header can never
  /// disagree with the list underneath it after a terminate.
  var activity: TautulliActivity {
    TautulliActivity(
      streamCount: sessions.count,
      directPlayCount: sessions.filter { $0.decision == .directPlay }.count,
      directStreamCount: sessions.filter { $0.decision == .directStream }.count,
      transcodeCount: sessions.filter { $0.decision == .transcode }.count,
      totalBandwidthKbps: sessions.reduce(0) { $0 + $1.bandwidthKbps },
      lanBandwidthKbps: sessions.filter { $0.location == .lan }
        .reduce(0) { $0 + $1.bandwidthKbps },
      wanBandwidthKbps: sessions.filter { $0.location != .lan }
        .reduce(0) { $0 + $1.bandwidthKbps },
      sessions: sessions)
  }
}

struct DemoTautulliRepository: TautulliRepositoryProtocol {
  let instance: ServiceInstance
  let server: DemoTautulliServer

  func activity() async throws -> TautulliActivity {
    await DemoTautulliLatency.read()
    return await server.activity
  }

  func terminate(sessionKey: String, message: String?) async throws {
    await DemoTautulliLatency.write()
    await server.terminate(sessionKey: sessionKey)
  }

  func history(
    filter: TautulliHistoryFilter, start: Int, length: Int
  ) async throws -> TautulliHistoryPage {
    await DemoTautulliLatency.read()
    let all = await server.history
    // Filtered here the way Tautulli filters server-side, so the demo's
    // filters compose exactly as the live ones do.
    var matches = all
    if let userID = filter.userID { matches = matches.filter { $0.userID == userID } }
    if let mediaType = filter.mediaType, !mediaType.isEmpty {
      matches = matches.filter { $0.mediaType == mediaType }
    }
    if let search = filter.search?.trimmingCharacters(in: .whitespacesAndNewlines),
      !search.isEmpty
    {
      matches = matches.filter {
        $0.title.localizedCaseInsensitiveContains(search)
          || $0.user.localizedCaseInsensitiveContains(search)
      }
    }
    let page = Array(matches.dropFirst(start).prefix(length))
    return TautulliHistoryPage(
      records: page, filteredCount: matches.count, totalCount: all.count)
  }

  func users() async throws -> [TautulliUser] {
    await DemoTautulliLatency.read()
    return DemoTautulliFixtures.users
  }

  func libraries() async throws -> [TautulliLibrary] {
    await DemoTautulliLatency.read()
    return DemoTautulliFixtures.libraries
  }
}

// MARK: - Fixtures

/// An active transcode, alongside streams that cost the server
/// nothing — the contrast is the whole point of the screen.
enum DemoTautulliFixtures {
  static func sessions() -> [TautulliSession] {
    [
      session(
        key: "312", user: "Casey", userID: 5, title: "Northern Lights - Signal Lost",
        subtitle: "S02E10", mediaType: "episode", player: "Apple TV", platform: "tvOS",
        state: .playing, decision: .directPlay, video: .directPlay, audio: .directPlay,
        location: .lan, bandwidth: 20_000, progress: 37, offset: 1_380_000,
        duration: 3_720_000, quality: "Original", transcodeProgress: nil),
      session(
        key: "313", user: "Priya", userID: 7, title: "Paper Cities", subtitle: nil,
        mediaType: "movie", player: "Chrome", platform: "Windows", state: .playing,
        decision: .transcode, video: .transcode, audio: .directStream, location: .wan,
        bandwidth: 4_000, progress: 8, offset: 480_000, duration: 6_000_000,
        quality: "4 Mbps 720p", transcodeProgress: 12),
      session(
        key: "314", user: "Sam", userID: 9, title: "Quiet Ledger - Ledger", subtitle: nil,
        mediaType: "track", player: "Sonos", platform: "Sonos", state: .paused,
        decision: .directStream, video: .unknown, audio: .directStream, location: .lan,
        bandwidth: 500, progress: 64, offset: 153_000, duration: 240_000, quality: nil,
        transcodeProgress: nil),
    ]
  }

  private static func session(
    key: String, user: String, userID: Int, title: String, subtitle: String?,
    mediaType: String, player: String, platform: String, state: TautulliPlaybackState,
    decision: TautulliStreamDecision, video: TautulliStreamDecision,
    audio: TautulliStreamDecision, location: TautulliStreamLocation, bandwidth: Int,
    progress: Int, offset: Int, duration: Int, quality: String?, transcodeProgress: Int?
  ) -> TautulliSession {
    TautulliSession(
      sessionKey: key, sessionID: "demo-\(key)", userID: userID, user: user, title: title,
      subtitle: subtitle, mediaType: mediaType, player: player, platform: platform,
      product: "Plex for \(platform)", ipAddress: location == .lan ? "192.0.2.42" : nil,
      state: state, decision: decision, videoDecision: video, audioDecision: audio,
      location: location, isSecure: true, qualityProfile: quality, bandwidthKbps: bandwidth,
      progressPercent: progress, viewOffsetMilliseconds: offset,
      durationMilliseconds: duration, transcodeProgressPercent: transcodeProgress,
      container: "mkv", videoCodec: "hevc", audioCodec: "eac3", thumbnailPath: nil)
  }

  /// Spans watched, partly watched, and stopped, across all three media types
  /// so the media filter has something to narrow.
  static func history() -> [TautulliHistoryRecord] {
    let day: TimeInterval = 86_400
    return [
      record(
        id: 90_003, daysAgo: 0.2, user: "Casey", userID: 5,
        title: "Northern Lights - Low Tide", subtitle: "S02E09", mediaType: "episode",
        status: .watched, percent: 100, seconds: 3_702, decision: .directPlay, day: day),
      record(
        id: 90_002, daysAgo: 1, user: "Priya", userID: 7, title: "Salt Harbour",
        subtitle: nil, mediaType: "movie", status: .partial, percent: 62, seconds: 4_100,
        decision: .transcode, day: day),
      record(
        id: 90_001, daysAgo: 3, user: "Sam", userID: 9, title: "Long Wave - Signal Drift",
        subtitle: nil, mediaType: "track", status: .stopped, percent: 12, seconds: 40,
        decision: .directStream, day: day),
      record(
        id: 90_000, daysAgo: 5, user: "Casey", userID: 5,
        title: "Northern Lights - Crosscurrent", subtitle: "S02E08", mediaType: "episode",
        status: .watched, percent: 100, seconds: 3_650, decision: .directPlay, day: day),
    ]
  }

  private static func record(
    id: Int, daysAgo: Double, user: String, userID: Int, title: String, subtitle: String?,
    mediaType: String, status: TautulliWatchStatus, percent: Int, seconds: Int,
    decision: TautulliStreamDecision, day: TimeInterval
  ) -> TautulliHistoryRecord {
    TautulliHistoryRecord(
      id: id, date: Date().addingTimeInterval(-daysAgo * day), user: user, userID: userID,
      title: title, subtitle: subtitle, mediaType: mediaType, player: "Apple TV",
      platform: "tvOS", decision: decision, watchStatus: status, percentComplete: percent,
      playDurationSeconds: seconds)
  }

  /// One heavy user, two occasional, one who has never watched anything — the
  /// last of those is what proves the "Never seen" case renders. Everyone
  /// streaming in `sessions()` is here, last seen at their newest play in
  /// `history()`.
  static let users: [TautulliUser] = [
    TautulliUser(
      id: 5, name: "Casey", plays: 412, totalTimeSeconds: 1_480_000,
      lastSeen: Date().addingTimeInterval(-0.2 * 86_400),
      lastPlayed: "Northern Lights - Low Tide",
      platform: "tvOS", player: "Apple TV", thumbnailPath: nil, isActive: true),
    TautulliUser(
      id: 7, name: "Priya", plays: 38, totalTimeSeconds: 210_000,
      lastSeen: Date().addingTimeInterval(-86_400), lastPlayed: "Salt Harbour",
      platform: "Windows", player: "Chrome", thumbnailPath: nil, isActive: true),
    TautulliUser(
      id: 9, name: "Sam", plays: 57, totalTimeSeconds: 14_000,
      lastSeen: Date().addingTimeInterval(-3 * 86_400), lastPlayed: "Long Wave - Signal Drift",
      platform: "tvOS", player: "Apple TV", thumbnailPath: nil, isActive: true),
    TautulliUser(
      id: 11, name: "Guest", plays: 0, totalTimeSeconds: 0, lastSeen: nil, lastPlayed: nil,
      platform: nil, player: nil, thumbnailPath: nil, isActive: false),
  ]

  /// Each last accessed at its newest play in `history()`.
  static let libraries: [TautulliLibrary] = [
    TautulliLibrary(
      id: 1, name: "Movies", type: "movie", count: 842, parentCount: nil, childCount: nil,
      plays: 1_900, totalTimeSeconds: 8_200_000,
      lastAccessed: Date().addingTimeInterval(-86_400), thumbnailPath: nil),
    TautulliLibrary(
      id: 2, name: "TV Shows", type: "show", count: 121, parentCount: 640, childCount: 9_812,
      plays: 7_400, totalTimeSeconds: 16_400_000,
      lastAccessed: Date().addingTimeInterval(-0.2 * 86_400), thumbnailPath: nil),
    TautulliLibrary(
      id: 3, name: "Music", type: "artist", count: 94, parentCount: 610, childCount: 7_302,
      plays: 220, totalTimeSeconds: 410_000,
      lastAccessed: Date().addingTimeInterval(-3 * 86_400), thumbnailPath: nil),
  ]
}
