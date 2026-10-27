import Foundation
import TowerCore

// Bazarr's wire types. `internal`, like every other service's DTOs.
//
// **Derived from observed payloads, not a schema.** Bazarr serves a Swagger
// document that declares its *requests* precisely and its *responses* not at
// all, so every field here is optional and every enum has an unknown case —
// the tolerance rule this codebase already applies to the *arrs, applied
// harder because there is no contract to check against.
//
// The one shape that repeats everywhere is the paged envelope: Bazarr wraps
// every list in `{ "data": [...], "total": n }`.

struct BazarrPageDTO<Row: Decodable & Sendable>: Decodable, Sendable {
  let data: [Row]?
  let total: Int?
}

/// A language as Bazarr sends it inside a `missing_subtitles` array.
///
/// Bazarr is inconsistent here: sometimes an object, sometimes a bare code
/// string. Both are accepted rather than one of them failing the decode of a
/// whole row.
struct BazarrLanguageDTO: Decodable, Sendable {
  let code2: String?
  let code3: String?
  let name: String?
  let hi: Bool?
  let forced: Bool?

  init(from decoder: any Decoder) throws {
    if let single = try? decoder.singleValueContainer(), let code = try? single.decode(String.self) {
      self.code2 = code
      self.code3 = nil
      self.name = code.uppercased()
      self.hi = false
      self.forced = false
      return
    }
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.code2 = try container.decodeIfPresent(String.self, forKey: .code2)
    self.code3 = try container.decodeIfPresent(String.self, forKey: .code3)
    self.name = try container.decodeIfPresent(String.self, forKey: .name)
    // `hi` and `forced` arrive as booleans on newer builds and as the strings
    // "True"/"False" on older ones.
    self.hi = try container.decodeFlexibleBool(forKey: .hi)
    self.forced = try container.decodeFlexibleBool(forKey: .forced)
  }

  enum CodingKeys: String, CodingKey {
    case code2, code3, name, hi, forced
  }

  var domain: SubtitleLanguage {
    let code = code2 ?? code3 ?? "??"
    return SubtitleLanguage(
      code: code,
      name: name ?? code.uppercased(),
      isHearingImpaired: hi ?? false,
      isForced: forced ?? false)
  }
}

extension KeyedDecodingContainer {
  /// Bazarr sends booleans as `true` on newer builds and `"True"` on older
  /// ones. A strict decode of either shape fails on the other.
  func decodeFlexibleBool(forKey key: Key) throws -> Bool? {
    if let value = try? decodeIfPresent(Bool.self, forKey: key) { return value }
    guard let text = try? decodeIfPresent(String.self, forKey: key) else { return nil }
    return text.lowercased() == "true"
  }
}

// MARK: - Library

struct BazarrSeriesDTO: Decodable, Sendable {
  let sonarrSeriesId: Int?
  let title: String?
  let monitored: Bool?
  let poster: String?
  let episodeMissingCount: Int?
  let profileId: Int?
  let profileName: String?

  var domain: BazarrMediaItem {
    BazarrMediaItem(
      serviceID: sonarrSeriesId ?? 0,
      title: title ?? "Untitled series",
      isSeries: true,
      posterURL: OpenableURL.from(poster),
      monitored: monitored ?? false,
      missingCount: episodeMissingCount ?? 0,
      languageProfileName: profileName)
  }
}

struct BazarrMovieDTO: Decodable, Sendable {
  let radarrId: Int?
  let title: String?
  let monitored: Bool?
  let poster: String?
  let missing_subtitles: [BazarrLanguageDTO]?
  let profileName: String?

  var domain: BazarrMediaItem {
    BazarrMediaItem(
      serviceID: radarrId ?? 0,
      title: title ?? "Untitled film",
      isSeries: false,
      posterURL: OpenableURL.from(poster),
      monitored: monitored ?? false,
      // A film has no episodes, so its "missing count" is how many languages
      // are still wanted.
      missingCount: missing_subtitles?.count ?? 0,
      languageProfileName: profileName)
  }
}

// MARK: - Wanted

struct BazarrWantedEpisodeDTO: Decodable, Sendable {
  let sonarrSeriesId: Int?
  let sonarrEpisodeId: Int?
  let seriesTitle: String?
  let episodeTitle: String?
  let episode_number: String?
  let missing_subtitles: [BazarrLanguageDTO]?

  var domain: WantedSubtitle {
    WantedSubtitle(
      title: seriesTitle ?? "Untitled series",
      // "2x11 · The Missing Signal" — the label a user scans for.
      subtitle: [episode_number, episodeTitle].compactMap { $0 }.joined(separator: " · "),
      seriesID: sonarrSeriesId,
      episodeID: sonarrEpisodeId,
      radarrID: nil,
      missing: (missing_subtitles ?? []).map(\.domain))
  }
}

struct BazarrWantedMovieDTO: Decodable, Sendable {
  let radarrId: Int?
  let title: String?
  let missing_subtitles: [BazarrLanguageDTO]?

  var domain: WantedSubtitle {
    WantedSubtitle(
      title: title ?? "Untitled film",
      subtitle: nil,
      seriesID: nil,
      episodeID: nil,
      radarrID: radarrId,
      missing: (missing_subtitles ?? []).map(\.domain))
  }
}

// MARK: - Manual search

struct BazarrCandidateDTO: Decodable, Sendable {
  let provider: String?
  let language: BazarrLanguageDTO?
  let score: Int?
  /// The opaque handle a download sends back. Bazarr calls it `subtitle`, and
  /// Tower never parses it.
  let subtitle: String?
  let release_info: [String]?
  let uploader: String?
  let url: String?
  let matches: [String]?
  let hearing_impaired: String?
  let forced: String?

  /// `nil` when the row can't be downloaded — without a provider and a handle
  /// there is nothing to send back, and offering it would produce a Grab that
  /// silently fails.
  var domain: SubtitleCandidate? {
    guard let provider, let subtitle, !subtitle.isEmpty else { return nil }
    var resolved = language?.domain
      ?? SubtitleLanguage(code: "??", name: "Unknown", isHearingImpaired: false, isForced: false)
    // Some builds put the two flags beside the language rather than inside it.
    if let hearing_impaired {
      resolved = SubtitleLanguage(
        code: resolved.code, name: resolved.name,
        isHearingImpaired: hearing_impaired.lowercased() == "true",
        isForced: resolved.isForced)
    }
    if let forced {
      resolved = SubtitleLanguage(
        code: resolved.code, name: resolved.name,
        isHearingImpaired: resolved.isHearingImpaired,
        isForced: forced.lowercased() == "true")
    }
    return SubtitleCandidate(
      provider: provider,
      language: resolved,
      score: score ?? 0,
      subtitleID: subtitle,
      releaseInfo: release_info ?? [],
      uploader: uploader.flatMap { $0.isEmpty ? nil : $0 },
      // The provider's own page for this subtitle — absolute in every Bazarr
      // build seen, and no image or link should be built from anything Tower
      // cannot open.
      url: OpenableURL.from(url),
      matchedBy: matches ?? [])
  }
}

// MARK: - Providers and history

struct BazarrProviderDTO: Decodable, Sendable {
  let name: String?
  let status: String?
  let retry: String?

  var domain: SubtitleProvider {
    SubtitleProvider(
      name: name ?? "Unknown provider",
      message: status,
      retryAt: retry)
  }
}

struct BazarrHistoryDTO: Decodable, Sendable {
  let id: Int?
  let action: Int?
  let seriesTitle: String?
  let title: String?
  let episode_number: String?
  let episodeTitle: String?
  let language: BazarrLanguageDTO?
  let provider: String?
  let score: BazarrScore?
  let timestamp: String?

  /// Bazarr sends a history score as `"88%"` on some rows and as a number on
  /// others.
  enum BazarrScore: Decodable, Sendable {
    case number(Int)
    case text(String)

    init(from decoder: any Decoder) throws {
      let container = try decoder.singleValueContainer()
      if let value = try? container.decode(Int.self) {
        self = .number(value)
      } else {
        self = .text((try? container.decode(String.self)) ?? "")
      }
    }

    var value: Int? {
      switch self {
      case .number(let value): value
      case .text(let text): Int(text.replacingOccurrences(of: "%", with: ""))
      }
    }
  }

  var domain: SubtitleHistoryRecord {
    SubtitleHistoryRecord(
      id: String(id ?? 0),
      title: seriesTitle ?? title ?? "Untitled",
      subtitle: [episode_number, episodeTitle].compactMap { $0 }
        .filter { !$0.isEmpty }
        .joined(separator: " · "),
      language: language?.domain,
      provider: provider.flatMap { $0.isEmpty ? nil : $0 },
      score: score?.value,
      timestamp: timestamp,
      action: SubtitleHistoryAction(apiValue: action))
  }
}
