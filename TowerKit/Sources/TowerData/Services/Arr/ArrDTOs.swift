import Foundation
import TowerCore

// The *arr wire shapes, and their mapping into `TowerCore`. **Internal to
// `TowerData`** — nothing here crosses the repository boundary, which is the
// same quarantine the Apollo types live under.
//
// Two rules run through the whole file, both the custom-scalar rule
// applied to REST:
//
// 1. **Everything the API declares nullable is optional here**, even where a
//    field is "obviously" always sent. These services are third-party and ship
//    new versions constantly; one missing string must cost a row's subtitle,
//    not the screen.
// 2. **Enums arrive as `String?` and are mapped through an `init(apiValue:)`
//    that has an `.unknown` case.** A `RawRepresentable` decode would throw on
//    a member added upstream — turning "Sonarr added a queue state" into "the
//    queue tab is broken".

// MARK: - Queue

struct QueuePageDTO: Decodable, Sendable {
  let page: Int?
  let pageSize: Int?
  let totalRecords: Int?
  let records: [QueueItemDTO]?

  var domain: ArrQueuePage {
    ArrQueuePage(
      items: (records ?? []).map(\.domain),
      page: page ?? 1,
      pageSize: pageSize ?? (records?.count ?? 0),
      totalRecords: totalRecords ?? (records?.count ?? 0)
    )
  }
}

struct QueueItemDTO: Decodable, Sendable {
  struct StatusMessageDTO: Decodable, Sendable {
    let title: String?
    let messages: [String]?
  }

  let id: Int
  let title: String?
  let movieId: Int?
  let seriesId: Int?
  let episodeId: Int?
  let albumId: Int?
  /// The API sends sizes as JSON numbers with a fractional part
  /// (`1234567.0`) — decoding them as `Int64` throws, which is why these are
  /// `Double?`.
  let size: Double?
  let sizeleft: Double?
  let timeleft: String?
  let estimatedCompletionTime: Date?
  let status: String?
  let trackedDownloadStatus: String?
  let trackedDownloadState: String?
  let statusMessages: [StatusMessageDTO]?
  let errorMessage: String?
  let `protocol`: String?
  let downloadClient: String?
  /// The client's own id, such as an NZB id. `downloadId` on the
  /// wire, and the join key for the queue's links to download client screens.
  let downloadId: String?
  let indexer: String?
  let quality: QualityModelDTO?

  var domain: ArrQueueItem {
    ArrQueueItem(
      id: id,
      title: title,
      // One field in the domain, three on the wire: whichever service answered,
      // this is "the library entry this download belongs to".
      mediaID: movieId ?? seriesId ?? albumId,
      episodeID: episodeId,
      sizeBytes: size.map { Int64($0) },
      sizeLeftBytes: sizeleft.map { Int64($0) },
      timeLeft: timeleft,
      estimatedCompletionTime: estimatedCompletionTime,
      status: ArrQueueStatus(apiValue: status),
      trackedStatus: ArrTrackedDownloadStatus(apiValue: trackedDownloadStatus),
      trackedState: ArrTrackedDownloadState(apiValue: trackedDownloadState),
      errorMessage: errorMessage,
      // Flattened: the nesting (a title plus its messages) is a detail of how
      // the *arr groups warnings, and every consumer wants the lines.
      statusMessages: (statusMessages ?? []).flatMap { message -> [String] in
        let lines = message.messages ?? []
        guard lines.isEmpty else { return lines }
        return message.title.map { [$0] } ?? []
      },
      downloadProtocol: ArrDownloadProtocol(apiValue: `protocol`),
      downloadClient: downloadClient,
      downloadID: downloadId,
      indexer: indexer,
      quality: quality?.quality?.name
    )
  }
}

struct QualityModelDTO: Decodable, Sendable {
  struct QualityDTO: Decodable, Sendable {
    let id: Int?
    let name: String?
  }
  let quality: QualityDTO?
}

// MARK: - Calendar

struct CalendarEntryDTO: Decodable, Sendable {
  let id: Int
  let title: String?
  let monitored: Bool?
  let hasFile: Bool?
  // Radarr
  let year: Int?
  let inCinemas: Date?
  let physicalRelease: Date?
  let digitalRelease: Date?
  // Sonarr
  let seriesTitle: String?
  let seasonNumber: Int?
  let episodeNumber: Int?
  let airDateUtc: Date?

  var domain: ArrCalendarEntry {
    ArrCalendarEntry(
      id: id,
      // Sonarr's calendar rows are episodes: the series is the headline and the
      // episode title is the detail, which is the opposite of Radarr's shape.
      title: seriesTitle ?? title ?? "Untitled",
      subtitle: subtitle,
      // First date that exists, in the order a user cares about: when can I
      // watch it. Radarr's digital release beats its cinema date for that.
      date: airDateUtc ?? digitalRelease ?? physicalRelease ?? inCinemas,
      isMonitored: monitored ?? false,
      hasFile: hasFile ?? false
    )
  }

  private var subtitle: String? {
    if let seasonNumber, let episodeNumber {
      let code = String(format: "S%02dE%02d", seasonNumber, episodeNumber)
      return title.map { "\(code) · \($0)" } ?? code
    }
    return year.map(String.init)
  }
}

// MARK: - History

struct HistoryPageDTO: Decodable, Sendable {
  let page: Int?
  let pageSize: Int?
  let totalRecords: Int?
  let records: [HistoryRecordDTO]?

  var domain: ArrHistoryPage {
    ArrHistoryPage(
      records: (records ?? []).map(\.domain),
      page: page ?? 1,
      pageSize: pageSize ?? (records?.count ?? 0),
      totalRecords: totalRecords ?? (records?.count ?? 0)
    )
  }
}

struct HistoryRecordDTO: Decodable, Sendable {
  let id: Int
  let eventType: String?
  let sourceTitle: String?
  let movieId: Int?
  let seriesId: Int?
  let albumId: Int?
  let date: Date?
  let quality: QualityModelDTO?

  var domain: ArrHistoryRecord {
    ArrHistoryRecord(
      id: id,
      event: ArrHistoryEvent(apiValue: eventType),
      sourceTitle: sourceTitle,
      mediaID: movieId ?? seriesId ?? albumId,
      date: date,
      quality: quality?.quality?.name
    )
  }
}

// MARK: - System

struct HealthDTO: Decodable, Sendable {
  let id: Int?
  let source: String?
  let type: String?
  let message: String?
  let wikiUrl: String?

  var domain: ArrHealthCheck {
    ArrHealthCheck(
      // The API sometimes omits `id` on health rows; the source is stable
      // enough to keep a list from re-animating on every refresh.
      id: id ?? abs((source ?? message ?? "").hashValue),
      source: source,
      severity: ArrHealthSeverity(apiValue: type),
      message: message ?? "Health check reported no message.",
      // **Not `URL.init(string:)`** — see `OpenableURL`. A scheme-less
      // address parses into a URL that `Link` cannot open, which renders a
      // "Read more" that does nothing when tapped.
      wikiURL: OpenableURL.from(wikiUrl)
    )
  }
}

struct DiskSpaceDTO: Decodable, Sendable {
  let path: String?
  let label: String?
  let freeSpace: Int64?
  let totalSpace: Int64?

  var domain: ArrDiskSpace {
    ArrDiskSpace(
      path: path ?? "—",
      // The label is empty rather than absent on most mounts; an empty string
      // renders as a gap the user reads as a bug.
      label: label?.isEmpty == true ? nil : label,
      freeBytes: freeSpace ?? 0,
      totalBytes: totalSpace ?? 0
    )
  }
}

struct SystemStatusDTO: Decodable, Sendable {
  let appName: String?
  let instanceName: String?
  let version: String?
  let osName: String?
  let osVersion: String?
  let isDocker: Bool?
  let startTime: Date?

  var domain: ArrSystemStatus {
    ArrSystemStatus(
      appName: appName,
      instanceName: instanceName,
      version: version,
      osName: osName,
      osVersion: osVersion,
      isDocker: isDocker ?? false,
      startTime: startTime
    )
  }
}

struct CommandDTO: Decodable, Sendable {
  let id: Int
  let name: String?
  let commandName: String?
  let message: String?
  let status: String?
  let started: Date?
  let ended: Date?

  var domain: ArrCommand {
    ArrCommand(
      id: id,
      // `commandName` is the display form ("Rss Sync"); `name` is the token
      // ("RssSync"). Prefer the readable one, fall back to the token.
      name: commandName ?? name ?? "Command",
      status: ArrCommandStatus(apiValue: status),
      message: message,
      started: started,
      ended: ended
    )
  }
}

// MARK: - Pickers

struct QualityProfileDTO: Decodable, Sendable {
  let id: Int
  let name: String?

  var domain: ArrQualityProfile {
    ArrQualityProfile(id: id, name: name ?? "Profile \(id)")
  }
}

struct RootFolderDTO: Decodable, Sendable {
  let id: Int
  let path: String?
  let accessible: Bool?
  let freeSpace: Int64?

  var domain: ArrRootFolder {
    ArrRootFolder(
      id: id,
      path: path ?? "—",
      // Absent means the service didn't say; treating that as inaccessible
      // would hide a usable folder from the add-media picker.
      isAccessible: accessible ?? true,
      freeBytes: freeSpace
    )
  }
}

struct TagDTO: Decodable, Sendable {
  let id: Int
  let label: String?

  var domain: ArrTag {
    ArrTag(id: id, label: label ?? "Tag \(id)")
  }
}
