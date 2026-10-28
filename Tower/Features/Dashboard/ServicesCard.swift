import SwiftUI
import TowerCore

/// The dashboard's tappable services rows — Docker, VMs, Shares — each a
/// summary count plus a chevron that switches the tab bar to that
/// destination. This is the card that turns the dashboard from a readout
/// into a hub: everything else on the screen is read-only.
struct ServicesCard: View {
  let counts: ServiceCounts
  let onSelect: (TowerTab) -> Void

  var body: some View {
    DashboardCard("Services", systemImage: "square.stack.3d.up") {
      VStack(spacing: 0) {
        row(tab: .docker, summary: counts.containersSummary)
        Divider()
        row(tab: .vms, summary: counts.vmsSummary)
        Divider()
        row(tab: .shares, summary: counts.sharesSummary)
      }
    }
  }

  private func row(tab: TowerTab, summary: String) -> some View {
    Button {
      onSelect(tab)
    } label: {
      DashboardRow {
        HStack {
          Label(tab.title, systemImage: tab.systemImage)
          Spacer()
          Text(summary)
            .foregroundStyle(.secondary)
        }
      }
    }
    .buttonStyle(.plain)
    .accessibilityIdentifier("services.\(tab.rawValue)")
  }
}

#Preview {
  ZStack {
    Color(.systemGroupedBackground).ignoresSafeArea()
    ScrollView {
      ServicesCard(
        counts: ServiceCounts(
          containersRunning: 14, containersTotal: 16,
          vmsRunning: 2, vmsTotal: 3,
          sharesTotal: 9
        ),
        onSelect: { _ in }
      )
      .padding()
    }
  }
}

/// VM reporting unavailable (libvirt stopped or errored) — `vmsRunning`/
/// `vmsTotal` nil, distinct from a healthy, VM-less server's real `0`/`0`.
/// See `ServiceCounts.vmsSummary`.
#Preview("VMs unavailable") {
  ZStack {
    Color(.systemGroupedBackground).ignoresSafeArea()
    ScrollView {
      ServicesCard(
        counts: ServiceCounts(
          containersRunning: 14, containersTotal: 16,
          vmsRunning: nil, vmsTotal: nil,
          sharesTotal: 9
        ),
        onSelect: { _ in }
      )
      .padding()
    }
  }
}

/// Docker reporting unavailable (the Docker service off, its counts query
/// failed) — `containersRunning`/`containersTotal` nil. See
/// `ServiceCounts.containersSummary`.
#Preview("Docker unavailable") {
  ZStack {
    Color(.systemGroupedBackground).ignoresSafeArea()
    ScrollView {
      ServicesCard(
        counts: ServiceCounts(
          containersRunning: nil, containersTotal: nil,
          vmsRunning: 2, vmsTotal: 3,
          sharesTotal: 9
        ),
        onSelect: { _ in }
      )
      .padding()
    }
  }
}

#Preview("Accessibility Size (AX5)") {
  ZStack {
    Color(.systemGroupedBackground).ignoresSafeArea()
    ScrollView {
      ServicesCard(
        counts: ServiceCounts(
          containersRunning: 14, containersTotal: 16,
          vmsRunning: 2, vmsTotal: 3,
          sharesTotal: 9
        ),
        onSelect: { _ in }
      )
      .padding()
    }
  }
  .environment(\.dynamicTypeSize, .accessibility5)
}
