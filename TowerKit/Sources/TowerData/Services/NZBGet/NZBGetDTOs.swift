import Foundation
import TowerCore

// NZBGet's wire types. `internal`, like every other service's DTOs.
//
// NZBGet's JSON uses PascalCase keys, so each of these spells its own
// `CodingKeys`: the shared decoder sets no key decoding strategy.

struct NZBGroupDTO: Decodable, Sendable {
  let nzbID: Int
  let nzbName: String?
  let status: String?
  let category: String?
  let fileSizeLo: Int64?
  let fileSizeHi: Int64?
  let fileSizeMB: Int64?
  let remainingSizeLo: Int64?
  let remainingSizeHi: Int64?
  let remainingSizeMB: Int64?
  let downloadedSizeLo: Int64?
  let downloadedSizeHi: Int64?
  let downloadedSizeMB: Int64?
  let maxPriority: Int?
  /// Per mille — 1000 is 100%.
  let health: Int?
  let activeDownloads: Int?

  enum CodingKeys: String, CodingKey {
    case nzbID = "NZBID"
    case nzbName = "NZBName"
    case status = "Status"
    case category = "Category"
    case fileSizeLo = "FileSizeLo"
    case fileSizeHi = "FileSizeHi"
    case fileSizeMB = "FileSizeMB"
    case remainingSizeLo = "RemainingSizeLo"
    case remainingSizeHi = "RemainingSizeHi"
    case remainingSizeMB = "RemainingSizeMB"
    case downloadedSizeLo = "DownloadedSizeLo"
    case downloadedSizeHi = "DownloadedSizeHi"
    case downloadedSizeMB = "DownloadedSizeMB"
    case maxPriority = "MaxPriority"
    case health = "Health"
    case activeDownloads = "ActiveDownloads"
  }

  var domain: NZBGroup {
    NZBGroup(
      id: nzbID,
      name: nzbName ?? "NZB \(nzbID)",
      status: NZBGroupStatus(apiValue: status),
      category: category.flatMap { $0.isEmpty ? nil : $0 },
      sizeBytes: NZBSize.bytes(lo: fileSizeLo, hi: fileSizeHi, megabytes: fileSizeMB),
      remainingBytes: NZBSize.bytes(
        lo: remainingSizeLo, hi: remainingSizeHi, megabytes: remainingSizeMB),
      downloadedBytes: NZBSize.bytes(
        lo: downloadedSizeLo, hi: downloadedSizeHi, megabytes: downloadedSizeMB),
      priority: NZBPriority(rawValue: maxPriority ?? 0),
      health: health.map { Double($0) / 1_000 },
      activeDownloads: activeDownloads ?? 0)
  }
}

struct NZBHistoryDTO: Decodable, Sendable {
  let nzbID: Int
  let name: String?
  let status: String?
  let category: String?
  let fileSizeLo: Int64?
  let fileSizeHi: Int64?
  let fileSizeMB: Int64?
  /// Unix seconds.
  let historyTime: Int64?
  let downloadTimeSec: Int64?

  enum CodingKeys: String, CodingKey {
    case nzbID = "NZBID"
    case name = "Name"
    case status = "Status"
    case category = "Category"
    case fileSizeLo = "FileSizeLo"
    case fileSizeHi = "FileSizeHi"
    case fileSizeMB = "FileSizeMB"
    case historyTime = "HistoryTime"
    case downloadTimeSec = "DownloadTimeSec"
  }

  var domain: NZBHistoryItem {
    let status = self.status ?? ""
    return NZBHistoryItem(
      id: nzbID,
      name: name ?? "NZB \(nzbID)",
      status: status,
      // NZBGet's status is compound — `SUCCESS/ALL`, `FAILURE/PAR`,
      // `DELETED/MANUAL`. Only the first segment says whether it worked, and
      // the whole string is kept because *which part* failed is the useful bit.
      isSuccess: status.split(separator: "/").first.map { $0 == "SUCCESS" } ?? false,
      category: category.flatMap { $0.isEmpty ? nil : $0 },
      sizeBytes: NZBSize.bytes(lo: fileSizeLo, hi: fileSizeHi, megabytes: fileSizeMB),
      completedAt: historyTime.flatMap {
        $0 > 0 ? Date(timeIntervalSince1970: TimeInterval($0)) : nil
      },
      downloadSeconds: downloadTimeSec.flatMap { $0 > 0 ? TimeInterval($0) : nil })
  }
}

struct NZBStatusDTO: Decodable, Sendable {
  let downloadRate: Int64?
  let remainingSizeLo: Int64?
  let remainingSizeHi: Int64?
  let remainingSizeMB: Int64?
  let downloadedSizeLo: Int64?
  let downloadedSizeHi: Int64?
  let downloadedSizeMB: Int64?
  let freeDiskSpaceLo: Int64?
  let freeDiskSpaceHi: Int64?
  let freeDiskSpaceMB: Int64?
  let downloadPaused: Bool?
  /// Bytes per second; 0 means unlimited.
  let downloadLimit: Int64?
  let upTimeSec: Int64?
  let postJobCount: Int?

  enum CodingKeys: String, CodingKey {
    case downloadRate = "DownloadRate"
    case remainingSizeLo = "RemainingSizeLo"
    case remainingSizeHi = "RemainingSizeHi"
    case remainingSizeMB = "RemainingSizeMB"
    case downloadedSizeLo = "DownloadedSizeLo"
    case downloadedSizeHi = "DownloadedSizeHi"
    case downloadedSizeMB = "DownloadedSizeMB"
    case freeDiskSpaceLo = "FreeDiskSpaceLo"
    case freeDiskSpaceHi = "FreeDiskSpaceHi"
    case freeDiskSpaceMB = "FreeDiskSpaceMB"
    case downloadPaused = "DownloadPaused"
    case downloadLimit = "DownloadLimit"
    case upTimeSec = "UpTimeSec"
    case postJobCount = "PostJobCount"
  }

  func domain(version: String?) -> NZBServerStatus {
    NZBServerStatus(
      downloadRateBytesPerSecond: downloadRate ?? 0,
      remainingBytes: NZBSize.bytes(
        lo: remainingSizeLo, hi: remainingSizeHi, megabytes: remainingSizeMB),
      downloadedBytes: NZBSize.bytes(
        lo: downloadedSizeLo, hi: downloadedSizeHi, megabytes: downloadedSizeMB),
      freeDiskSpaceBytes: NZBSize.bytes(
        lo: freeDiskSpaceLo, hi: freeDiskSpaceHi, megabytes: freeDiskSpaceMB),
      isDownloadPaused: downloadPaused ?? false,
      // 0 is NZBGet's "no limit"; rendering it as "0 B/s" would say the
      // opposite of what it means.
      speedLimitBytesPerSecond: (downloadLimit ?? 0) > 0 ? downloadLimit : nil,
      uptime: upTimeSec.flatMap { $0 > 0 ? TimeInterval($0) : nil },
      postJobCount: postJobCount ?? 0,
      version: version)
  }
}
