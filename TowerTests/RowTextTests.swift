import Foundation
import Testing
import TowerCore

@testable import Tower

/// Text a row builds from its model, where a missing or repeated value would
/// otherwise reach the screen as a stray dash or a doubled word.
@MainActor
@Suite
struct RowTextTests {
  private func disk(fsUsed: Int64?, fsSize: Int64?, size: Int64?) -> ArrayDisk {
    ArrayDisk(
      id: "disk", idx: 0, name: "parity", device: "sdb", status: "DISK_OK", temp: 30,
      size: size, fsFree: nil, fsUsed: fsUsed, fsSize: fsSize, fsType: nil,
      rotational: true, numReads: 0, numWrites: 0, numErrors: 0, type: "PARITY")
  }

  @Test func aDiskWithoutAFilesystemShowsItsCapacityAlone() {
    let parity = disk(fsUsed: nil, fsSize: nil, size: 12_000_000_000)
    #expect(parity.capacityLine == Formatters.kilobytes(12_000_000_000))
  }

  @Test func aMountedDiskShowsUsedOfCapacity() {
    let data = disk(fsUsed: 4_000_000_000, fsSize: 12_000_000_000, size: 12_000_000_000)
    #expect(
      data.capacityLine
        == "\(Formatters.kilobytes(4_000_000_000)) of \(Formatters.kilobytes(12_000_000_000))")
  }

  private func request(
    status: RequestStatus, media: MediaAvailability, requestedBy: String? = "Alex",
    seasons: [Int] = []
  ) -> OverseerrRequest {
    OverseerrRequest(
      id: 1, status: status, mediaType: .movie, mediaID: 1, tmdbID: 700_001, tvdbID: nil,
      mediaStatus: media, requestedBy: requestedBy, requestedByAvatarURL: nil,
      createdAt: nil, updatedAt: nil, is4K: false, seasons: seasons, title: "Example")
  }

  @Test func aRequestWhoseMediaReadsTheSameSaysItOnce() {
    let row = OverseerrRequestRow(request: request(status: .pending, media: .pending))
    #expect(row.mediaStatus == nil)
    #expect(row.accessibilityLabel == "Example, Pending, Requested by Alex")
  }

  @Test func aRequestWhoseMediaDiffersSaysBoth() {
    let row = OverseerrRequestRow(request: request(status: .approved, media: .processing))
    #expect(row.mediaStatus == MediaAvailability.processing.displayName)
    #expect(
      row.accessibilityLabel
        == "Example, Approved, \(MediaAvailability.processing.displayName), Requested by Alex")
  }

  @Test func aRequestWithoutARequesterOpensWithoutASeparator() {
    let row = OverseerrRequestRow(
      request: request(status: .pending, media: .pending, requestedBy: nil, seasons: [2]))
    #expect(row.detailLine == "Season 2")
  }

  @Test func aRequestWithARequesterSeparatesEachPart() {
    let row = OverseerrRequestRow(
      request: request(status: .pending, media: .pending, seasons: [1, 2, 3]))
    #expect(row.detailLine == "Alex · Seasons 1–3")
  }
}
