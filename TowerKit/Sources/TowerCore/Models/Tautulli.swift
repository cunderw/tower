import Foundation

// Tautulli's domain types. Plain `TowerCore`, like every other service.
//
// Tautulli is the only service in the stack with **one endpoint and no
// schema**: everything is `GET /api/v2?cmd=<command>`, and it answers HTTP 200
// even for a rejected API key. Two consequences show up here rather than in
// the DTOs. First, `TautulliStreamDecision` and `TautulliPlaybackState` are
// closed enums with an `unknown` case, because the wire values are free
// strings Tautulli has renamed between versions. Second, everything numeric is
// optional at the boundary and defaulted here — Tautulli sends numbers as
// strings about as often as it sends them as numbers, and a stream that is
// missing its bandwidth is still a stream worth showing.

/// What Tautulli is doing right now: the counts, the bandwidth, and one entry
/// per playing stream.
public struct TautulliActivity: Equatable, Sendable {
  public let streamCount: Int
  public let directPlayCount: Int
  public let directStreamCount: Int
  public let transcodeCount: Int
  /// Kilobits per second, which is Tautulli's own unit for all three.
  public let totalBandwidthKbps: Int
  public let lanBandwidthKbps: Int
  public let wanBandwidthKbps: Int
  public let sessions: [TautulliSession]

  public init(
    streamCount: Int, directPlayCount: Int, directStreamCount: Int, transcodeCount: Int,
    totalBandwidthKbps: Int, lanBandwidthKbps: Int, wanBandwidthKbps: Int,
    sessions: [TautulliSession]
  ) {
    self.streamCount = streamCount
    self.directPlayCount = directPlayCount
    self.directStreamCount = directStreamCount
    self.transcodeCount = transcodeCount
    self.totalBandwidthKbps = totalBandwidthKbps
    self.lanBandwidthKbps = lanBandwidthKbps
    self.wanBandwidthKbps = wanBandwidthKbps
    self.sessions = sessions
  }

  public static let empty = TautulliActivity(
    streamCount: 0, directPlayCount: 0, directStreamCount: 0, transcodeCount: 0,
    totalBandwidthKbps: 0, lanBandwidthKbps: 0, wanBandwidthKbps: 0, sessions: [])
}

/// How the server is delivering one stream.
///
/// The distinction people actually care about: a transcode is costing the
/// server CPU, a direct play is costing it nothing.
public enum TautulliStreamDecision: String, Sendable, Hashable, CaseIterable {
  case directPlay
  case directStream
  case transcode
  case unknown

  /// Tautulli's `transcode_decision`, which says `copy` where the UI says
  /// "direct stream" — the one rename worth normalising rather than showing
  /// a word no Plex screen uses.
  public init(apiValue: String?) {
    switch (apiValue ?? "").lowercased().replacingOccurrences(of: " ", with: "") {
    case "directplay": self = .directPlay
    case "copy", "directstream": self = .directStream
    case "transcode": self = .transcode
    default: self = .unknown
    }
  }

  public var displayName: String {
    switch self {
    case .directPlay: "Direct Play"
    case .directStream: "Direct Stream"
    case .transcode: "Transcode"
    case .unknown: "Unknown"
    }
  }
}

public enum TautulliPlaybackState: String, Sendable, Hashable {
  case playing
  case paused
  case buffering
  case unknown

  public init(apiValue: String?) {
    self = TautulliPlaybackState(rawValue: (apiValue ?? "").lowercased()) ?? .unknown
  }

  public var displayName: String {
    switch self {
    case .playing: "Playing"
    case .paused: "Paused"
    case .buffering: "Buffering"
    case .unknown: "Unknown"
    }
  }
}

/// Where a stream is coming from. Relayed traffic goes through Plex's own
/// relay, which is capped at 2 Mbps — worth surfacing, because it looks like
/// a bad transcode from the server's side.
public enum TautulliStreamLocation: String, Sendable, Hashable {
  case lan
  case wan
  case relayed
  case unknown

  public init(apiValue: String?, isRelayed: Bool) {
    if isRelayed {
      self = .relayed
      return
    }
    self = TautulliStreamLocation(rawValue: (apiValue ?? "").lowercased()) ?? .unknown
  }

  public var displayName: String {
    switch self {
    case .lan: "Local"
    case .wan: "Remote"
    case .relayed: "Relayed"
    case .unknown: "Unknown"
    }
  }
}

/// One playing stream.
public struct TautulliSession: Equatable, Sendable, Identifiable {
  /// Tautulli's `session_key`, and the handle `terminate_session` takes.
  public let sessionKey: String
  public let sessionID: String?
  public let userID: Int?
  public let user: String
  public let title: String
  /// "Show · S02E04" style context, when the media has any. `nil` for a film.
  public let subtitle: String?
  public let mediaType: String?
  public let player: String
  public let platform: String?
  public let product: String?
  public let ipAddress: String?
  public let state: TautulliPlaybackState
  public let decision: TautulliStreamDecision
  public let videoDecision: TautulliStreamDecision
  public let audioDecision: TautulliStreamDecision
  public let location: TautulliStreamLocation
  public let isSecure: Bool
  public let qualityProfile: String?
  public let bandwidthKbps: Int
  /// 0–100.
  public let progressPercent: Int
  public let viewOffsetMilliseconds: Int
  public let durationMilliseconds: Int
  public let transcodeProgressPercent: Int?
  public let container: String?
  public let videoCodec: String?
  public let audioCodec: String?
  public let thumbnailPath: String?

  public var id: String { sessionKey }

  public init(
    sessionKey: String, sessionID: String?, userID: Int?, user: String, title: String,
    subtitle: String?, mediaType: String?, player: String, platform: String?, product: String?,
    ipAddress: String?, state: TautulliPlaybackState, decision: TautulliStreamDecision,
    videoDecision: TautulliStreamDecision, audioDecision: TautulliStreamDecision,
    location: TautulliStreamLocation, isSecure: Bool, qualityProfile: String?,
    bandwidthKbps: Int, progressPercent: Int, viewOffsetMilliseconds: Int,
    durationMilliseconds: Int, transcodeProgressPercent: Int?, container: String?,
    videoCodec: String?, audioCodec: String?, thumbnailPath: String?
  ) {
    self.sessionKey = sessionKey
    self.sessionID = sessionID
    self.userID = userID
    self.user = user
    self.title = title
    self.subtitle = subtitle
    self.mediaType = mediaType
    self.player = player
    self.platform = platform
    self.product = product
    self.ipAddress = ipAddress
    self.state = state
    self.decision = decision
    self.videoDecision = videoDecision
    self.audioDecision = audioDecision
    self.location = location
    self.isSecure = isSecure
    self.qualityProfile = qualityProfile
    self.bandwidthKbps = bandwidthKbps
    self.progressPercent = progressPercent
    self.viewOffsetMilliseconds = viewOffsetMilliseconds
    self.durationMilliseconds = durationMilliseconds
    self.transcodeProgressPercent = transcodeProgressPercent
    self.container = container
    self.videoCodec = videoCodec
    self.audioCodec = audioCodec
    self.thumbnailPath = thumbnailPath
  }

  /// A stream is only costing the server real work when *something* is being
  /// transcoded — Plex reports the overall decision as `transcode` when only
  /// the audio is, which is a much cheaper thing than a video transcode.
  public var isTranscoding: Bool {
    decision == .transcode || videoDecision == .transcode || audioDecision == .transcode
  }

  public var isVideoTranscoding: Bool { videoDecision == .transcode }
}

// MARK: - History

public enum TautulliWatchStatus: Sendable, Hashable {
  case watched
  case partial
  case stopped

  /// Tautulli's `watched_status` is `1`, `0.5`, or `0` — a fraction, not a
  /// flag, because "watched" means past the server's threshold.
  public init(apiValue: Double?) {
    switch apiValue ?? 0 {
    case 1: self = .watched
    case 0.5..<1: self = .partial
    default: self = .stopped
    }
  }

  public var displayName: String {
    switch self {
    case .watched: "Watched"
    case .partial: "Partly watched"
    case .stopped: "Stopped"
    }
  }
}

public struct TautulliHistoryRecord: Equatable, Sendable, Identifiable {
  public let id: Int
  public let date: Date?
  public let user: String
  public let userID: Int?
  public let title: String
  public let subtitle: String?
  public let mediaType: String?
  public let player: String?
  public let platform: String?
  public let decision: TautulliStreamDecision
  public let watchStatus: TautulliWatchStatus
  public let percentComplete: Int
  /// How long this play actually lasted, which is not the media's runtime.
  public let playDurationSeconds: Int

  public init(
    id: Int, date: Date?, user: String, userID: Int?, title: String, subtitle: String?,
    mediaType: String?, player: String?, platform: String?, decision: TautulliStreamDecision,
    watchStatus: TautulliWatchStatus, percentComplete: Int, playDurationSeconds: Int
  ) {
    self.id = id
    self.date = date
    self.user = user
    self.userID = userID
    self.title = title
    self.subtitle = subtitle
    self.mediaType = mediaType
    self.player = player
    self.platform = platform
    self.decision = decision
    self.watchStatus = watchStatus
    self.percentComplete = percentComplete
    self.playDurationSeconds = playDurationSeconds
  }
}

/// A page of history, plus the totals its screen needs to say "50 of 1,204".
public struct TautulliHistoryPage: Equatable, Sendable {
  public let records: [TautulliHistoryRecord]
  public let filteredCount: Int
  public let totalCount: Int

  public init(records: [TautulliHistoryRecord], filteredCount: Int, totalCount: Int) {
    self.records = records
    self.filteredCount = filteredCount
    self.totalCount = totalCount
  }
}

/// What the history screen can narrow by. Deliberately the three Tautulli
/// filters that are cheap on its side — it filters in SQL, and a client-side
/// filter over one page would silently only search the page.
public struct TautulliHistoryFilter: Equatable, Sendable {
  public var userID: Int?
  public var mediaType: String?
  public var search: String?

  public init(userID: Int? = nil, mediaType: String? = nil, search: String? = nil) {
    self.userID = userID
    self.mediaType = mediaType
    self.search = search
  }

  public static let none = TautulliHistoryFilter()
}

// MARK: - Users and libraries

public struct TautulliUser: Equatable, Sendable, Identifiable {
  public let id: Int
  public let name: String
  public let plays: Int
  public let totalTimeSeconds: Int
  public let lastSeen: Date?
  public let lastPlayed: String?
  public let platform: String?
  public let player: String?
  public let thumbnailPath: String?
  public let isActive: Bool

  public init(
    id: Int, name: String, plays: Int, totalTimeSeconds: Int, lastSeen: Date?,
    lastPlayed: String?, platform: String?, player: String?, thumbnailPath: String?,
    isActive: Bool
  ) {
    self.id = id
    self.name = name
    self.plays = plays
    self.totalTimeSeconds = totalTimeSeconds
    self.lastSeen = lastSeen
    self.lastPlayed = lastPlayed
    self.platform = platform
    self.player = player
    self.thumbnailPath = thumbnailPath
    self.isActive = isActive
  }
}

public struct TautulliLibrary: Equatable, Sendable, Identifiable {
  public let id: Int
  public let name: String
  /// Plex's own section type: `movie`, `show`, `artist`, `photo`.
  public let type: String?
  /// Top-level items: films, or shows.
  public let count: Int
  /// Seasons for a show library, albums for a music one; `nil` where the type
  /// has no middle tier.
  public let parentCount: Int?
  /// Episodes, or tracks.
  public let childCount: Int?
  public let plays: Int
  public let totalTimeSeconds: Int
  public let lastAccessed: Date?
  public let thumbnailPath: String?

  public init(
    id: Int, name: String, type: String?, count: Int, parentCount: Int?, childCount: Int?,
    plays: Int, totalTimeSeconds: Int, lastAccessed: Date?, thumbnailPath: String?
  ) {
    self.id = id
    self.name = name
    self.type = type
    self.count = count
    self.parentCount = parentCount
    self.childCount = childCount
    self.plays = plays
    self.totalTimeSeconds = totalTimeSeconds
    self.lastAccessed = lastAccessed
    self.thumbnailPath = thumbnailPath
  }

  /// "Movies", "TV Shows", "Music" — Plex's section types spelled the way its
  /// own sidebar spells them.
  public var typeDisplayName: String {
    switch (type ?? "").lowercased() {
    case "movie": "Movies"
    case "show": "TV Shows"
    case "artist": "Music"
    case "photo": "Photos"
    default: "Library"
    }
  }
}
