import Testing

@testable import Tower

/// What a Tautulli stream row prints beside the measured bitrate.
@MainActor
struct StreamCardTests {
  @Test func aProfileNamedAfterItsRateShowsOnlyTheResolution() {
    #expect(StreamCard.qualityBesideBitrate("4 Mbps 720p") == "720p")
    #expect(StreamCard.qualityBesideBitrate("1.5 Mbps 480p") == "480p")
    #expect(StreamCard.qualityBesideBitrate("20 Mbps 1080p") == "1080p")
  }

  @Test func aProfileThatIsOnlyARateAddsNothing() {
    #expect(StreamCard.qualityBesideBitrate("320 kbps") == nil)
  }

  @Test func aProfileWithNoRatePassesThrough() {
    #expect(StreamCard.qualityBesideBitrate("Original") == "Original")
    #expect(StreamCard.qualityBesideBitrate(nil) == nil)
  }
}
