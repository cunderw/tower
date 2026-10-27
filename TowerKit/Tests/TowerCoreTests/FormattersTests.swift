import Foundation
import Testing
@testable import TowerCore

@Test func uptimeFormatsDaysHoursMinutesFromBootTimestamp() {
  let boot = ISO8601DateFormatter().date(from: "2026-07-01T00:00:00Z")!
  let now = ISO8601DateFormatter().date(from: "2026-07-15T03:04:00Z")!
  #expect(Formatters.uptime(since: boot, now: now) == "14d 3h 4m")
}

@Test func uptimeUnderADayOmitsDays() {
  let boot = ISO8601DateFormatter().date(from: "2026-07-15T00:00:00Z")!
  let now = ISO8601DateFormatter().date(from: "2026-07-15T05:30:00Z")!
  #expect(Formatters.uptime(since: boot, now: now) == "5h 30m")
}

@Test func uptimeParsesFractionalSecondsFromTheServer() {
  // Unraid returns e.g. "2026-01-01T00:00:00.250Z"
  let boot = Formatters.parseTimestamp("2026-01-01T00:00:00.250Z")
  let expected = ISO8601DateFormatter().date(from: "2026-01-01T00:00:00Z")!
    .addingTimeInterval(0.25)
  #expect(boot != nil)
  #expect(abs(boot!.timeIntervalSince(expected)) < 0.001)
}

@Test func uptimeParsesNonFractionalTimestampsThroughThePublicAPI() {
  // Every other uptime test builds its Date fixture with a local
  // ISO8601DateFormatter and never touches Formatters.parseTimestamp. This
  // one goes through the public entry point with a plain, non-fractional
  // timestamp, to show the one fractional-seconds style accepts that form too.
  let now = ISO8601DateFormatter().date(from: "2026-01-01T00:10:00Z")!
  #expect(Formatters.uptime(sinceTimestamp: "2026-01-01T00:00:00Z", now: now) == "10m")
}

@Test func uptimeUnderAnHourShowsMinutesOnly() {
  let boot = ISO8601DateFormatter().date(from: "2026-07-15T00:00:00Z")!
  let now = ISO8601DateFormatter().date(from: "2026-07-15T00:42:00Z")!
  #expect(Formatters.uptime(since: boot, now: now) == "42m")
}

@Test func uptimeWithAFutureBootTimeClampsToZero() {
  // Clock skew between the server and the phone is real; a boot time in the
  // future must not render as a negative or wildly wrong duration.
  let boot = ISO8601DateFormatter().date(from: "2026-07-15T12:00:00Z")!
  let now = ISO8601DateFormatter().date(from: "2026-07-15T11:00:00Z")!
  #expect(Formatters.uptime(since: boot, now: now) == "0m")
}

@Test func uptimeWithUnparseableInputIsUnknown() {
  #expect(Formatters.uptime(sinceTimestamp: "not a date", now: .now) == "Unknown")
}

@Test func kilobytesFormatsMultiTerabyteValues() {
  // 96_000_000_000 KB, about 98 TB. Assert magnitude, not
  // merely the unit string: a formatter returning "0 TB" would pass a
  // contains("TB") check while being completely wrong.
  let formatted = Formatters.kilobytes(96_000_000_000)
  #expect(formatted.contains("TB"))
  #expect(formatted.hasPrefix("98"))
}

@Test func kilobytesAndBytesRenderNilAsADash() {
  #expect(Formatters.kilobytes(nil) == "—")
  #expect(Formatters.bytes(nil) == "—")
}

@Test func kilobytesMultipliesByOneKibibyte() {
  // Guards the KB→bytes conversion specifically: without the *1024, this
  // renders roughly a thousandth of the true size.
  #expect(Formatters.bytes(2_048) == Formatters.kilobytes(2))
}

@Test func temperatureAppendsCelsius() {
  #expect(Formatters.temperature(36) == "36°C")
  #expect(Formatters.temperature(nil) == "—")
}

@Test func durationFormatsDaysHoursMinutesFromSeconds() {
  // 37_800s, a parity check's length on a large array.
  #expect(Formatters.duration(seconds: 37_800) == "10h 30m")
}

@Test func durationOverADayIncludesDays() {
  #expect(Formatters.duration(seconds: 100_000) == "1d 3h 46m")
}

@Test func durationUnderAnHourShowsMinutesOnly() {
  #expect(Formatters.duration(seconds: 300) == "5m")
}

@Test func durationClampsNegativeToZero() {
  #expect(Formatters.duration(seconds: -10) == "0m")
}

// MARK: - Transfer rates

@Test func speedAppendsPerSecondToAByteCount() {
  #expect(Formatters.speed(bytesPerSecond: 12_582_912).hasSuffix("/s"))
  #expect(Formatters.speed(bytesPerSecond: 12_582_912).contains("MB"))
}

@Test func anIdleSpeedIsADashRatherThanZeroKBPerSecond() {
  // Most rows in a download queue are idle, and `ByteCountFormatter` spells 0 as
  // "Zero KB" — a column of "Zero KB/s" is both wrong-looking and noisy.
  #expect(Formatters.speed(bytesPerSecond: 0) == "—")
  #expect(Formatters.speed(bytesPerSecond: nil) == "—")
  // A negative rate is not a thing; it should not render as one either.
  #expect(Formatters.speed(bytesPerSecond: -1) == "—")
}

// MARK: - Counts

@Test func aCountOfOneIsSingular() {
  #expect(Formatters.count(1, "album") == "1 album")
  #expect(Formatters.count(0, "album") == "0 albums")
  #expect(Formatters.count(2, "album") == "2 albums")
}

@Test func aLargeCountGroupsItsDigits() {
  // A returned String reaches `Text` verbatim, so the count has to carry its
  // own grouping; "1284 queries" sat beside "4,902 ms" in one row.
  let english = Locale(identifier: "en_US")
  #expect(Formatters.count(1_284, "query", plural: "queries", locale: english) == "1,284 queries")
  #expect(Formatters.count(999, "grab", locale: english) == "999 grabs")
}

@Test func anIrregularPluralCanBeGiven() {
  #expect(Formatters.count(1, "entry", plural: "entries") == "1 entry")
  #expect(Formatters.count(3, "entry", plural: "entries") == "3 entries")
}

// MARK: - Stream bitrates

@Test func bitrateIsKilobitsNotKilobytes() {
  // Tautulli's unit is kbps. Routing this through `speed(bytesPerSecond:)`
  // would under-report every stream by a factor of eight.
  #expect(Formatters.bitrate(kilobitsPerSecond: 800) == "800 kbps")
  #expect(Formatters.bitrate(kilobitsPerSecond: 1_500) == "1.5 Mbps")
  // No decimal once the number is big enough for one to be noise.
  #expect(Formatters.bitrate(kilobitsPerSecond: 24_500) == "25 Mbps")
}

@Test func anIdleStreamBitrateIsADash() {
  #expect(Formatters.bitrate(kilobitsPerSecond: 0) == "—")
  #expect(Formatters.bitrate(kilobitsPerSecond: nil) == "—")
  #expect(Formatters.bitrate(kilobitsPerSecond: -1) == "—")
}

@Test func etaRendersADurationAndADashForNoEstimate() {
  // nil means the client has no estimate; fabricating a
  // duration for it is the bug this guards.
  #expect(Formatters.eta(nil) == "—")
  #expect(Formatters.eta(0) == "—")
  #expect(Formatters.eta(3_600) == "1h 0m")
  #expect(Formatters.eta(90) == "1m")
}
