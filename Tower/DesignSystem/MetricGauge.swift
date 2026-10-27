import SwiftUI
import TowerCore

/// A compact metric readout using the *system* circular gauge — the same
/// control iOS uses in Control Center and widgets — rather than a hand-rolled
/// arc.
struct MetricGauge: View {
  let title: String        // "CPU"
  let percent: Double?     // 0-100 as the server reports it, nil when unknown
  let detail: String?      // "28.16 GB of 32 GB", nil for CPU

  var body: some View {
    VStack(spacing: 4) {
      // No label content: `.accessoryCircular` renders whatever this
      // closure returns *inside* the ring, at very little width, which
      // truncates "Memory" to "Mem…". The title already reads in full just
      // below the gauge, so an in-ring copy would be pure redundancy.
      // `EmptyView()` rather than omitting the trailing closure — `Gauge`
      // still requires a label argument — and accessibility for the whole
      // control comes from the explicit `.accessibilityLabel`/
      // `.accessibilityValue` below rather than whatever SwiftUI would
      // otherwise derive from this.
      Gauge(value: (percent ?? 0) / 100) {
        EmptyView()
      } currentValueLabel: {
        Text(percent.map { "\(Int($0.rounded()))%" } ?? "—")
      }
      .gaugeStyle(.accessoryCircular)
      // Deliberately `Color(usageLevel:)`, not `.usage(_:)`. `.tint(_:)`
      // *sets* the environment's tint for this subtree; `.usage(.normal)`
      // resolves to `AnyShapeStyle(.tint)`, i.e. "whatever the ambient tint
      // already is" -- installing that value as the *new* ambient tint is
      // circular. SwiftUI resolves it lazily, so nothing fails to compile;
      // instead `TintShapeStyle._apply(to:)` recurses into itself
      // indefinitely the moment this view is laid out, and the app dies
      // with EXC_BAD_ACCESS ("Thread stack size exceeded due to excessive
      // recursion") -- confirmed by crash, reproducible at default Dynamic
      // Type size, not just at accessibility sizes. `Color.accentColor` is
      // a concrete value with nothing left to resolve, so it can't recurse.
      // `.usage(_:)` stays safe for direct-paint contexts like
      // `Shape.stroke(_:)` (see `CapacityRing`), which read the *current*
      // resolved tint rather than redefining it for descendants.
      .tint(Color(usageLevel: percent.map { UsageLevel.forFraction($0 / 100) } ?? .unknown))

      Text(title)
        .font(.subheadline)

      if let detail {
        Text(detail)
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
    // Matches `CapacityRing`'s treatment: the title and detail
    // `Text`s above are otherwise separate elements VoiceOver would
    // announce individually, doubling up on the title reading it once as
    // the gauge's own accessibility label and again as this `Text`.
    // `children: .ignore` merges the whole control into one element instead,
    // with an explicit label and value replacing whatever default SwiftUI
    // would otherwise compose.
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(title)
    .accessibilityValue(accessibilityValueText)
    .accessibilityIdentifier("dashboard.metricGauge.\(title.lowercased())")
  }

  /// Spells out "Unknown" for a nil `percent` rather than leaving it to
  /// `Gauge`'s default behaviour, which — with no explicit value — is free
  /// to derive something from `value: 0` (e.g. "0 percent"), indistinguishable
  /// from a genuine zero reading. Includes `detail` (e.g. "28.16 GB of 32
  /// GB") the same way `CapacityRing.accessibilityValue` folds its caption
  /// in, so VoiceOver still gets the full reading despite `children: .ignore`
  /// dropping `detail`'s own `Text` as a separate element.
  private var accessibilityValueText: String {
    let value = percent.map { "\(Int($0.rounded()))%" } ?? "Unknown"
    guard let detail else { return value }
    return "\(value), \(detail)"
  }
}

#Preview {
  ZStack {
    Color(.systemGroupedBackground).ignoresSafeArea()
    HStack(spacing: 24) {
      MetricGauge(title: "CPU", percent: 23, detail: nil)
      MetricGauge(title: "Memory", percent: 88, detail: "28.16 GB of 32 GB")
      MetricGauge(title: "Temp", percent: nil, detail: nil)
    }
    .padding()
  }
}

/// AX5 is the largest Dynamic Type size and the one most likely to reveal an
/// in-ring truncation regression — kept alongside
/// the default-size preview the same way `CapacityRing` does.
#Preview("Accessibility Size (AX5)") {
  ZStack {
    Color(.systemGroupedBackground).ignoresSafeArea()
    HStack(spacing: 24) {
      MetricGauge(title: "CPU", percent: 23, detail: nil)
      MetricGauge(title: "Memory", percent: 88, detail: "28.16 GB of 32 GB")
      MetricGauge(title: "Temp", percent: nil, detail: nil)
    }
    .padding()
  }
  .environment(\.dynamicTypeSize, .accessibility5)
}
