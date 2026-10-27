import Foundation

public enum Formatters {
  /// Unraid reports `info.os.uptime` as a boot *timestamp*, not a duration.
  ///
  /// `Date.ISO8601FormatStyle` is a genuine value type and `Sendable`,
  /// unlike `ISO8601DateFormatter`, so it caches cleanly as `static let`
  /// under Swift 6 strict concurrency instead of allocating per call. A
  /// single style with `includingFractionalSeconds: true` parses both the
  /// fractional-second timestamps Unraid sends (e.g.
  /// `"2026-01-01T00:00:00.250Z"`) and plain `Z`-suffixed ones (e.g.
  /// `"2026-01-01T00:00:00Z"`).
  private static let isoFormatStyle = Date.ISO8601FormatStyle(includingFractionalSeconds: true)

  public static func parseTimestamp(_ value: String) -> Date? {
    try? isoFormatStyle.parse(value)
  }

  public static func uptime(sinceTimestamp value: String, now: Date = .now) -> String {
    guard let boot = parseTimestamp(value) else { return "Unknown" }
    return uptime(since: boot, now: now)
  }

  public static func uptime(since boot: Date, now: Date = .now) -> String {
    breakdown(seconds: Int(max(0, now.timeIntervalSince(boot))))
  }

  /// A completed parity check's `durationSeconds` — a full check on a large
  /// array can run well past a day, so this shares `uptime`'s day/hour/minute
  /// breakdown rather than assuming anything under 24h.
  public static func duration(seconds: Int) -> String {
    breakdown(seconds: max(0, seconds))
  }

  private static func breakdown(seconds total: Int) -> String {
    let days = total / 86_400
    let hours = (total % 86_400) / 3_600
    let minutes = (total % 3_600) / 60
    if days > 0 { return "\(days)d \(hours)h \(minutes)m" }
    if hours > 0 { return "\(hours)h \(minutes)m" }
    return "\(minutes)m"
  }

  public static func bytes(_ value: Int64?) -> String {
    guard let value else { return "—" }
    return ByteCountFormatter.string(fromByteCount: value, countStyle: .file)
  }

  /// Unraid reports array capacity and disk sizes in kilobytes.
  public static func kilobytes(_ value: Int64?) -> String {
    guard let value else { return "—" }
    return bytes(value * 1_024)
  }

  public static func temperature(_ value: Int?) -> String {
    guard let value else { return "—" }
    return "\(value)°C"
  }

  /// A transfer rate, for the download clients.
  ///
  /// **Zero renders as an em dash, not "Zero KB/s".** Most rows in a download
  /// queue are idle, and a column of "Zero KB/s" is both wrong-looking and what
  /// `ByteCountFormatter` actually produces for 0 — it spells the number.
  public static func speed(bytesPerSecond value: Int64?) -> String {
    guard let value, value > 0 else { return "—" }
    return "\(bytes(value))/s"
  }

  /// A count with its noun, pluralised.
  ///
  /// One place for it means a new count is a call rather than another chance
  /// to write "1 albums".
  ///
  /// `plural` is for nouns English doesn't form by adding an s — pass it rather
  /// than accepting "entrys".
  ///
  /// The number is grouped for `locale` ("1,284"). A returned `String` reaches
  /// `Text` verbatim, so the grouping a `Text("\(count) …")` interpolation adds
  /// does not happen here unless this does it.
  public static func count(
    _ value: Int, _ singular: String, plural: String? = nil, locale: Locale = .autoupdatingCurrent
  ) -> String {
    let noun = value == 1 ? singular : (plural ?? singular + "s")
    return "\(value.formatted(.number.locale(locale))) \(noun)"
  }

  /// A stream's bitrate, for Tautulli.
  ///
  /// **Kilobits, not kilobytes** — Tautulli's `bandwidth` is kbps, the unit
  /// Plex quotes everywhere, and reusing `speed(bytesPerSecond:)` here would
  /// under-report every stream by a factor of eight. Formatted by hand rather
  /// than through `ByteCountFormatter`, which has no bit-based style and would
  /// spell a zero as "Zero".
  public static func bitrate(kilobitsPerSecond value: Int?) -> String {
    guard let value, value > 0 else { return "—" }
    if value < 1_000 { return "\(value) kbps" }
    let megabits = Double(value) / 1_000
    // One decimal below 10 Mbps, none above: "1.5 Mbps" is useful, "24.5 Mbps"
    // is noise next to a progress bar.
    return megabits < 10
      ? String(format: "%.1f Mbps", megabits)
      : "\(Int(megabits.rounded())) Mbps"
  }

  /// A countdown, for an ETA. `nil`, meaning the client has no estimate, is an
  /// em dash rather than a fabricated duration.
  public static func eta(_ value: TimeInterval?) -> String {
    guard let value, value > 0 else { return "—" }
    return duration(seconds: Int(value))
  }
}
