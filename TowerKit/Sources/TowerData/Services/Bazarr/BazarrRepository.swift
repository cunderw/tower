import Foundation
import TowerCore

/// Everything the Bazarr screens can ask for.
///
/// **Not built on `ArrClientCore`.** Bazarr has no shared *arr surface — no
/// v3 API, no queue, no calendar, no command endpoint — so it reuses Tower's
/// UI patterns and none of its *arr client code, and this protocol is where
/// that shows.
///
/// **The request shapes here follow Bazarr's own Swagger document**
/// (`GET /api/swagger.json`, which it serves unauthenticated). That matters
/// because Bazarr's mutations take their arguments as **query parameters
/// rather than a JSON body** — including the manual subtitle download, where
/// every one of the seven is required. A body-shaped POST is accepted and does
/// nothing.
/// Its Swagger declares no *response* schemas, so the DTOs below are derived
/// from observed payloads and stay tolerant: every field optional, every enum
/// with an unknown case.
public protocol BazarrRepositoryProtocol: ServiceRepository {
  func series() async throws -> [BazarrMediaItem]
  func movies() async throws -> [BazarrMediaItem]

  /// Everything still missing a subtitle, episodes and films together.
  func wanted() async throws -> [WantedSubtitle]

  /// Manual search: what the providers have for one item.
  func candidates(for item: WantedSubtitle) async throws -> [SubtitleCandidate]
  /// Downloads a specific candidate the user picked.
  func download(_ candidate: SubtitleCandidate, for item: WantedSubtitle) async throws
  /// Lets Bazarr pick the best match itself.
  func downloadBest(_ language: SubtitleLanguage, for item: WantedSubtitle) async throws

  func providers() async throws -> [SubtitleProvider]
  func history() async throws -> [SubtitleHistoryRecord]
}

/// The live conformance.
public struct LiveBazarrRepository: BazarrRepositoryProtocol {
  public let instance: ServiceInstance
  private let client: ServiceHTTPClient

  /// `-1` is Bazarr's "no limit". Its list endpoints paginate by
  /// `start`/`length` and default to a page, which would silently truncate a
  /// wanted list.
  private static let noLimit = "-1"

  public init(instance: ServiceInstance, sessionConfiguration: URLSessionConfiguration? = nil) {
    self.instance = instance
    self.client = ServiceHTTPClient(
      instance: instance, sessionConfiguration: sessionConfiguration)
  }

  init(instance: ServiceInstance, client: ServiceHTTPClient) {
    self.instance = instance
    self.client = client
  }

  // MARK: - Library

  public func series() async throws -> [BazarrMediaItem] {
    let page: BazarrPageDTO<BazarrSeriesDTO> = try await client.send(
      "api/series", query: listQuery, as: BazarrPageDTO<BazarrSeriesDTO>.self)
    return (page.data ?? []).map(\.domain).sorted {
      $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
    }
  }

  public func movies() async throws -> [BazarrMediaItem] {
    let page: BazarrPageDTO<BazarrMovieDTO> = try await client.send(
      "api/movies", query: listQuery, as: BazarrPageDTO<BazarrMovieDTO>.self)
    return (page.data ?? []).map(\.domain).sorted {
      $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
    }
  }

  private var listQuery: [URLQueryItem] {
    [
      URLQueryItem(name: "start", value: "0"),
      URLQueryItem(name: "length", value: Self.noLimit),
    ]
  }

  // MARK: - Wanted

  public func wanted() async throws -> [WantedSubtitle] {
    // Two endpoints, one list. Fetched concurrently — they are independent,
    // and a Bazarr managing both libraries would otherwise pay for them in
    // series.
    async let episodes = wantedEpisodes()
    async let films = wantedMovies()
    // A Bazarr with only one of Sonarr or Radarr connected answers the other
    // with an error; losing the whole screen for that would be wrong.
    let episodeRows = (try? await episodes) ?? []
    let movieRows = (try? await films) ?? []
    return episodeRows + movieRows
  }

  private func wantedEpisodes() async throws -> [WantedSubtitle] {
    let page: BazarrPageDTO<BazarrWantedEpisodeDTO> = try await client.send(
      "api/episodes/wanted", query: listQuery,
      as: BazarrPageDTO<BazarrWantedEpisodeDTO>.self)
    return (page.data ?? []).map(\.domain)
  }

  private func wantedMovies() async throws -> [WantedSubtitle] {
    let page: BazarrPageDTO<BazarrWantedMovieDTO> = try await client.send(
      "api/movies/wanted", query: listQuery, as: BazarrPageDTO<BazarrWantedMovieDTO>.self)
    return (page.data ?? []).map(\.domain)
  }

  // MARK: - Search and download

  public func candidates(for item: WantedSubtitle) async throws -> [SubtitleCandidate] {
    let dtos: [BazarrCandidateDTO]
    if let episodeID = item.episodeID {
      dtos = try await client.send(
        "api/providers/episodes",
        query: [URLQueryItem(name: "episodeid", value: String(episodeID))],
        as: [BazarrCandidateDTO].self)
    } else if let radarrID = item.radarrID {
      dtos = try await client.send(
        "api/providers/movies",
        query: [URLQueryItem(name: "radarrid", value: String(radarrID))],
        as: [BazarrCandidateDTO].self)
    } else {
      return []
    }
    // Best score first — the whole reason the score is surfaced.
    return dtos.compactMap(\.domain).sorted { $0.score > $1.score }
  }

  public func download(
    _ candidate: SubtitleCandidate, for item: WantedSubtitle
  ) async throws {
    // **Query parameters, not a body**, and all seven required — verified
    // against the served Swagger. `provider` and `subtitle` together identify
    // the exact file; the language flags have to match the candidate's, or
    // Bazarr fetches the wrong variant of the right subtitle.
    var query = [
      URLQueryItem(name: "hi", value: candidate.language.isHearingImpaired ? "True" : "False"),
      URLQueryItem(name: "forced", value: candidate.language.isForced ? "True" : "False"),
      URLQueryItem(name: "original_format", value: "False"),
      URLQueryItem(name: "provider", value: candidate.provider),
      URLQueryItem(name: "subtitle", value: candidate.subtitleID),
    ]

    if let episodeID = item.episodeID, let seriesID = item.seriesID {
      query.append(URLQueryItem(name: "seriesid", value: String(seriesID)))
      query.append(URLQueryItem(name: "episodeid", value: String(episodeID)))
      try await client.send("api/providers/episodes", method: .post, query: query)
    } else if let radarrID = item.radarrID {
      query.append(URLQueryItem(name: "radarrid", value: String(radarrID)))
      try await client.send("api/providers/movies", method: .post, query: query)
    }
  }

  public func downloadBest(
    _ language: SubtitleLanguage, for item: WantedSubtitle
  ) async throws {
    // A different endpoint and a different verb from the manual pick: PATCH
    // on the media's own subtitles resource, which is Bazarr's "go and find
    // one yourself".
    var query = [
      URLQueryItem(name: "language", value: language.code),
      URLQueryItem(name: "hi", value: language.isHearingImpaired ? "True" : "False"),
      URLQueryItem(name: "forced", value: language.isForced ? "True" : "False"),
    ]

    if let episodeID = item.episodeID, let seriesID = item.seriesID {
      query.append(URLQueryItem(name: "seriesid", value: String(seriesID)))
      query.append(URLQueryItem(name: "episodeid", value: String(episodeID)))
      try await client.send("api/episodes/subtitles", method: .patch, query: query)
    } else if let radarrID = item.radarrID {
      query.append(URLQueryItem(name: "radarrid", value: String(radarrID)))
      try await client.send("api/movies/subtitles", method: .patch, query: query)
    }
  }

  // MARK: - Providers and history

  public func providers() async throws -> [SubtitleProvider] {
    let page: BazarrPageDTO<BazarrProviderDTO> = try await client.send(
      "api/providers", as: BazarrPageDTO<BazarrProviderDTO>.self)
    return (page.data ?? []).map(\.domain).sorted {
      $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
    }
  }

  public func history() async throws -> [SubtitleHistoryRecord] {
    async let episodes = historyPage("api/episodes/history")
    async let films = historyPage("api/movies/history")
    // Same reasoning as `wanted()`: one library missing must not cost both.
    let combined = ((try? await episodes) ?? []) + ((try? await films) ?? [])
    return combined
  }

  private func historyPage(_ path: String) async throws -> [SubtitleHistoryRecord] {
    let page: BazarrPageDTO<BazarrHistoryDTO> = try await client.send(
      path,
      query: [
        URLQueryItem(name: "start", value: "0"),
        URLQueryItem(name: "length", value: "50"),
      ],
      as: BazarrPageDTO<BazarrHistoryDTO>.self)
    return (page.data ?? []).map(\.domain)
  }
}
