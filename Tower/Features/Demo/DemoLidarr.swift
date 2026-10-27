import Foundation
import TowerCore
import TowerData

/// Demo mode's Lidarr.
private enum DemoLidarrLatency {
  static let read = Duration.milliseconds(450)
  static let write = Duration.milliseconds(700)

  static func read() async { try? await Task.sleep(for: read) }
  static func write() async { try? await Task.sleep(for: write) }
}

@MainActor
final class DemoLidarrServer {
  private(set) var artists: [LidarrArtist] = DemoLidarrFixtures.artists()
  private(set) var albums: [Int: [LidarrAlbum]] = DemoLidarrFixtures.albums()
  private(set) var tracks: [Int: [LidarrTrack]] = DemoLidarrFixtures.tracks()
  private var nextID = 90

  func replace(_ artist: LidarrArtist) {
    artists = artists.map { $0.id == artist.id ? artist : $0 }
  }

  func remove(id: Int) {
    artists.removeAll { $0.id == id }
    albums[id] = nil
  }

  func add(_ request: LidarrAddArtistRequest) -> LidarrArtist {
    let id = nextID
    nextID += 1
    let added = LidarrArtist(
      id: id, name: request.lookup.name, sortName: request.lookup.name.lowercased(),
      foreignArtistID: request.lookup.foreignArtistID, overview: request.lookup.overview,
      artistType: request.lookup.artistType, disambiguation: request.lookup.disambiguation,
      status: .continuing, isMonitored: request.isMonitored,
      qualityProfileID: request.qualityProfileID,
      metadataProfileID: request.metadataProfileID,
      path: "\(request.rootFolderPath)/\(request.lookup.name)",
      rootFolderPath: request.rootFolderPath, genres: [], tagIDs: request.tagIDs,
      added: Date(), posterURL: nil,
      // Nothing on disk yet, which is what a just-added artist looks like.
      statistics: LidarrArtistStatistics(
        albumCount: 0, trackFileCount: 0, trackCount: 0, totalTrackCount: 0,
        sizeOnDiskBytes: 0))
    artists.append(added)
    artists.sort { $0.sortName.localizedCaseInsensitiveCompare($1.sortName) == .orderedAscending }
    albums[id] = []
    return added
  }

  func setAlbumMonitored(_ isMonitored: Bool, ids: [Int]) {
    for (artistID, list) in albums {
      albums[artistID] = list.map {
        ids.contains($0.id) ? $0.settingMonitored(isMonitored) : $0
      }
    }
  }
}

struct DemoLidarrRepository: LidarrRepositoryProtocol {
  let instance: ServiceInstance
  let server: DemoLidarrServer
  /// The shared *arr dataset, so Lidarr's queue, calendar, and history come
  /// from the same place Radarr's and Sonarr's do — which is what makes the
  /// shell's reuse visible in the demo rather than only in the code.
  let arrServer: DemoArrServer

  var arr: ArrClientCore {
    // Never used: every shared endpoint is answered below.
    ArrClientCore(client: ServiceHTTPClient(instance: instance), apiPath: "api/v1")
  }

  func artists() async throws -> [LidarrArtist] {
    await DemoLidarrLatency.read()
    return await server.artists
  }

  func artist(id: Int) async throws -> LidarrArtist {
    await DemoLidarrLatency.read()
    guard let match = await server.artists.first(where: { $0.id == id }) else {
      throw AppError.unknown("That artist is no longer in \(instance.name).")
    }
    return match
  }

  func albums(artistID: Int) async throws -> [LidarrAlbum] {
    await DemoLidarrLatency.read()
    return await server.albums[artistID] ?? []
  }

  func tracks(albumID: Int) async throws -> [LidarrTrack] {
    await DemoLidarrLatency.read()
    return await server.tracks[albumID] ?? []
  }

  func lookup(term: String) async throws -> [LidarrArtistLookup] {
    await DemoLidarrLatency.read()
    return DemoLidarrFixtures.lookups(matching: term, existing: await server.artists)
  }

  @discardableResult
  func add(_ request: LidarrAddArtistRequest) async throws -> LidarrArtist {
    await DemoLidarrLatency.write()
    return await server.add(request)
  }

  @discardableResult
  func update(_ artist: LidarrArtist, with edit: LidarrArtistEdit) async throws -> LidarrArtist {
    await DemoLidarrLatency.write()
    let updated = artist.applying(edit)
    await server.replace(updated)
    return updated
  }

  func delete(id: Int, deleteFiles: Bool, addImportExclusion: Bool) async throws {
    await DemoLidarrLatency.write()
    await server.remove(id: id)
  }

  func setAlbumMonitored(_ isMonitored: Bool, albumIDs: [Int]) async throws {
    await DemoLidarrLatency.write()
    await server.setAlbumMonitored(isMonitored, ids: albumIDs)
  }

  func metadataProfiles() async throws -> [LidarrMetadataProfile] {
    DemoLidarrFixtures.metadataProfiles
  }

  func qualityProfiles() async throws -> [ArrQualityProfile] {
    DemoLidarrFixtures.qualityProfiles
  }

  func rootFolders() async throws -> [ArrRootFolder] { DemoLidarrFixtures.rootFolders }
  func tags() async throws -> [ArrTag] { DemoArrFixtures.tags }

  func releases(artistID: Int) async throws -> [ArrRelease] {
    await DemoLidarrLatency.read()
    let name = await server.artists.first { $0.id == artistID }?.name ?? "Unknown Artist"
    return DemoArrFixtures.releases(for: name)
  }

  func releases(albumID: Int) async throws -> [ArrRelease] {
    await DemoLidarrLatency.read()
    let album = await server.albums.values.flatMap { $0 }.first { $0.id == albumID }
    return DemoArrFixtures.releases(for: album?.title ?? "Unknown Album")
  }

  func grab(_ release: ArrRelease) async throws {
    await DemoLidarrLatency.write()
    await arrServer.grab(release)
  }

  func searchArtist(id: Int) async throws { await DemoLidarrLatency.write() }
  func searchAlbum(id: Int) async throws { await DemoLidarrLatency.write() }

  // MARK: - The shared surface

  func queue() async throws -> ArrQueuePage {
    await DemoLidarrLatency.read()
    let items = await arrServer.queue
    return ArrQueuePage(items: items, page: 1, pageSize: 50, totalRecords: items.count)
  }

  func removeQueueItem(id: Int, removeFromClient: Bool, blocklist: Bool) async throws {
    await DemoLidarrLatency.write()
    await arrServer.removeQueueItem(id: id)
  }

  func calendar(start: Date, end: Date) async throws -> [ArrCalendarEntry] {
    await DemoLidarrLatency.read()
    return DemoLidarrFixtures.calendar()
  }

  func history(page: Int) async throws -> ArrHistoryPage {
    await DemoLidarrLatency.read()
    let records = await arrServer.history
    return ArrHistoryPage(records: records, page: 1, pageSize: 50, totalRecords: records.count)
  }

  func health() async throws -> [ArrHealthCheck] {
    await DemoLidarrLatency.read()
    return []
  }

  func diskSpace() async throws -> [ArrDiskSpace] {
    await DemoLidarrLatency.read()
    return DemoArrFixtures.disks
  }

  func systemStatus() async throws -> ArrSystemStatus {
    await DemoLidarrLatency.read()
    return DemoArrFixtures.status(app: "Lidarr", version: "2.1.7.4030")
  }

  @discardableResult
  func runCommand(_ name: String) async throws -> ArrCommand {
    await DemoLidarrLatency.write()
    return ArrCommand(id: 1, name: name, status: .queued, message: nil, started: Date(), ended: nil)
  }
}

extension LidarrArtist {
  fileprivate func applying(_ edit: LidarrArtistEdit) -> LidarrArtist {
    LidarrArtist(
      id: id, name: name, sortName: sortName, foreignArtistID: foreignArtistID,
      overview: overview, artistType: artistType, disambiguation: disambiguation,
      status: status, isMonitored: edit.isMonitored, qualityProfileID: edit.qualityProfileID,
      metadataProfileID: edit.metadataProfileID, path: path,
      rootFolderPath: edit.rootFolderPath ?? rootFolderPath, genres: genres,
      tagIDs: edit.tagIDs, added: added, posterURL: posterURL, statistics: statistics)
  }
}

// MARK: - Fixtures

/// Artists and albums at mixed completeness. An artist's statistics are the
/// sums of its albums' in `albums()`, so the library row and the artist screen
/// agree.
enum DemoLidarrFixtures {
  static func artists() -> [LidarrArtist] {
    [
      artist(
        id: 1, name: "The Wandering Signal", sort: "wandering signal, the", albums: 4,
        files: 26, tracked: 31, total: 35, size: 2_080_000_000, genres: ["Post-rock"]),
      artist(
        id: 2, name: "Anvil Choir", sort: "anvil choir", albums: 2, files: 0, tracked: 20,
        total: 20, size: 0, monitored: false, genres: ["Doom"]),
      artist(
        id: 3, name: "Quiet Ledger", sort: "quiet ledger", albums: 1, files: 11, tracked: 11,
        total: 11, size: 880_000_000, genres: ["Ambient"]),
      artist(
        id: 4, name: "Harbour Choir", sort: "harbour choir", albums: 3, files: 24,
        tracked: 30, total: 30, size: 1_920_000_000, genres: ["Folk"]),
    ]
  }

  /// Invented, like every demo name.
  private static func artistOverview(_ id: Int) -> String {
    DemoArrFixtures.pick(id, from: [
      "An instrumental group known for long, slow-building records.",
      "A four-piece band that tours small venues between albums.",
      "A choir that records in churches and boathouses along the coast.",
      "A duo that writes short, loud songs about long drives.",
    ])
  }

  private static func artist(
    id: Int, name: String, sort: String, albums: Int, files: Int, tracked: Int, total: Int,
    size: Int64, monitored: Bool = true, genres: [String]
  ) -> LidarrArtist {
    LidarrArtist(
      id: id, name: name, sortName: sort, foreignArtistID: "mb-\(id)",
      overview: artistOverview(id), artistType: "Group",
      disambiguation: nil, status: id.isMultiple(of: 2) ? .ended : .continuing,
      isMonitored: monitored, qualityProfileID: 1, metadataProfileID: 2,
      path: "/data/media/music/\(name)", rootFolderPath: "/data/media/music",
      genres: genres, tagIDs: [], added: Date(timeIntervalSince1970: 1_690_000_000),
      posterURL: nil,
      statistics: LidarrArtistStatistics(
        albumCount: albums, trackFileCount: files, trackCount: tracked,
        totalTrackCount: total, sizeOnDiskBytes: size))
  }

  /// Complete, partial, and unreleased albums — the three states the album row
  /// can render.
  static func albums() -> [Int: [LidarrAlbum]] {
    [
      1: [
        album(id: 10, artist: 1, title: "Long Wave", year: 2025, files: 9, tracks: 9),
        album(id: 11, artist: 1, title: "Static Season", year: 2023, files: 5, tracks: 10),
        album(
          id: 12, artist: 1, title: "Nothing Yet", year: 2027, files: 0, tracks: 4,
          released: nothingYetReleases),
        album(
          id: 13, artist: 1, title: "First Signal", year: 2019, files: 12, tracks: 12,
          monitored: false),
      ],
      2: [
        album(id: 20, artist: 2, title: "Hollow Hymn", year: 2016, files: 0, tracks: 10),
        album(id: 21, artist: 2, title: "Slow Iron", year: 2014, files: 0, tracks: 10),
      ],
      3: [album(id: 30, artist: 3, title: "Ledger", year: 2024, files: 11, tracks: 11)],
      4: [
        album(id: 40, artist: 4, title: "Tideline", year: 2024, files: 12, tracks: 12),
        album(id: 41, artist: 4, title: "Saltmarsh", year: 2021, files: 12, tracks: 12),
        album(id: 42, artist: 4, title: "Low Country", year: 2018, files: 0, tracks: 6),
      ],
    ]
  }

  private static func album(
    id: Int, artist: Int, title: String, year: Int, files: Int, tracks: Int,
    monitored: Bool = true, released: Date? = nil
  ) -> LidarrAlbum {
    let releaseDate = released
      ?? Calendar(identifier: .gregorian).date(from: DateComponents(year: year, month: 5, day: 16))
    // Lidarr counts a track when its album is monitored and released, or when
    // the track already has a file.
    let isReleased = (releaseDate ?? .distantPast) <= Date()
    let counted = monitored && isReleased ? tracks : files
    return LidarrAlbum(
      id: id, artistID: artist, title: title, disambiguation: nil,
      overview: DemoArrFixtures.pick(id, from: [
        "Recorded live over a single weekend.",
        "Songs written on the road between two tours.",
        "Their quietest record, mostly piano and voice.",
      ]),
      albumType: "Album",
      secondaryTypes: [],
      releaseDate: releaseDate,
      isMonitored: monitored, durationMilliseconds: tracks * 240_000, genres: [],
      coverURL: nil,
      statistics: LidarrAlbumStatistics(
        trackFileCount: files, trackCount: counted, totalTrackCount: tracks,
        sizeOnDiskBytes: Int64(files) * 80_000_000))
  }

  /// Tracks for the album a reviewer is most likely to open — the partial one,
  /// where some are on disk and some are not.
  static func tracks() -> [Int: [LidarrTrack]] {
    var byAlbum: [Int: [LidarrTrack]] = [:]
    byAlbum[10] = (1...9).map {
      track(id: 1_000 + $0, album: 10, number: "A\($0)", index: $0, hasFile: true)
    }
    byAlbum[11] = (1...10).map {
      // Five on disk, five missing — the state the row's "5 of 10" describes.
      track(id: 1_100 + $0, album: 11, number: "B\($0)", index: $0, hasFile: $0 <= 5)
    }
    return byAlbum
  }

  private static func track(
    id: Int, album: Int, number: String, index: Int, hasFile: Bool
  ) -> LidarrTrack {
    LidarrTrack(
      id: id, albumID: album, title: "Track \(index)", trackNumber: number,
      absoluteTrackNumber: index, mediumNumber: 1, durationMilliseconds: 240_000,
      hasFile: hasFile, isExplicit: index == 3)
  }

  static func lookups(
    matching term: String, existing: [LidarrArtist]
  ) -> [LidarrArtistLookup] {
    let candidates = [
      ("Coastal Watch", "Group"), ("Northern Lights Ensemble", "Group"),
      ("The Wandering Signal", "Group"),
    ]
    let query = term.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    return candidates
      .filter { query.isEmpty || $0.0.lowercased().contains(query) }
      .enumerated()
      .map { index, candidate in
        let match = existing.first { $0.name == candidate.0 }
        return LidarrArtistLookup(
          foreignArtistID: "mb-lookup-\(index)", name: candidate.0,
          overview: artistOverview(index),
          artistType: candidate.1, disambiguation: nil, posterURL: nil,
          existingArtistID: match?.id)
      }
  }

  static let metadataProfiles: [LidarrMetadataProfile] = [
    LidarrMetadataProfile(id: 1, name: "Standard"),
    LidarrMetadataProfile(id: 2, name: "Everything"),
  ]

  static let qualityProfiles: [ArrQualityProfile] = [
    ArrQualityProfile(id: 1, name: "Lossless"),
    ArrQualityProfile(id: 2, name: "Standard"),
  ]

  static let rootFolders: [ArrRootFolder] = [
    ArrRootFolder(
      id: 1, path: "/data/media/music", isAccessible: true, freeBytes: 1_099_511_627_776)
  ]

  /// The unreleased album's release date, which the album row and the
  /// calendar both show.
  private static var nothingYetReleases: Date {
    Calendar.current.startOfDay(for: Date()).addingTimeInterval(4 * 86_400)
  }

  static func calendar() -> [ArrCalendarEntry] {
    [
      ArrCalendarEntry(
        id: 12, title: "Nothing Yet", subtitle: "The Wandering Signal",
        date: nothingYetReleases, isMonitored: true, hasFile: false)
    ]
  }
}
