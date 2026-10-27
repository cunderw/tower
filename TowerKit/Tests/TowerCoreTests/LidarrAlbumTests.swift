import Foundation
import Testing
import TowerCore

@Suite
struct LidarrAlbumTests {
  private func album(releaseDate: Date?, statistics: LidarrAlbumStatistics?) -> LidarrAlbum {
    LidarrAlbum(
      id: 1, artistID: 1, title: "Album", disambiguation: nil, overview: nil, albumType: nil,
      secondaryTypes: [], releaseDate: releaseDate, isMonitored: true,
      durationMilliseconds: nil, genres: [], coverURL: nil, statistics: statistics)
  }

  @Test func anAlbumWithNoTracksIsMissingWhetherOrNotItIsReleased() {
    // No statistics and a zero track count both read as `.missing`;
    // `isReleased` is what tells an unreleased album apart on screen.
    let future = album(releaseDate: .now.addingTimeInterval(86_400 * 30), statistics: nil)
    let past = album(
      releaseDate: .now.addingTimeInterval(-86_400 * 30),
      statistics: LidarrAlbumStatistics(
        trackFileCount: 0, trackCount: 0, totalTrackCount: 0, sizeOnDiskBytes: 0))

    #expect(future.libraryState == .missing)
    #expect(!future.isReleased)
    #expect(past.libraryState == .missing)
    #expect(past.isReleased)
  }
}

// MARK: - Track summary

private func statistics(files: Int, tracked: Int, total: Int) -> LidarrAlbumStatistics {
  LidarrAlbumStatistics(
    trackFileCount: files, trackCount: tracked, totalTrackCount: total, sizeOnDiskBytes: 0)
}

@Test func anAlbumWithTrackedTracksReadsFilesOfTracked() {
  #expect(statistics(files: 5, tracked: 10, total: 10).trackSummary == "5 of 10")
}

@Test func anAlbumLidarrTracksNothingOnShowsItsTotalInstead() {
  // An unreleased or unmonitored album with no files has a tracked count of
  // zero, and "0 of 0" says nothing about it.
  #expect(statistics(files: 0, tracked: 0, total: 4).trackSummary == "4 tracks")
  #expect(statistics(files: 0, tracked: 0, total: 1).trackSummary == "1 track")
}

@Test func anAlbumWithNoTracksAtAllHasNoTrackLine() {
  #expect(statistics(files: 0, tracked: 0, total: 0).trackSummary == nil)
}
