import Foundation
import TowerCore

/// The ids that join the demo *arr queues to the demo download clients.
///
/// **One place, referenced from both sides.** These are the only values that
/// have to agree across two otherwise-independent fixture sets, and a literal
/// copied into each would drift the first time one was edited — leaving a demo
/// where the queue row offers a link to an item the client doesn't have.
/// The download-client fixtures read the same constant.
enum DemoDownloadIDs {
  /// NZBGet addresses items by integer id.
  static let northernLightsNZB = 41
}

/// The dataset demo mode's Radarr and Sonarr present.
///
/// Shaped like a real stack, following the same rule as `DemoData`: every state
/// the UI can render appears somewhere. A screen of uniformly healthy rows
/// teaches an App Store reviewer nothing about what the app is for.
///
/// Nothing here names a real title, host, or key: the films, series, networks
/// and indexers are invented, and the addresses are TEST-NET-1.
enum DemoArrFixtures {
  // MARK: - Movies

  /// 54 films: mostly downloaded, some missing, one unreleased, one
  /// unmonitored — enough that search, sort, and the filters all do something
  /// visible on a screenshot.
  static func movies() -> [RadarrMovie] {
    var library: [RadarrMovie] = [
      movie(id: 1, title: "The Cartographer", year: 2024, state: .downloaded,
            size: 68_719_476_736, studio: "Meridian Pictures", quality: "WEBDL-2160p"),
      movie(id: 2, title: "Salt Harbour", year: 2023, state: .downloaded,
            size: 11_811_160_064, studio: "Northgate Films"),
      movie(id: 3, title: "Winter Ledger", year: 2022, state: .missing,
            studio: "Meridian Pictures"),
      movie(id: 4, title: "The Quiet Signal", year: 2026, state: .unreleased,
            studio: "Harbourlight"),
      movie(id: 5, title: "Paper Cities", year: 2021, state: .downloaded,
            size: 12_884_901_888, studio: "Northgate Films", monitored: false),
    ]
    let titles = [
      "Anvil Road", "Blue Meridian", "Copper Line", "Dust and Ember", "Echo Valley",
      "Fathom", "Glass Harbour", "Hollow Point", "Ironwood", "Junction 12",
      "Kestrel", "Lantern Hill", "Marrow", "Nightjar", "Orchard Street",
      "Pale Horizon", "Quarry", "Rust Belt", "Saltwater", "Tidewater",
      "Umbra", "Vantage", "Waypoint", "Xenon Nights", "Yardarm",
      "Zephyr", "Ash Fork", "Bright Angel", "Cold Spring", "Deep Water",
      "Eastwind", "Foxglove", "Granite", "Hazel Bend", "Inkwell",
      "Juniper", "Kingfisher", "Longshore", "Mile End", "Northern Line",
      "Overwinter", "Pinnacle", "Quicksilver", "Redwood", "Stonecrop",
      "Thornfield", "Undertow", "Verglas", "Windrow",
    ]
    for (index, title) in titles.enumerated() {
      let downloaded = !index.isMultiple(of: 5)
      library.append(
        movie(
          id: 100 + index,
          title: title,
          year: 2005 + (index % 20),
          state: downloaded ? .downloaded : .missing,
          // 6 to 15 GB, the range of a 1080p web release.
          size: downloaded ? Int64(6_000 + (index * 1_237) % 9_000) * 1_000_000 : 0,
          studio: index.isMultiple(of: 2) ? "Meridian Pictures" : "Northgate Films"))
    }
    return library
  }

  static func movie(from request: RadarrAddMovieRequest, id: Int) -> RadarrMovie {
    movie(
      id: id,
      title: request.lookup.title,
      year: request.lookup.year ?? 2026,
      state: .missing,
      studio: request.lookup.studio,
      monitored: request.isMonitored,
      rootFolder: request.rootFolderPath,
      profile: request.qualityProfileID,
      tags: request.tagIDs)
  }

  static func movieLookups(matching term: String, existing: [RadarrMovie]) -> [RadarrMovieLookup] {
    let candidates = [
      ("Harbour Lights", 2026, "Harbourlight"),
      ("The Cartographer", 2024, "Meridian Pictures"),
      ("Second Wind", 2025, "Northgate Films"),
    ]
    let query = term.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    return candidates
      .filter { query.isEmpty || $0.0.lowercased().contains(query) }
      .enumerated()
      .map { index, candidate in
        let match = existing.first { $0.title == candidate.0 }
        return RadarrMovieLookup(
          tmdbID: 700_000 + index, title: candidate.0, year: candidate.1,
          overview: filmOverview(index), posterURL: nil,
          studio: candidate.2, runtimeMinutes: 100 + index * 7, existingMovieID: match?.id)
      }
  }

  private enum MovieState {
    case downloaded, missing, unreleased
  }

  private static func movie(
    id: Int, title: String, year: Int, state: MovieState, size: Int64 = 0,
    studio: String? = nil, monitored: Bool = true, quality: String = "WEBDL-1080p",
    rootFolder: String = "/data/media/movies", profile: Int = 4, tags: [Int] = []
  ) -> RadarrMovie {
    RadarrMovie(
      id: id, tmdbID: 600_000 + id, imdbID: nil, title: title,
      sortTitle: title.lowercased(), year: year,
      overview: filmOverview(id),
      studio: studio, runtimeMinutes: 96 + (id % 40), certification: "PG-13",
      genres: ["Drama"], status: state == .unreleased ? .announced : .released,
      minimumAvailability: .released, isMonitored: monitored,
      hasFile: state == .downloaded, isAvailable: state != .unreleased,
      sizeOnDiskBytes: size, qualityProfileID: profile, path: "\(rootFolder)/\(title) (\(year))",
      rootFolderPath: rootFolder, tagIDs: tags,
      added: Date(timeIntervalSince1970: 1_700_000_000 + Double(id) * 3_600),
      inCinemas: nil, digitalRelease: nil, physicalRelease: nil, posterURL: nil, fanartURL: nil,
      file: state == .downloaded
        ? RadarrMovieFile(
          id: id, relativePath: "\(title) (\(year)) \(quality).mkv", sizeBytes: size,
          quality: quality, releaseGroup: "DEMO", videoCodec: "HEVC", audioCodec: "TrueHD",
          audioChannels: 7.1, resolution: quality.contains("2160") ? "3840x2160" : "1920x1080",
          runtime: "1:52:00", languages: ["eng"],
          dateAdded: Date(timeIntervalSince1970: 1_700_000_000))
        : nil)
  }

  // MARK: - Series

  /// A dozen series, including one with a **missing episode that has a
  /// grabbable release** — the demo path, end to end.
  static func series() -> [SonarrSeries] {
    [
      // S02E12 has not aired, so 23 of 24.
      show(id: 1, title: "Northern Lights", files: 22, aired: 23, total: 24,
           size: 96_636_764_160,
           seasons: [
            season(1, files: 12, aired: 12, total: 12, size: 48_318_382_080),
            season(2, files: 10, aired: 11, total: 12, size: 48_318_382_080),
           ]),
      show(id: 2, title: "The Long Wire", files: 30, aired: 30, size: 128_849_018_880,
           seasons: [season(1, files: 30, aired: 30, total: 30, size: 128_849_018_880)]),
      show(id: 3, title: "Harbourmaster", files: 6, aired: 10, size: 25_769_803_776,
           monitored: false,
           seasons: [season(1, files: 6, aired: 10, total: 12, size: 25_769_803_776)]),
    ] + (4...12).map { index in
      show(
        id: index, title: ["Kestrel Court", "Ninth Street", "Old Sound", "Pilot Light",
                           "Quarter Mile", "Riverbend", "Signal Hill", "Tidal", "Undercurrent"][index - 4],
        files: 8 + index, aired: 8 + index, size: Int64(index) * 8_589_934_592,
        seasons: [season(1, files: 8 + index, aired: 8 + index, total: 10 + index,
                         size: Int64(index) * 8_589_934_592)])
    }
  }

  static func series(from request: SonarrAddSeriesRequest, id: Int) -> SonarrSeries {
    show(
      id: id, title: request.lookup.title, files: 0, aired: 0,
      size: 0, monitored: request.monitorOption != .none, seasons: [],
      rootFolder: request.rootFolderPath, profile: request.qualityProfileID,
      type: request.seriesType, tags: request.tagIDs)
  }

  /// Season 2 of "Northern Lights" is short two episodes, one of them aired —
  /// that is the row a reviewer taps to reach interactive search.
  ///
  /// **Its named episodes are the ones the other demo services mention.** Bazarr
  /// wants subtitles for 9 and 10, Tautulli streams 10 and has played 8 and 9,
  /// and the calendar shows 12, so each title and air date lives here once.
  static func episodes() -> [SonarrEpisode] {
    var episodes: [SonarrEpisode] = []
    for number in 1...12 {
      episodes.append(
        episode(
          id: 1_000 + number, series: 1, season: 1, number: number,
          title: "Season One, Episode \(number)", hasFile: true,
          aired: Date(timeIntervalSince1970: 1_690_000_000 + Double(number) * 604_800)))
    }
    for number in 1...12 {
      // 11 has aired and is missing; 12 hasn't aired yet.
      let hasFile = number <= 10
      let airDate = Date(timeIntervalSince1970: 1_720_000_000 + Double(number) * 604_800)
      episodes.append(
        episode(
          id: 2_000 + number, series: 1, season: 2, number: number,
          title: northernLightsSeasonTwo[number] ?? "Season Two, Episode \(number)",
          hasFile: hasFile,
          aired: number == 12 ? northernLightsFinaleAirs : airDate))
    }
    for number in 1...30 {
      episodes.append(
        episode(
          id: 3_000 + number, series: 2, season: 1, number: number,
          title: "Episode \(number)", hasFile: true,
          aired: Date(timeIntervalSince1970: 1_660_000_000 + Double(number) * 604_800)))
    }
    return episodes
  }

  private static let northernLightsSeasonTwo = [
    8: "Crosscurrent", 9: "Low Tide", 10: "Signal Lost", 11: "The Missing Signal",
    12: "Aftermath",
  ]

  /// When S02E12 airs: the same moment in the episode list and on the calendar.
  private static var northernLightsFinaleAirs: Date {
    Calendar.current.startOfDay(for: Date()).addingTimeInterval(2 * 86_400 + 21 * 3_600)
  }

  static func seriesLookups(matching term: String, existing: [SonarrSeries]) -> [SonarrSeriesLookup] {
    let candidates = [("Coastal Watch", 2026), ("Northern Lights", 2021), ("Third Shift", 2025)]
    let query = term.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    return candidates
      .filter { query.isEmpty || $0.0.lowercased().contains(query) }
      .enumerated()
      .map { index, candidate in
        let match = existing.first { $0.title == candidate.0 }
        return SonarrSeriesLookup(
          tvdbID: 800_000 + index, title: candidate.0, year: candidate.1,
          overview: seriesOverview(index), network: "Coastline TV",
          status: match == nil ? .upcoming : .continuing, posterURL: nil,
          existingSeriesID: match?.id)
      }
  }

  private static func show(
    id: Int, title: String, files: Int, aired: Int, total: Int? = nil, size: Int64,
    monitored: Bool = true, seasons: [SonarrSeason], rootFolder: String = "/data/media/tv", profile: Int = 4,
    type: SeriesType = .standard, tags: [Int] = []
  ) -> SonarrSeries {
    SonarrSeries(
      id: id, tvdbID: 800_000 + id, imdbID: nil, title: title, sortTitle: title.lowercased(),
      year: 2019 + (id % 6), overview: seriesOverview(id),
      network: "Coastline TV", runtimeMinutes: 45, certification: "TV-MA",
      genres: ["Drama"], status: id.isMultiple(of: 3) ? .ended : .continuing, seriesType: type,
      isMonitored: monitored, usesSeasonFolders: true, qualityProfileID: profile,
      path: "\(rootFolder)/\(title)", rootFolderPath: rootFolder, tagIDs: tags,
      added: Date(timeIntervalSince1970: 1_690_000_000), nextAiring: nil, previousAiring: nil,
      posterURL: nil, fanartURL: nil, seasons: seasons,
      statistics: SonarrSeriesStatistics(
        seasonCount: max(seasons.count, 1), episodeFileCount: files, episodeCount: aired,
        totalEpisodeCount: total ?? aired + 2, sizeOnDiskBytes: size))
  }

  private static func season(
    _ number: Int, files: Int, aired: Int, total: Int, size: Int64
  ) -> SonarrSeason {
    SonarrSeason(
      seasonNumber: number, isMonitored: true, episodeFileCount: files, episodeCount: aired,
      totalEpisodeCount: total, sizeOnDiskBytes: size, nextAiring: nil)
  }

  private static func episode(
    id: Int, series: Int, season: Int, number: Int, title: String, hasFile: Bool, aired: Date
  ) -> SonarrEpisode {
    SonarrEpisode(
      id: id, seriesID: series, seasonNumber: season, episodeNumber: number, title: title,
      overview: episodeOverview(id), airDate: aired,
      runtimeMinutes: 45, hasFile: hasFile, isMonitored: true,
      file: hasFile
        ? SonarrEpisodeFile(
          id: id, relativePath: "Season \(season)/\(title).mkv", sizeBytes: 4_294_967_296,
          quality: "WEBDL-1080p", releaseGroup: "DEMO", videoCodec: "h264", audioCodec: "EAC3",
          resolution: "1920x1080", languages: ["eng"], dateAdded: aired)
        : nil)
  }

  // MARK: - Overviews

  /// Invented blurbs, picked by id so neighbouring rows read differently. None
  /// names a real title.
  static func filmOverview(_ id: Int) -> String {
    pick(id, from: [
      "A surveyor maps a coastline that changes between every visit.",
      "Two estranged siblings drive a borrowed truck across three states.",
      "A night-shift nurse keeps meeting the same patient on every ward.",
      "A small-town orchestra has one season to save its concert hall.",
      "A retired pilot agrees to fly one last cargo run over the mountains.",
    ])
  }

  static func seriesOverview(_ id: Int) -> String {
    pick(id, from: [
      "A coastal rescue crew works the winter season from an island station.",
      "Detectives in a northern city reopen a case their predecessors closed.",
      "A family restaurant changes hands three times in one year.",
      "Engineers race to finish a bridge before the river floods.",
    ])
  }

  static func episodeOverview(_ id: Int) -> String {
    pick(id, from: [
      "A storm call comes in with half the boats out for repair.",
      "An old witness changes their story.",
      "A delivery goes missing, and everyone has a theory.",
      "The night before the inspection, nothing goes to plan.",
    ])
  }

  static func pick(_ id: Int, from options: [String]) -> String {
    options[abs(id) % options.count]
  }

  // MARK: - Shared surfaces

  /// One downloading, one stuck at import, one waiting — the three states the
  /// queue exists to tell apart.
  static func queue() -> [ArrQueueItem] {
    [
      ArrQueueItem(
        id: 1, title: "Winter Ledger (2022) 2160p DEMO", mediaID: 3,
        sizeBytes: 64_424_509_440, sizeLeftBytes: 21_474_836_480, timeLeft: "00:18:22",
        estimatedCompletionTime: nil, status: .downloading, trackedStatus: .ok,
        trackedState: .downloading, errorMessage: nil, statusMessages: [],
        downloadProtocol: .usenet, downloadClient: "NZBGet",
        indexer: "Kestrel NZB", quality: "WEBDL-2160p"),
      // **Deliberately not the title `releases(for:)` generates.** The demo's
      // grab dedupes by title, so a seeded queue row that matches the searched
      // release makes the demo's headline search → grab path silently do
      // nothing. This row is the copy that stalled at import; the search
      // offers a different release.
      ArrQueueItem(
        id: 2, title: "Northern Lights S02E11 1080p Usenet DEMO", mediaID: 1,
        sizeBytes: 4_294_967_296, sizeLeftBytes: 0, timeLeft: nil,
        estimatedCompletionTime: nil, status: .warning, trackedStatus: .warning,
        trackedState: .importBlocked, errorMessage: nil,
        statusMessages: ["No files found are eligible for import"],
        downloadProtocol: .usenet, downloadClient: "NZBGet",
        downloadID: String(DemoDownloadIDs.northernLightsNZB),
        indexer: "Kestrel NZB", quality: "WEBDL-1080p"),
      ArrQueueItem(
        id: 3, title: "Salt Harbour (2023) 1080p DEMO", mediaID: 2,
        sizeBytes: 11_811_160_064, sizeLeftBytes: 0, timeLeft: nil,
        estimatedCompletionTime: nil, status: .completed, trackedStatus: .ok,
        trackedState: .importPending, errorMessage: nil, statusMessages: [],
        downloadProtocol: .usenet, downloadClient: "NZBGet",
        indexer: "Kestrel NZB", quality: "WEBDL-1080p"),
    ]
  }

  /// Winter Ledger's file was deleted and its first 2160p download failed,
  /// which is why it is missing and grabbed again; the films with files have
  /// only imports.
  static func history() -> [ArrHistoryRecord] {
    [
      ArrHistoryRecord(
        id: 1, event: .grabbed, sourceTitle: "Winter Ledger (2022) 2160p DEMO",
        mediaID: 3, date: Date().addingTimeInterval(-1_800), quality: "WEBDL-2160p"),
      ArrHistoryRecord(
        id: 2, event: .downloadFolderImported, sourceTitle: "Salt Harbour (2023) 1080p DEMO",
        mediaID: 2, date: Date().addingTimeInterval(-9_000), quality: "WEBDL-1080p"),
      ArrHistoryRecord(
        id: 3, event: .downloadFailed, sourceTitle: "Winter Ledger (2022) 2160p Remux DEMO",
        mediaID: 3, date: Date().addingTimeInterval(-90_000), quality: "Remux-2160p"),
      ArrHistoryRecord(
        id: 4, event: .fileDeleted, sourceTitle: "Winter Ledger (2022) 1080p DEMO",
        mediaID: 3, date: Date().addingTimeInterval(-172_800), quality: "WEBDL-1080p"),
    ]
  }

  static func movieCalendar() -> [ArrCalendarEntry] {
    let today = Calendar.current.startOfDay(for: Date())
    return [
      ArrCalendarEntry(
        id: 3, title: "Winter Ledger", subtitle: "2022",
        date: today.addingTimeInterval(10 * 3_600), isMonitored: true, hasFile: false),
      ArrCalendarEntry(
        id: 2, title: "Salt Harbour", subtitle: "2023",
        date: today.addingTimeInterval(15 * 3_600), isMonitored: true, hasFile: true),
      ArrCalendarEntry(
        id: 4, title: "The Quiet Signal", subtitle: "2026",
        date: today.addingTimeInterval(4 * 86_400 + 20 * 3_600), isMonitored: true, hasFile: false),
    ]
  }

  static func seriesCalendar() -> [ArrCalendarEntry] {
    let today = Calendar.current.startOfDay(for: Date())
    return [
      ArrCalendarEntry(
        id: 2_012, title: "Northern Lights", subtitle: "S02E12 · Aftermath",
        date: northernLightsFinaleAirs, isMonitored: true, hasFile: false),
      ArrCalendarEntry(
        id: 3_031, title: "The Long Wire", subtitle: "S02E01 · Homecoming",
        date: today.addingTimeInterval(5 * 86_400 + 21 * 3_600), isMonitored: true, hasFile: false),
    ]
  }

  /// The releases behind the demo's search → grab path. The first is approved
  /// and grabbable; the second shows what a rejection reads like.
  ///
  /// **Named after what was searched for.** A movie search that answers with
  /// `Northern Lights S02E11` is a demo caught telling the truth about being a
  /// fixture — and the grab confirmation quotes the release title back, so it
  /// lands in the one dialog a reviewer is most likely to read.
  static func releases(for title: String, season: Int? = nil, episode: Int? = nil) -> [ArrRelease] {
    let tag = season.map { String(format: " S%02dE%02d", $0, episode ?? 1) } ?? ""
    return [
      ArrRelease(
        id: "demo-release-1", title: "\(title)\(tag) 1080p DEMO",
        indexer: "Brightwater Index", indexerID: 1, quality: "WEBDL-1080p",
        sizeBytes: 4_294_967_296, downloadProtocol: .usenet,
        publishDate: Date().addingTimeInterval(-7_200), ageHours: 2, isApproved: true,
        rejections: []),
      ArrRelease(
        id: "demo-release-2", title: "\(title)\(tag) 720p DEMO",
        indexer: "Kestrel NZB", indexerID: 2, quality: "HDTV-720p",
        sizeBytes: 1_073_741_824, downloadProtocol: .usenet,
        publishDate: Date().addingTimeInterval(-86_400), ageHours: 24, isApproved: false,
        rejections: ["Quality HDTV-720p is below the profile's cutoff"]),
    ]
  }

  static let qualityProfiles: [ArrQualityProfile] = [
    ArrQualityProfile(id: 1, name: "Any"),
    ArrQualityProfile(id: 4, name: "HD-1080p"),
    ArrQualityProfile(id: 6, name: "Ultra-HD"),
  ]

  static let movieRootFolders: [ArrRootFolder] = [
    ArrRootFolder(id: 1, path: "/data/media/movies", isAccessible: true, freeBytes: 3_221_225_472_000),
    ArrRootFolder(id: 2, path: "/data/media/movies-4k", isAccessible: true, freeBytes: 1_099_511_627_776),
  ]

  static let seriesRootFolders: [ArrRootFolder] = [
    ArrRootFolder(id: 1, path: "/data/media/tv", isAccessible: true, freeBytes: 2_199_023_255_552)
  ]

  static let tags: [ArrTag] = [
    ArrTag(id: 1, label: "4k"), ArrTag(id: 2, label: "kids"), ArrTag(id: 3, label: "archive"),
  ]

  /// One warning, not a wall of them: enough to show what the health list is
  /// for without implying the demo server is broken.
  static let health: [ArrHealthCheck] = [
    ArrHealthCheck(
      id: 1, source: "ImportListStatusCheck", severity: .warning,
      message: "Lists unavailable due to failures: Example List",
      wikiURL: URL(string: "https://wiki.servarr.com/radarr/system"))
  ]

  static let disks: [ArrDiskSpace] = [
    ArrDiskSpace(path: "/data", label: "data", freeBytes: 3_221_225_472_000, totalBytes: 12_000_138_625_024),
    ArrDiskSpace(path: "/config", label: nil, freeBytes: 48_318_382_080, totalBytes: 107_374_182_400),
  ]

  static func status(app: String, version: String) -> ArrSystemStatus {
    ArrSystemStatus(
      appName: app, instanceName: app, version: version, osName: "ubuntu", osVersion: "24.04",
      isDocker: true, startTime: Date().addingTimeInterval(-9 * 86_400))
  }
}
