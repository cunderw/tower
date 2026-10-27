import SwiftUI
import TowerCore

/// One dashboard card per disk group. `DashboardView` instantiates this three
/// times — "Data Disks", "Parity", "Cache" — skipping any group whose array
/// is empty, so this view never needs its own "no disks" state.
///
/// Each row is a `NavigationLink(value:)` pushing the disk's identifier via
/// the `navigationDestination(for: ArrayDisk.ID.self)` declared on
/// `DashboardView`'s `NavigationStack`. Disks arrive already
/// sorted by `idx` from `SystemRepository` (unknowns sink to the end), so
/// this renders them as given rather than re-sorting.
struct DiskListCard: View {
  let title: String
  let disks: [ArrayDisk]

  var body: some View {
    DashboardCard(title, systemImage: "internaldrive") {
      VStack(spacing: 0) {
        ForEach(Array(disks.enumerated()), id: \.element.id) { index, disk in
          if index > 0 {
            Divider()
          }
          DiskRow(disk: disk)
        }
      }
    }
  }
}

private struct DiskRow: View {
  let disk: ArrayDisk

  var body: some View {
    // Pushes the identifier, not the `ArrayDisk` value itself.
    // `DashboardView`'s `navigationDestination(for: ArrayDisk.ID.self)`
    // re-resolves this disk from the store on every render, so the 30s poll
    // reaches the pushed screen instead of freezing it at today's snapshot.
    NavigationLink(value: disk.id) {
      DashboardRow {
        VStack(alignment: .leading, spacing: 6) {
          HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
              HStack(spacing: 4) {
                Text(disk.displayName)
                // The glyph is `Label("", systemImage:
                // "exclamationmark.triangle.fill")` in `.orange` when
                // `!disk.isHealthy`. `.iconOnly` drops the empty-string title
                // from layout rather than reserving space for a zero-width
                // `Text`. The empty title left the merged row accessibility
                // label with no status text at all — `subtitle` carries that in
                // text, so the glyph is purely decorative and explicitly hidden
                // from the accessibility tree rather than contributing a
                // redundant empty element to it.
                if !disk.isHealthy {
                  Label("", systemImage: "exclamationmark.triangle.fill")
                    .labelStyle(.iconOnly)
                    .foregroundStyle(.orange)
                    .accessibilityHidden(true)
                }
              }
              Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
              Text(Formatters.temperature(disk.temp))
                .foregroundStyle(Color(usageLevel: .forTemperature(disk.temp)))
              Text(disk.capacityLine)
                .font(.caption)
                .foregroundStyle(.secondary)
            }
          }
          // Parity disks have no filesystem, and a disk mid-format — or one
          // whose filesystem is mounted but hasn't been sampled yet — reports
          // `fsSize` without `fsUsed`. `usedFraction` is `Double?` precisely so
          // this is a compiler-enforced `if let` on the pair rather than a
          // hand-written `fsSize`-only check that would still draw a
          // healthy-looking empty 0% bar for the second case. See
          // `ArrayDisk.usedFraction`: nil means not reported, never zero.
          if let fraction = disk.usedFraction {
            ProgressView(value: fraction)
              .tint(Color(usageLevel: .forFraction(fraction)))
          }
        }
      }
    }
    .buttonStyle(.plain)
    .accessibilityIdentifier("disk.row.\(disk.id)")
  }

  /// Device (or filesystem) line, with the humanised status appended for an
  /// unhealthy disk — the only place on the dashboard this is signalled in
  /// text, because the icon beside it is decorative. `ArrayDisk.statusText` is
  /// `nil` only when the server sent no status at all, which `isHealthy` also
  /// treats as unhealthy (`status == "DISK_OK"` is false for `nil`) — the
  /// `if let` guards that case so the line falls back to just the device rather
  /// than appending nothing after a stray separator.
  private var subtitle: String {
    let device = disk.device ?? disk.fsType ?? "—"
    guard !disk.isHealthy, let statusText = disk.statusText else { return device }
    return "\(device) · \(statusText)"
  }
}

#Preview("Data disks") {
  ZStack {
    Color(.systemGroupedBackground).ignoresSafeArea()
    ScrollView {
      NavigationStack {
        DiskListCard(title: "Data Disks", disks: [
          .rowPreviewFixture(id: "disk1", idx: 1, name: "disk1", device: "sdb", temp: 34, fsUsed: 2_400_000_000, fsSize: 4_000_000_000, type: "DATA"),
          .rowPreviewFixture(id: "disk2", idx: 2, name: "disk2", device: "sdc", status: "DISK_DSBL", temp: 58, fsUsed: 3_900_000_000, fsSize: 4_000_000_000, type: "DATA"),
        ])
        .padding()
      }
    }
  }
}

#Preview("Parity — no filesystem") {
  ZStack {
    Color(.systemGroupedBackground).ignoresSafeArea()
    ScrollView {
      NavigationStack {
        DiskListCard(title: "Parity", disks: [
          .rowPreviewFixture(id: "parity1", idx: 0, name: "parity", device: "sda", temp: 31, fsUsed: nil, fsSize: nil, type: "PARITY"),
        ])
        .padding()
      }
    }
  }
}

#Preview("Accessibility Size (AX5)") {
  ZStack {
    Color(.systemGroupedBackground).ignoresSafeArea()
    ScrollView {
      NavigationStack {
        DiskListCard(title: "Data Disks", disks: [
          .rowPreviewFixture(id: "disk1", idx: 1, name: "disk1", device: "sdb", temp: 34, fsUsed: 2_400_000_000, fsSize: 4_000_000_000, type: "DATA"),
        ])
        .padding()
      }
    }
  }
  .environment(\.dynamicTypeSize, .accessibility5)
}

extension ArrayDisk {
  /// "Used of capacity", or the capacity alone for a disk that reports no
  /// used figure: a parity disk has no filesystem, and "— of 12 TB" reads as
  /// a value that failed to load.
  var capacityLine: String {
    guard let fsUsed else { return Formatters.kilobytes(capacityKilobytes) }
    return "\(Formatters.kilobytes(fsUsed)) of \(Formatters.kilobytes(capacityKilobytes))"
  }

  /// A convenience fixture for this file's row previews only: derives
  /// `fsFree` from `fsSize`/`fsUsed` and fixes the read/write/error counters
  /// to plausible constants, since `DiskListCard`'s row doesn't render them.
  /// Not the same fixture as `ArrayDisk.previewFixture` in
  /// `DiskDetailView.swift`, which takes every `ArrayDisk` field directly
  /// because its detail screen renders all of them — same name, adjacent
  /// files, different semantics would be confusing, hence the distinct name.
  fileprivate static func rowPreviewFixture(
    id: String, idx: Int?, name: String, device: String?, status: String = "DISK_OK",
    temp: Int?, fsUsed: Int64?, fsSize: Int64?, type: String
  ) -> ArrayDisk {
    ArrayDisk(
      id: id, idx: idx, name: name, device: device, status: status, temp: temp,
      size: fsSize, fsFree: fsSize.map { $0 - (fsUsed ?? 0) }, fsUsed: fsUsed, fsSize: fsSize,
      fsType: fsSize != nil ? "xfs" : nil, rotational: true, numReads: 120_000,
      numWrites: 4_200, numErrors: 0, type: type
    )
  }
}
