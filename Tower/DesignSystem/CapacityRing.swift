import SwiftUI
import TowerCore

/// A large-format capacity indicator for the array card. The system `Gauge`
/// has no large-format style, so this is the one place a hand-rolled shape
/// is warranted — see `MetricGauge` for the system control used everywhere
/// else.
struct CapacityRing: View {
  /// `nil` means "no genuine reading" — a server response that failed to
  /// parse, or a disk with no filesystem — and renders this ring's own
  /// unknown state (a "—" title, `.unknown`'s secondary stroke colour)
  /// rather than asking every caller to hand-roll that branch.
  ///
  /// With a non-optional `Double`, `ArrayHeroCard`/`DiskDetailView` would
  /// each duplicate an `if let fraction { … } else { CapacityRing(fraction:
  /// 0, title: "—", level: .unknown, …) }`, and nothing would stop a third
  /// caller writing `capacity?.usedFraction ?? 0` and silently fabricating a
  /// healthy-looking empty reading instead. This type owns that invariant
  /// once, in the one place it's drawn.
  let fraction: Double?
  let caption: String     // e.g. "of 96.8 TB used"
  /// What VoiceOver announces as the element's identity, e.g. "Array
  /// capacity" or "Disk 1" — distinct from `title`/`caption`, which are the
  /// changing reading and are announced as the accessibility *value*.
  var label: String = "Capacity"
  /// A parameter rather than one baked-in identifier: the dashboard and the
  /// disk detail screen each query a ring, and a shared identifier would
  /// resolve only while exactly one ring is in the tree. Each screen supplies
  /// its own.
  var identifier: String = "capacityRing"
  // `.title2` can grow to ~44pt and `.caption` to ~26pt at AX5; a plain
  // fixed `CGFloat` here would let the centre text escape the stroke well
  // before that, since `.frame(width:height:)` only proposes a size rather
  // than clipping to it. `@ScaledMetric` grows the ring itself in step with
  // Dynamic Type so the stroke keeps containing its label at every size.
  @ScaledMetric(relativeTo: .title2) var lineWidth: CGFloat = 14
  @ScaledMetric(relativeTo: .title2) var diameter: CGFloat = 132

  private var level: UsageLevel {
    guard let fraction else { return .unknown }
    return .forFraction(fraction)
  }

  private var title: String {
    guard let fraction else { return "—" }
    return "\(Int((fraction * 100).rounded()))%"
  }

  var body: some View {
    ZStack {
      Circle()
        .stroke(.quaternary, lineWidth: lineWidth)
      Circle()
        .trim(from: 0, to: max(0.001, min(1, fraction ?? 0)))
        .stroke(.usage(level), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
        .rotationEffect(.degrees(-90))
        .animation(.smooth, value: fraction)
      VStack(spacing: 4) {
        Text(title)
          .font(.title2)
          .bold()
          .monospacedDigit()
          .contentTransition(.numericText())
        Text(caption)
          .font(.caption)
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
      }
    }
    .frame(width: diameter, height: diameter)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(label)
    .accessibilityValue("\(title), \(caption)")
    .accessibilityIdentifier(identifier)
  }
}

#Preview {
  ZStack {
    Color(.systemGroupedBackground).ignoresSafeArea()
    HStack(spacing: 24) {
      CapacityRing(fraction: 0.42, caption: "of 96.8 TB used", label: "Array capacity")
      CapacityRing(fraction: 0.88, caption: "of 96.8 TB used", label: "Array capacity")
      CapacityRing(fraction: 0.97, caption: "of 96.8 TB used", label: "Array capacity")
    }
    .padding()
  }
}

/// The unknown state this type owns itself — a nil
/// `fraction` renders "—" and the secondary stroke colour rather than a
/// fabricated 0%.
#Preview("Unknown") {
  ZStack {
    Color(.systemGroupedBackground).ignoresSafeArea()
    CapacityRing(fraction: nil, caption: "Capacity unavailable", label: "Array capacity")
      .padding()
  }
}

/// AX5 is the largest Dynamic Type size and the one most likely to break a
/// fixed-diameter ring; keeping this alongside the default-size preview
/// makes that regression visible without a device in hand.
#Preview("Accessibility Size (AX5)") {
  ZStack {
    Color(.systemGroupedBackground).ignoresSafeArea()
    HStack(spacing: 24) {
      CapacityRing(fraction: 0.42, caption: "of 96.8 TB used", label: "Array capacity")
      CapacityRing(fraction: 0.88, caption: "of 96.8 TB used", label: "Array capacity")
      CapacityRing(fraction: 0.97, caption: "of 96.8 TB used", label: "Array capacity")
    }
    .padding()
  }
  .environment(\.dynamicTypeSize, .accessibility5)
}
