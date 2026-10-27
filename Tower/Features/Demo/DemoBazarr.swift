import Foundation
import TowerCore
import TowerData

/// Demo mode's Bazarr.
private enum DemoBazarrLatency {
  static let read = Duration.milliseconds(450)
  static let write = Duration.milliseconds(700)

  static func read() async { try? await Task.sleep(for: read) }
  static func write() async { try? await Task.sleep(for: write) }
}

@MainActor
final class DemoBazarrServer {
  private(set) var wanted: [WantedSubtitle] = DemoBazarrFixtures.wanted()
  private(set) var history: [SubtitleHistoryRecord] = DemoBazarrFixtures.history()
  private var nextHistoryID = 950

  /// Satisfies one language on a row, dropping the row once nothing is left —
  /// which is what a real Bazarr's next `wanted` read shows, and the behaviour
  /// the store's re-read exists to pick up.
  func satisfy(_ language: SubtitleLanguage, on item: WantedSubtitle, provider: String, score: Int) {
    var title = item.title
    var subtitle = item.subtitle
    wanted = wanted.compactMap { row in
      guard row.id == item.id else { return row }
      title = row.title
      subtitle = row.subtitle
      let remaining = row.missing.filter { $0.id != language.id }
      guard !remaining.isEmpty else { return nil }
      return WantedSubtitle(
        title: row.title, subtitle: row.subtitle, seriesID: row.seriesID,
        episodeID: row.episodeID, radarrID: row.radarrID, missing: remaining)
    }

    history.insert(
      SubtitleHistoryRecord(
        id: String(nextHistoryID), title: title, subtitle: subtitle, language: language,
        provider: provider, score: score, timestamp: "just now",
        action: .manuallyDownloaded),
      at: 0)
    nextHistoryID += 1
  }

  /// What each library item is still missing, derived from `wanted` so the
  /// two can't disagree: episodes for a series, as Bazarr counts them, and
  /// languages for a film.
  func missingCount(seriesID: Int?, radarrID: Int?) -> Int {
    let rows = wanted.filter {
      seriesID != nil ? $0.seriesID == seriesID : $0.radarrID == radarrID
    }
    return seriesID != nil ? rows.count : rows.reduce(0) { $0 + $1.missing.count }
  }
}

struct DemoBazarrRepository: BazarrRepositoryProtocol {
  let instance: ServiceInstance
  let server: DemoBazarrServer

  func series() async throws -> [BazarrMediaItem] {
    await DemoBazarrLatency.read()
    // Counts derived from the wanted list rather than fixed, so downloading a
    // subtitle visibly moves the library row too.
    var items: [BazarrMediaItem] = []
    for item in DemoBazarrFixtures.seriesShells {
      let missing = await server.missingCount(seriesID: item.serviceID, radarrID: nil)
      items.append(item.settingMissingCount(missing))
    }
    return items
  }

  func movies() async throws -> [BazarrMediaItem] {
    await DemoBazarrLatency.read()
    var items: [BazarrMediaItem] = []
    for item in DemoBazarrFixtures.movieShells {
      let missing = await server.missingCount(seriesID: nil, radarrID: item.serviceID)
      items.append(item.settingMissingCount(missing))
    }
    return items
  }

  func wanted() async throws -> [WantedSubtitle] {
    await DemoBazarrLatency.read()
    return await server.wanted
  }

  func candidates(for item: WantedSubtitle) async throws -> [SubtitleCandidate] {
    await DemoBazarrLatency.read()
    return DemoBazarrFixtures.candidates(for: item)
  }

  func download(_ candidate: SubtitleCandidate, for item: WantedSubtitle) async throws {
    await DemoBazarrLatency.write()
    await server.satisfy(
      candidate.language, on: item, provider: candidate.provider, score: candidate.score)
  }

  func downloadBest(_ language: SubtitleLanguage, for item: WantedSubtitle) async throws {
    await DemoBazarrLatency.write()
    // Bazarr's automatic pick is the highest-scoring candidate for that
    // language, which is what the demo does rather than inventing a result.
    let best = DemoBazarrFixtures.candidates(for: item)
      .filter { $0.language.code == language.code }
      .max { $0.score < $1.score }
    await server.satisfy(
      language, on: item, provider: best?.provider ?? "opensubtitles.com",
      score: best?.score ?? 92)
  }

  func providers() async throws -> [SubtitleProvider] {
    await DemoBazarrLatency.read()
    return DemoBazarrFixtures.providers
  }

  func history() async throws -> [SubtitleHistoryRecord] {
    await DemoBazarrLatency.read()
    return await server.history
  }
}

extension BazarrMediaItem {
  fileprivate func settingMissingCount(_ count: Int) -> BazarrMediaItem {
    BazarrMediaItem(
      serviceID: serviceID, title: title, isSeries: isSeries, posterURL: posterURL,
      monitored: monitored, missingCount: count, languageProfileName: languageProfileName)
  }
}

// MARK: - Fixtures

enum DemoBazarrFixtures {
  private static let english = SubtitleLanguage(
    code: "en", name: "English", isHearingImpaired: false, isForced: false)
  private static let englishHI = SubtitleLanguage(
    code: "en", name: "English", isHearingImpaired: true, isForced: false)
  private static let french = SubtitleLanguage(
    code: "fr", name: "French", isHearingImpaired: false, isForced: true)

  /// Wanted items across both libraries, one of them missing two languages —
  /// the case that proves a download leaves the row rather than clearing it.
  ///
  /// Every row is an episode or film the demo Sonarr and Radarr have a file
  /// for, under the title they give it: Bazarr only wants subtitles for media
  /// on disk.
  static func wanted() -> [WantedSubtitle] {
    [
      WantedSubtitle(
        title: "Northern Lights", subtitle: "2x10 · Signal Lost", seriesID: 1,
        episodeID: 2_010, radarrID: nil, missing: [english, englishHI]),
      WantedSubtitle(
        title: "Northern Lights", subtitle: "2x09 · Low Tide", seriesID: 1,
        episodeID: 2_009, radarrID: nil, missing: [english]),
      WantedSubtitle(
        title: "The Long Wire", subtitle: "1x04 · Episode 4", seriesID: 2,
        episodeID: 3_004, radarrID: nil, missing: [french]),
      WantedSubtitle(
        title: "Salt Harbour", subtitle: nil, seriesID: nil, episodeID: nil, radarrID: 2,
        missing: [english]),
    ]
  }

  /// Scored candidates, spanning all three confidence bands so the row's
  /// treatment is demonstrable.
  static func candidates(for item: WantedSubtitle) -> [SubtitleCandidate] {
    let name = item.subtitle.map { "\(item.title) \($0)" } ?? item.title
    return item.missing.flatMap { language in
      [
        SubtitleCandidate(
          provider: "opensubtitles.com", language: language, score: 96,
          subtitleID: "demo-\(language.id)-a", releaseInfo: ["\(name) 1080p DEMO"],
          uploader: "demo-uploader", url: nil,
          // Matched to the release file, so the "in sync" treatment shows.
          matchedBy: ["series", "season", "episode", "release_group"]),
        SubtitleCandidate(
          provider: "gestdown", language: language, score: 78,
          subtitleID: "demo-\(language.id)-b", releaseInfo: ["\(name) 720p DEMO"],
          uploader: nil, url: nil, matchedBy: ["series", "season"]),
        SubtitleCandidate(
          provider: "addic7ed", language: language, score: 54,
          subtitleID: "demo-\(language.id)-c", releaseInfo: ["\(name) 480p DEMO"],
          uploader: nil, url: nil, matchedBy: ["series"]),
      ]
    }
  }

  /// One healthy, one throttled, one quiet — so the provider screen's failing
  /// count is non-zero and its treatment is visible.
  static let providers: [SubtitleProvider] = [
    SubtitleProvider(name: "opensubtitles.com", message: "Good", retryAt: "-"),
    SubtitleProvider(
      name: "addic7ed", message: "Throttled: too many requests", retryAt: "in 2 hours"),
    SubtitleProvider(name: "gestdown", message: nil, retryAt: "-"),
  ]

  static func history() -> [SubtitleHistoryRecord] {
    [
      // French, because English for this episode is still on the wanted list.
      SubtitleHistoryRecord(
        id: "900", title: "Northern Lights", subtitle: "2x10 · Signal Lost",
        language: SubtitleLanguage(
          code: "fr", name: "French", isHearingImpaired: false, isForced: true),
        provider: "opensubtitles.com", score: 96, timestamp: "2 hours ago",
        action: .downloaded),
      SubtitleHistoryRecord(
        id: "901", title: "Salt Harbour", subtitle: nil,
        language: SubtitleLanguage(
          code: "fr", name: "French", isHearingImpaired: false, isForced: true),
        provider: "gestdown", score: 74, timestamp: "yesterday",
        action: .manuallyDownloaded),
      SubtitleHistoryRecord(
        id: "902", title: "The Long Wire", subtitle: "1x03 · Episode 3",
        language: SubtitleLanguage(
          code: "en", name: "English", isHearingImpaired: true, isForced: false),
        provider: "opensubtitles.com", score: 88, timestamp: "3 days ago", action: .upgraded),
    ]
  }

  static let seriesShells: [BazarrMediaItem] = [
    BazarrMediaItem(
      serviceID: 1, title: "Northern Lights", isSeries: true, posterURL: nil, monitored: true,
      missingCount: 0, languageProfileName: "English + French"),
    BazarrMediaItem(
      serviceID: 2, title: "The Long Wire", isSeries: true, posterURL: nil, monitored: true,
      missingCount: 0, languageProfileName: "English + French"),
    BazarrMediaItem(
      serviceID: 3, title: "Harbourmaster", isSeries: true, posterURL: nil, monitored: false,
      missingCount: 0, languageProfileName: "English"),
  ]

  /// Films the demo Radarr has a file for: Bazarr only syncs those.
  static let movieShells: [BazarrMediaItem] = [
    BazarrMediaItem(
      serviceID: 1, title: "The Cartographer", isSeries: false, posterURL: nil, monitored: true,
      missingCount: 0, languageProfileName: "English"),
    BazarrMediaItem(
      serviceID: 2, title: "Salt Harbour", isSeries: false, posterURL: nil, monitored: true,
      missingCount: 0, languageProfileName: "English"),
  ]
}
