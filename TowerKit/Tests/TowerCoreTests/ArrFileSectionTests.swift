import Foundation
import Testing
@testable import TowerCore

/// What the *arr detail screens' File section is allowed to say.
///
/// The flag (`hasFile`) and the details (`file`) arrive from the service
/// independently, so a screen that renders the details' absence as "no file on
/// disk" can contradict its own status label. Sonarr answers `api/v3/episode`
/// with `hasFile: true` and no `episodeFile` unless asked for one, and such a
/// screen then reads "Downloaded" and "No file on disk." at once. The query asks
/// for the file; these tests stop the screen being *able* to say it anyway.

// MARK: - Sonarr

private func episode(
  hasFile: Bool, file: SonarrEpisodeFile?, aired: Date?
) -> SonarrEpisode {
  SonarrEpisode(
    id: 1, seriesID: 1, seasonNumber: 1, episodeNumber: 1, title: "Ep",
    overview: nil, airDate: aired, runtimeMinutes: 45, hasFile: hasFile,
    isMonitored: true, file: file)
}

private let anEpisodeFile = SonarrEpisodeFile(
  id: 1, relativePath: "Season 1/Ep.mkv", sizeBytes: 350_000_000, quality: "SDTV",
  releaseGroup: "GROUP", videoCodec: "h264", audioCodec: "AAC", resolution: "1920x1080",
  languages: ["eng"], dateAdded: nil)

private let aired = Date(timeIntervalSince1970: 1_000_000)
private let unaired = Date.distantFuture

@Test func anEpisodeWithDetailsShowsThem() {
  #expect(episode(hasFile: true, file: anEpisodeFile, aired: aired).fileSection == .details)
}

@Test func anEpisodeOnDiskWithNoDetailsSaysSoRatherThanClaimingNoFile() {
  // Sonarr's payload without `includeEpisodeFile`: the flag says the file is
  // there, the details never arrived. "No file on disk." here contradicts
  // "On disk: Yes" directly above it and invites re-downloading something the
  // array already holds.
  #expect(
    episode(hasFile: true, file: nil, aired: aired).fileSection == .onDiskWithoutDetails)
}

@Test func anAiredEpisodeWithNoFileIsMissing() {
  #expect(episode(hasFile: false, file: nil, aired: aired).fileSection == .missing)
}

@Test func anUnairedEpisodeMakesNoFileClaim() {
  #expect(episode(hasFile: false, file: nil, aired: unaired).fileSection == .notYetAvailable)
}

@Test func anUnairedEpisodeThatSomehowHasAFileStillShowsIt() {
  // Sonarr does hand out early releases; the file winning over the air date
  // keeps the screen describing what is actually on the array.
  #expect(episode(hasFile: true, file: anEpisodeFile, aired: unaired).fileSection == .details)
}

// MARK: - Radarr

private func movie(
  hasFile: Bool, file: RadarrMovieFile?, isAvailable: Bool
) -> RadarrMovie {
  RadarrMovie(
    id: 1, tmdbID: nil, imdbID: nil, title: "Film", sortTitle: "film", year: 2024,
    overview: nil, studio: nil, runtimeMinutes: 120, certification: nil, genres: [],
    status: isAvailable ? .released : .announced, minimumAvailability: .released,
    isMonitored: true, hasFile: hasFile, isAvailable: isAvailable, sizeOnDiskBytes: 0,
    qualityProfileID: 1, path: nil, rootFolderPath: nil, tagIDs: [], added: nil,
    inCinemas: nil, digitalRelease: nil, physicalRelease: nil, posterURL: nil,
    fanartURL: nil, file: file)
}

private let aMovieFile = RadarrMovieFile(
  id: 1, relativePath: "Film.mkv", sizeBytes: 1_750_000_000, quality: "Bluray-1080p",
  releaseGroup: "GRP", videoCodec: "h264", audioCodec: "DTS", audioChannels: 5.1,
  resolution: "1920x1080", runtime: nil, languages: ["English"], dateAdded: nil)

@Test func aMovieWithDetailsShowsThem() {
  #expect(movie(hasFile: true, file: aMovieFile, isAvailable: true).fileSection == .details)
}

@Test func aMovieOnDiskWithNoDetailsSaysSoRatherThanClaimingNoFile() {
  #expect(
    movie(hasFile: true, file: nil, isAvailable: true).fileSection == .onDiskWithoutDetails)
}

@Test func aReleasedMovieWithNoFileIsMissing() {
  #expect(movie(hasFile: false, file: nil, isAvailable: true).fileSection == .missing)
}

@Test func anUnreleasedMovieMakesNoFileClaim() {
  #expect(movie(hasFile: false, file: nil, isAvailable: false).fileSection == .notYetAvailable)
}

// MARK: - The invariant both screens must hold

@Test func nothingOnDiskEverReadsAsHavingNoFile() {
  // The rule, stated once: whenever the status label would say "Downloaded",
  // the File section must not claim the file is absent — and that has to hold
  // for both screens and every input shape.
  let onDisk: [ArrFileSection] = [
    episode(hasFile: true, file: anEpisodeFile, aired: aired).fileSection,
    episode(hasFile: true, file: nil, aired: aired).fileSection,
    episode(hasFile: true, file: nil, aired: unaired).fileSection,
    movie(hasFile: true, file: aMovieFile, isAvailable: true).fileSection,
    movie(hasFile: true, file: nil, isAvailable: true).fileSection,
    movie(hasFile: true, file: nil, isAvailable: false).fileSection,
  ]
  #expect(onDisk.allSatisfy { $0.claimsAFileExists })
  #expect(!onDisk.contains(.missing))
  #expect(!onDisk.contains(.notYetAvailable))
}

@Test func everyStateThatDeniesAFileAgreesTheFileIsAbsent() {
  let absent: [ArrFileSection] = [
    episode(hasFile: false, file: nil, aired: aired).fileSection,
    episode(hasFile: false, file: nil, aired: unaired).fileSection,
    movie(hasFile: false, file: nil, isAvailable: true).fileSection,
    movie(hasFile: false, file: nil, isAvailable: false).fileSection,
  ]
  #expect(absent.allSatisfy { !$0.claimsAFileExists })
}
