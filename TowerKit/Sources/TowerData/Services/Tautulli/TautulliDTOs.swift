import Foundation
import TowerCore

// Tautulli's wire types. `internal`, like every other service's DTOs.
//
// **Tautulli has no schema and no stable field types.** Its API v2 is one
// endpoint with a `cmd` parameter, everything comes back inside a
// `{"response": {"result": …, "message": …, "data": …}}` envelope, and the
// same field is a number in one release and a numeric *string* in the next
// (`bandwidth`, `duration`, `view_offset`, `user_id`, `section_id` have all
// been both). `TautulliNumber` below exists so one field changing shape can't
// fail the decode of a whole activity payload.
//
// The other trap is that **`result` is the only success signal**: Tautulli
// answers HTTP 200 for a bad API key, an unknown command, and a malformed
// parameter alike, with the reason in `message`. `LiveTautulliRepository`
// therefore checks the envelope, not the status code — see the comment there.

/// A number as Tautulli sends it: `1234`, `"1234"`, `"1.5"`, `""`, or absent.
///
/// Decoding to `Double` and narrowing on read, rather than one type per field:
/// Tautulli mixes integral and fractional forms for the same field
/// (`watched_status` is `0`, `0.5`, or `1`; `progress_percent` is an integer
/// that sometimes arrives as `"87"`).
struct TautulliNumber: Decodable, Sendable, Equatable {
  let value: Double?

  init(from decoder: any Decoder) throws {
    let container = try decoder.singleValueContainer()
    if container.decodeNil() {
      self.value = nil
    } else if let number = try? container.decode(Double.self) {
      self.value = number
    } else if let text = try? container.decode(String.self) {
      // "" and "n/a" both appear where Tautulli has no value; neither is a 0.
      self.value = Double(text.trimmingCharacters(in: .whitespaces))
    } else if let flag = try? container.decode(Bool.self) {
      self.value = flag ? 1 : 0
    } else {
      self.value = nil
    }
  }

  var int: Int? { value.map { Int($0) } }
  var double: Double? { value }
}

extension Optional where Wrapped == TautulliNumber {
  var int: Int? { self?.int }
  var double: Double? { self?.double }
  func int(or fallback: Int) -> Int { self?.int ?? fallback }
}

/// Tautulli's universal envelope. `data` is whatever the command returns —
/// an object, an array, or nothing at all for `terminate_session`.
struct TautulliResponseDTO<Data: Decodable & Sendable>: Decodable, Sendable {
  struct Body: Decodable, Sendable {
    let result: String?
    let message: String?
    let data: Data?
  }

  let response: Body
}

/// The envelope with its payload ignored, for commands whose `data` is either
/// absent or a bare string. `terminate_session` answers with both, depending
/// on version.
struct TautulliEmptyResponseDTO: Decodable, Sendable {
  struct Body: Decodable, Sendable {
    let result: String?
    let message: String?
  }

  let response: Body
}

// MARK: - Activity

struct TautulliActivityDTO: Decodable, Sendable {
  let stream_count: TautulliNumber?
  let stream_count_direct_play: TautulliNumber?
  let stream_count_direct_stream: TautulliNumber?
  let stream_count_transcode: TautulliNumber?
  let total_bandwidth: TautulliNumber?
  let lan_bandwidth: TautulliNumber?
  let wan_bandwidth: TautulliNumber?
  let sessions: [TautulliSessionDTO]?

  var domain: TautulliActivity {
    let sessions = (self.sessions ?? []).map(\.domain)
    return TautulliActivity(
      // Derived from the sessions when Tautulli omits the counters, so the
      // header can never disagree with the list underneath it.
      streamCount: stream_count.int ?? sessions.count,
      directPlayCount: stream_count_direct_play.int
        ?? sessions.filter { $0.decision == .directPlay }.count,
      directStreamCount: stream_count_direct_stream.int
        ?? sessions.filter { $0.decision == .directStream }.count,
      transcodeCount: stream_count_transcode.int
        ?? sessions.filter { $0.decision == .transcode }.count,
      totalBandwidthKbps: total_bandwidth.int(or: 0),
      lanBandwidthKbps: lan_bandwidth.int(or: 0),
      wanBandwidthKbps: wan_bandwidth.int(or: 0),
      sessions: sessions)
  }
}

struct TautulliSessionDTO: Decodable, Sendable {
  let session_key: TautulliNumber?
  let session_id: String?
  let user_id: TautulliNumber?
  let user: String?
  let friendly_name: String?
  let full_title: String?
  let title: String?
  let grandparent_title: String?
  let parent_media_index: TautulliNumber?
  let media_index: TautulliNumber?
  let media_type: String?
  let player: String?
  let platform: String?
  let product: String?
  let ip_address: String?
  let state: String?
  let transcode_decision: String?
  let video_decision: String?
  let audio_decision: String?
  let location: String?
  let relayed: TautulliNumber?
  let secure: TautulliNumber?
  let quality_profile: String?
  let bandwidth: TautulliNumber?
  let progress_percent: TautulliNumber?
  let view_offset: TautulliNumber?
  let duration: TautulliNumber?
  let transcode_progress: TautulliNumber?
  let container: String?
  let video_codec: String?
  let audio_codec: String?
  let thumb: String?

  var domain: TautulliSession {
    TautulliSession(
      // The key is the terminate handle, so a session without one is still
      // shown — it simply cannot be stopped, and the store checks for that.
      sessionKey: session_key.int.map(String.init) ?? session_id ?? "",
      sessionID: session_id,
      userID: user_id.int,
      user: friendly_name?.nonEmpty ?? user?.nonEmpty ?? "Unknown user",
      title: full_title?.nonEmpty ?? title?.nonEmpty ?? "Untitled",
      subtitle: episodeContext,
      mediaType: media_type,
      player: player?.nonEmpty ?? "Unknown player",
      platform: platform?.nonEmpty,
      product: product?.nonEmpty,
      ipAddress: ip_address?.nonEmpty,
      state: TautulliPlaybackState(apiValue: state),
      decision: TautulliStreamDecision(apiValue: transcode_decision),
      videoDecision: TautulliStreamDecision(apiValue: video_decision),
      audioDecision: TautulliStreamDecision(apiValue: audio_decision),
      location: TautulliStreamLocation(
        apiValue: location, isRelayed: (relayed.int ?? 0) != 0),
      isSecure: (secure.int ?? 0) != 0,
      qualityProfile: quality_profile?.nonEmpty,
      bandwidthKbps: bandwidth.int(or: 0),
      progressPercent: progress_percent.int(or: 0),
      viewOffsetMilliseconds: view_offset.int(or: 0),
      durationMilliseconds: duration.int(or: 0),
      // Only meaningful while something is actually transcoding; Tautulli
      // sends 0 for a direct play, which would render as a stalled transcode.
      transcodeProgressPercent: TautulliStreamDecision(apiValue: transcode_decision)
        == .transcode ? transcode_progress.int : nil,
      container: container?.nonEmpty,
      videoCodec: video_codec?.nonEmpty,
      audioCodec: audio_codec?.nonEmpty,
      thumbnailPath: thumb?.nonEmpty)
  }

  /// "S02E04" for an episode, nothing for anything else. `full_title` already
  /// carries the show's name, so repeating it here would read twice.
  private var episodeContext: String? {
    guard (media_type ?? "").lowercased() == "episode" else { return nil }
    guard let season = parent_media_index.int, let episode = media_index.int else {
      return grandparent_title?.nonEmpty
    }
    return String(format: "S%02dE%02d", season, episode)
  }
}

extension String {
  /// Tautulli sends `""` where it means "nothing", constantly.
  var nonEmpty: String? {
    let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }
}

// MARK: - History

/// Tautulli's DataTables-shaped page, used by every `*_table` command.
struct TautulliTableDTO<Row: Decodable & Sendable>: Decodable, Sendable {
  let data: [Row]?
  let recordsFiltered: TautulliNumber?
  let recordsTotal: TautulliNumber?
}

struct TautulliHistoryRowDTO: Decodable, Sendable {
  let id: TautulliNumber?
  let reference_id: TautulliNumber?
  let date: TautulliNumber?
  let user: String?
  let friendly_name: String?
  let user_id: TautulliNumber?
  let full_title: String?
  let title: String?
  let grandparent_title: String?
  let parent_media_index: TautulliNumber?
  let media_index: TautulliNumber?
  let media_type: String?
  let player: String?
  let platform: String?
  let transcode_decision: String?
  let watched_status: TautulliNumber?
  let percent_complete: TautulliNumber?
  let duration: TautulliNumber?

  var domain: TautulliHistoryRecord {
    TautulliHistoryRecord(
      id: id.int ?? reference_id.int ?? 0,
      // Tautulli's dates are Unix seconds, and it sends them as strings.
      date: date.double.map { Date(timeIntervalSince1970: $0) },
      user: friendly_name?.nonEmpty ?? user?.nonEmpty ?? "Unknown user",
      userID: user_id.int,
      title: full_title?.nonEmpty ?? title?.nonEmpty ?? "Untitled",
      subtitle: episodeContext,
      mediaType: media_type,
      player: player?.nonEmpty,
      platform: platform?.nonEmpty,
      decision: TautulliStreamDecision(apiValue: transcode_decision),
      watchStatus: TautulliWatchStatus(apiValue: watched_status.double),
      percentComplete: percent_complete.int(or: 0),
      // `duration` on a history row is how long the play lasted, in seconds,
      // not the media's runtime.
      playDurationSeconds: duration.int(or: 0))
  }

  private var episodeContext: String? {
    guard (media_type ?? "").lowercased() == "episode" else { return nil }
    guard let season = parent_media_index.int, let episode = media_index.int else {
      return grandparent_title?.nonEmpty
    }
    return String(format: "S%02dE%02d", season, episode)
  }
}

// MARK: - Users

struct TautulliUserRowDTO: Decodable, Sendable {
  let user_id: TautulliNumber?
  let friendly_name: String?
  let username: String?
  let plays: TautulliNumber?
  let duration: TautulliNumber?
  let last_seen: TautulliNumber?
  let last_played: String?
  let platform: String?
  let player: String?
  let user_thumb: String?
  let thumb: String?
  let is_active: TautulliNumber?

  var domain: TautulliUser {
    TautulliUser(
      id: user_id.int ?? 0,
      name: friendly_name?.nonEmpty ?? username?.nonEmpty ?? "Unknown user",
      plays: plays.int(or: 0),
      totalTimeSeconds: duration.int(or: 0),
      lastSeen: last_seen.double.map { Date(timeIntervalSince1970: $0) },
      lastPlayed: last_played?.nonEmpty,
      platform: platform?.nonEmpty,
      player: player?.nonEmpty,
      thumbnailPath: user_thumb?.nonEmpty ?? thumb?.nonEmpty,
      // Absent on older builds, where every returned user is active.
      isActive: (is_active.int ?? 1) != 0)
  }
}

// MARK: - Libraries

struct TautulliLibraryRowDTO: Decodable, Sendable {
  let section_id: TautulliNumber?
  let section_name: String?
  let section_type: String?
  let count: TautulliNumber?
  let parent_count: TautulliNumber?
  let child_count: TautulliNumber?
  let plays: TautulliNumber?
  let duration: TautulliNumber?
  let last_accessed: TautulliNumber?
  let thumb: String?

  var domain: TautulliLibrary {
    TautulliLibrary(
      id: section_id.int ?? 0,
      name: section_name?.nonEmpty ?? "Untitled library",
      type: section_type?.nonEmpty,
      count: count.int(or: 0),
      parentCount: parent_count.int,
      childCount: child_count.int,
      plays: plays.int(or: 0),
      totalTimeSeconds: duration.int(or: 0),
      lastAccessed: last_accessed.double.map { Date(timeIntervalSince1970: $0) },
      thumbnailPath: thumb?.nonEmpty)
  }
}
