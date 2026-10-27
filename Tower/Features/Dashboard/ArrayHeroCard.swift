import SwiftUI
import TowerCore

/// The dashboard's hero card: array state, capacity ring, disk counts, and
/// parity check status. The single most-looked-at surface in the app.
struct ArrayHeroCard: View {
  let snapshot: DashboardSnapshot

  // At the largest accessibility text sizes the capacity ring (itself
  // `@ScaledMetric`, see `CapacityRing`) grows large enough that it and the
  // detail column no longer fit side by side on one screen, the same
  // hazard as any three-up row. Below AX sizes the two sit in
  // an `HStack`; at AX sizes they stack vertically instead.
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  private var array: ArrayStatus { snapshot.array }
  private var parity: ParityStatus { snapshot.parity }

  var body: some View {
    DashboardCard("Array", systemImage: "externaldrive.fill") {
      VStack(alignment: .leading, spacing: 16) {
        capacitySection
        if parity.isActive {
          parityProgressSection
        } else if let lastParityCheckLine {
          Text(lastParityCheckLine)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }
    } accessory: {
      statusPill
    }
  }

  @ViewBuilder
  private var capacitySection: some View {
    if dynamicTypeSize.isAccessibilitySize {
      VStack(spacing: 16) {
        capacityRing
        capacityDetails
        diskCounts
      }
      .frame(maxWidth: .infinity)
    } else {
      VStack(alignment: .leading, spacing: 12) {
        HStack(spacing: 20) {
          capacityRing
          capacityDetails
        }
        diskCounts
      }
    }
  }

  // A nil `capacity` means the server response failed to parse — see
  // `ArrayCapacity`'s doc comment. `CapacityRing` renders that explicit
  // "unavailable" state itself from a nil `fraction` — nothing
  // here substitutes zeros for a reading that doesn't exist.
  private var capacityRing: some View {
    CapacityRing(
      fraction: array.capacity?.usedFraction,
      caption: capacityCaption,
      label: "Array capacity",
      identifier: "dashboard.capacityRing"
    )
  }

  private var capacityCaption: String {
    guard let capacity = array.capacity else { return "Capacity unavailable" }
    return "of \(Formatters.kilobytes(capacity.total))"
  }

  private var capacityDetails: some View {
    // `Formatters.kilobytes` already renders a nil value as "—" rather than
    // "0 KB", so these stay honest about an unavailable capacity without
    // needing their own `if let` and without the row count changing
    // depending on whether the parse succeeded.
    VStack(alignment: .leading, spacing: 8) {
      LabeledContent("Used", value: Formatters.kilobytes(array.capacity?.used))
      LabeledContent("Free", value: Formatters.kilobytes(array.capacity?.free))
      LabeledContent("Total", value: Formatters.kilobytes(array.capacity?.total))
    }
  }

  /// A full-width row of its own rather than a fourth line in the column beside
  /// the ring. Used/Free/Total are short — "17.59 TB" — but the
  /// disk counts run to "9 data · 2 parity · 1 cache", which is wider than what
  /// the ring leaves, so beside the ring it wraps after "2 parity ·" and splits
  /// one list into two ragged fragments. Widening the row rather than
  /// shortening the text or capping `lineLimit`: the counts stay whole, and at
  /// accessibility sizes they can still wrap onto as many lines as they need.
  private var diskCounts: some View {
    LabeledContent(
      "Disks",
      value: "\(array.disks.count) data · \(array.parities.count) parity · \(array.caches.count) cache"
    )
    .accessibilityIdentifier("array.diskCounts")
  }

  private var statusPill: some View {
    HStack(spacing: 6) {
      Circle()
        .fill(array.isStarted ? Color.green : Color.orange)
        .frame(width: 8, height: 8)
      Text(array.state.capitalized)
    }
    .font(.subheadline)
    .foregroundStyle(.secondary)
    // The header-row-vs-accessory competition at AX5 (this pill wrapping
    // "Array" into "Ar-ray") is handled in `DashboardCard` itself, which
    // stacks its header vertically at accessibility sizes — see its doc
    // comment. No local cap needed, so this pill scales like the rest of
    // the card.
    .accessibilityIdentifier("array.state")
  }

  private var parityProgressSection: some View {
    VStack(alignment: .leading, spacing: 4) {
      // `progressFraction` still needs a concrete number for the
      // determinate `ProgressView` to render at all — that fallback is
      // intentional and left alone. The label is different: a nil
      // `progressPercent` means the server hasn't reported a reading yet
      // for this running check, not that it's genuinely at 0% — the same
      // unknown-reads-as-zero hazard the capacity ring and the errors
      // clause elsewhere in this file already guard against.
      ProgressView(value: parity.progressFraction ?? 0) {
        Text("Parity check · \(parityPercentText)\(speedSuffix)")
      }
      if parity.correcting {
        Text("Correcting")
          .font(.caption)
          .foregroundStyle(.orange)
      }
    }
    .accessibilityIdentifier("array.parityProgress")
  }

  private var parityPercentText: String {
    guard let percent = parity.progressPercent else { return "—" }
    return "\(percent)%"
  }

  /// Empty whenever there's nothing honest to append: `speed` is a free-form
  /// string, not a number (do not assume it parses), and Unraid sends the
  /// literal string `"0"` while idle. That sentinel means
  /// "not a genuine reading," not "0 MB/s mid-check," so it's filtered out
  /// here exactly like a nil value would be — this section only ever renders
  /// while `parity.isActive` in the first place.
  private var speedSuffix: String {
    guard let speed = parity.speed, !speed.isEmpty, speed != "0" else { return "" }
    return " · \(speed)"
  }

  /// `nil` whenever there's nothing honest to say: no check has ever run, or
  /// the timestamp the server sent doesn't parse. Printing "Unknown" (or
  /// "0 errors" for a nil `errors`) would fabricate a reading; omitting the
  /// line — or, for `errors`/`durationSeconds`, just that clause — is
  /// deliberate rather than a fixed `"...\(errors) errors"` string: a
  /// `null` error count (or duration) on a completed check is exactly the
  /// kind of unknown-reads-as-zero failure mode the capacity ring's nil
  /// handling above already guards against.
  private var lastParityCheckLine: String? {
    guard !parity.isActive,
          let timestamp = parity.lastRunTimestamp,
          let date = Formatters.parseTimestamp(timestamp)
    else { return nil }
    var line = "Last parity check \(date.formatted(.relative(presentation: .named)))"
    if let durationSeconds = parity.durationSeconds {
      line += " · \(Formatters.duration(seconds: durationSeconds))"
    }
    if let errors = parity.errors {
      line += " · \(Formatters.count(errors, "error"))"
    }
    return line
  }
}

#Preview("Healthy, started") {
  ZStack {
    Color(.systemGroupedBackground).ignoresSafeArea()
    ScrollView {
      ArrayHeroCard(snapshot: .heroPreviewFixture())
        .padding()
    }
  }
}

#Preview("Parity check running") {
  ZStack {
    Color(.systemGroupedBackground).ignoresSafeArea()
    ScrollView {
      ArrayHeroCard(snapshot: .heroPreviewFixture(
        parity: ParityStatus(
          state: .running, progressPercent: 42, errors: nil, speed: "150 MB/s",
          lastRunTimestamp: nil, durationSeconds: nil, correcting: true
        )
      ))
      .padding()
    }
  }
}

#Preview("Capacity unavailable") {
  ZStack {
    Color(.systemGroupedBackground).ignoresSafeArea()
    ScrollView {
      ArrayHeroCard(snapshot: .heroPreviewFixture(capacity: nil))
        .padding()
    }
  }
}

/// AX5 is the largest Dynamic Type size and the one most likely to break the
/// side-by-side ring/details layout. Kept alongside the default-size previews
/// so the regression is visible without a device in hand.
#Preview("Accessibility Size (AX5)") {
  ZStack {
    Color(.systemGroupedBackground).ignoresSafeArea()
    ScrollView {
      ArrayHeroCard(snapshot: .heroPreviewFixture())
        .padding()
    }
  }
  .environment(\.dynamicTypeSize, .accessibility5)
}

extension DashboardSnapshot {
  fileprivate static func heroPreviewFixture(
    capacity: ArrayCapacity? = ArrayCapacity(free: 36_570_000_000, used: 58_050_000_000, total: 94_620_000_000),
    parity: ParityStatus = ParityStatus(
      state: .completed, progressPercent: 100, errors: 0, speed: nil,
      lastRunTimestamp: "2026-01-01T00:00:00Z", durationSeconds: 37_800, correcting: false
    )
  ) -> DashboardSnapshot {
    DashboardSnapshot(
      array: ArrayStatus(
        state: "STARTED",
        capacity: capacity,
        disks: (1...20).map { previewDisk(id: "disk\($0)", type: "Data") },
        parities: (1...2).map { previewDisk(id: "parity\($0)", type: "Parity") },
        caches: (1...2).map { previewDisk(id: "cache\($0)", type: "Cache") },
        system: nil
      ),
      parity: parity,
      services: ServiceCounts(
        containersRunning: 0, containersTotal: 0, vmsRunning: 0, vmsTotal: 0,
        sharesTotal: 0
      )
    )
  }

  private static func previewDisk(id: String, type: String) -> ArrayDisk {
    ArrayDisk(
      id: id, idx: nil, name: id, device: nil, status: "DISK_OK", temp: 34,
      size: nil, fsFree: nil, fsUsed: nil, fsSize: nil, fsType: nil,
      rotational: nil, numReads: nil, numWrites: nil, numErrors: nil, type: type
    )
  }
}
