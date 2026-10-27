import SwiftUI
import TowerCore

/// The dashboard's CPU/memory two-up, plus OS and uptime. Second most-looked-
/// at surface after `ArrayHeroCard`, and built the same way: nil metrics
/// render as an honest "—" via `MetricGauge`/`LabeledContent`, never as a
/// fabricated zero.
struct SystemMetricsCard: View {
  let system: SystemInfo?

  // `MetricGauge`'s system `Gauge` control is fixed-size even as its title
  // and detail labels grow with Dynamic Type — at accessibility sizes the
  // two gauges side by side outgrow the card's width the same way
  // `ArrayHeroCard.capacitySection`'s ring/details row does. Same fix: stack
  // vertically once the size crosses into the accessibility range.
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  var body: some View {
    DashboardCard("System", systemImage: "cpu") {
      VStack(alignment: .leading, spacing: 16) {
        metricsRow
        Divider()
        VStack(alignment: .leading, spacing: 8) {
          if let osLine {
            LabeledContent("OS", value: osLine)
          }
          LabeledContent("Uptime", value: uptimeText)
        }
      }
    }
  }

  @ViewBuilder
  private var metricsRow: some View {
    if dynamicTypeSize.isAccessibilitySize {
      VStack(spacing: 20) {
        cpuGauge
        memoryGauge
      }
      .frame(maxWidth: .infinity)
    } else {
      HStack(spacing: 20) {
        cpuGauge
          .frame(maxWidth: .infinity)
        memoryGauge
          .frame(maxWidth: .infinity)
      }
    }
  }

  private var cpuGauge: some View {
    MetricGauge(title: "CPU", percent: system?.cpuPercent, detail: cpuDetail)
  }

  private var memoryGauge: some View {
    MetricGauge(title: "Memory", percent: system?.memoryPercent, detail: memoryDetail)
  }

  /// Core/thread count when the server sent both, else the CPU brand string,
  /// else nil — `MetricGauge` already omits the detail line entirely for a
  /// nil `detail` rather than showing an empty caption.
  private var cpuDetail: String? {
    if let cores = system?.cpuCores, let threads = system?.cpuThreads {
      return "\(cores) cores · \(threads) threads"
    }
    return system?.cpuBrand
  }

  /// `metrics.memory.used`/`.total` are **bytes** — the one place in this API
  /// that isn't kilobytes (array capacity, disk sizes, and share usage all
  /// are). `Formatters.bytes` here, never `Formatters.kilobytes`: the wrong
  /// one is off by 1024x and renders a plausible-looking wrong number (28.16
  /// GB as 28.84 TB) rather than an obviously broken one.
  private var memoryDetail: String? {
    guard let used = system?.memoryUsedBytes, let total = system?.memoryTotalBytes else {
      return nil
    }
    return "\(Formatters.bytes(used)) of \(Formatters.bytes(total))"
  }

  /// `"\(distro) \(release)"` when both are present. Joins only the
  /// non-nil parts rather than printing "—" in place of a missing one —
  /// "Linux —" reads like a broken field where just "Linux" reads like a
  /// partial (but honest) answer. `nil` when neither is present, which
  /// omits the whole row instead of a "— —" line that says nothing.
  private var osLine: String? {
    let parts = [system?.distro, system?.release].compactMap { $0 }
    return parts.isEmpty ? nil : parts.joined(separator: " ")
  }

  /// "—" when there's no boot timestamp to format at all, distinct from
  /// `Formatters.uptime(sinceTimestamp:)`'s own "Unknown" for a timestamp
  /// that fails to parse. Keeps the row present (same count-stays-stable
  /// reasoning as `ArrayHeroCard.capacityDetails`) rather than omitting it.
  private var uptimeText: String {
    guard let bootTimestamp = system?.bootTimestamp else { return "—" }
    return Formatters.uptime(sinceTimestamp: bootTimestamp)
  }
}

#Preview("Healthy reading") {
  ZStack {
    Color(.systemGroupedBackground).ignoresSafeArea()
    ScrollView {
      SystemMetricsCard(system: .previewFixture())
        .padding()
    }
  }
}

#Preview("Unknown metrics") {
  ZStack {
    Color(.systemGroupedBackground).ignoresSafeArea()
    ScrollView {
      SystemMetricsCard(system: nil)
        .padding()
    }
  }
}

/// AX5 is the largest Dynamic Type size and the one most likely to break the
/// side-by-side gauge row — kept alongside the default-size previews so the
/// regression is visible without a device in hand.
#Preview("Accessibility Size (AX5)") {
  ZStack {
    Color(.systemGroupedBackground).ignoresSafeArea()
    ScrollView {
      SystemMetricsCard(system: .previewFixture())
        .padding()
    }
  }
  .environment(\.dynamicTypeSize, .accessibility5)
}

extension SystemInfo {
  fileprivate static func previewFixture() -> SystemInfo {
    SystemInfo(
      distro: "Unraid OS",
      release: "7.3.0",
      bootTimestamp: "2026-01-01T00:00:00Z",
      cpuBrand: "Example 8-Core CPU",
      cpuCores: 8,
      cpuThreads: 16,
      cpuPercent: 12,
      memoryPercent: 88,
      memoryUsedBytes: 28_160_000_000,
      memoryTotalBytes: 32_000_000_000
    )
  }
}
