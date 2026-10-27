import SwiftUI
import TowerCore

/// Pushed from a `DiskListCard` row via `navigationDestination(for:
/// ArrayDisk.ID.self)` on `DashboardView`'s `NavigationStack`.
///
/// Takes the store and an identifier, not a disk value: `disk` below
/// re-resolves from `store.state` on every render, so the dashboard's
/// 30-second poll (or a future mutation) reaches this screen while it's
/// open instead of leaving it frozen at whatever was true when it was
/// pushed. The identifier is stable across that refresh — Unraid's disk
/// identity is derived from server and device identity, not array
/// position — so the lookup keeps finding the same disk across polls.
struct DiskDetailView: View {
  let store: DashboardStore
  let diskID: ArrayDisk.ID

  /// `nil` when this disk is no longer in the latest snapshot — it can drop
  /// out of the array while this screen is open. That's a real state to
  /// render (`ContentUnavailableView` below), not a defensive nicety: this
  /// screen must neither crash on a force-unwrap nor keep showing a disk the
  /// store no longer has.
  private var disk: ArrayDisk? {
    store.state.value?.array.disk(id: diskID)
  }

  var body: some View {
    if let disk {
      DiskDetailContent(disk: disk)
    } else {
      DiskNotFoundView()
    }
  }
}

/// The not-found state: rendered when `DiskDetailView`'s lookup
/// comes back nil. A dedicated type, not inlined into `DiskDetailView.body`,
/// so it can be previewed without standing up a `DashboardStore`.
private struct DiskNotFoundView: View {
  var body: some View {
    ContentUnavailableView(
      "Disk Not Found",
      systemImage: "externaldrive.trianglebadge.exclamationmark",
      description: Text("This disk is no longer part of the array.")
    )
  }
}

/// The disk readout: "render a known disk", split from `DiskDetailView`'s
/// "resolve the disk from the store".
///
/// Parity disks carry no filesystem at all — `fsSize`, `fsFree`, `fsUsed`,
/// and `fsType` are legitimately absent, not zero — so every row here omits
/// itself when its backing value is nil rather than rendering an em dash for
/// a field that doesn't apply to this disk type. A parity disk's screen
/// should read as "this disk has a size but no filesystem", never as a wall
/// of dashes or (worse) a fabricated 0%/0-count reading.
private struct DiskDetailContent: View {
  let disk: ArrayDisk

  var body: some View {
    List {
      capacitySection
      deviceSection
      activitySection
    }
    .navigationTitle(disk.displayName)
    .navigationBarTitleDisplayMode(.large)
  }

  // MARK: - Capacity

  @ViewBuilder
  private var capacitySection: some View {
    // `capacityKilobytes` is `fsSize ?? size` — nil only when the server
    // sent neither, which would make every row below meaningless too.
    if let capacityKilobytes = disk.capacityKilobytes {
      Section("Capacity") {
        HStack {
          Spacer()
          capacityRing(capacityKilobytes: capacityKilobytes)
          Spacer()
        }
        .listRowBackground(Color.clear)
        // `fsUsed`/`fsFree` are filesystem-level and absent on parity disks
        // (which reach this section only via the raw `size` fallback) — omit
        // rather than dash.
        if let fsUsed = disk.fsUsed {
          LabeledContent("Used", value: Formatters.kilobytes(fsUsed))
        }
        if let fsFree = disk.fsFree {
          LabeledContent("Free", value: Formatters.kilobytes(fsFree))
        }
        LabeledContent("Size", value: Formatters.kilobytes(capacityKilobytes))
      }
    }
  }

  /// Mirrors `ArrayHeroCard.capacityRing`'s nil handling one level down: a
  /// real `fsUsed`/`fsSize` pair draws a genuine usage ring, but a parity
  /// disk has no such pair — only the device's raw `size` — and a disk
  /// mid-format (or one not yet sampled) reports `fsSize` without `fsUsed`.
  /// `usedFraction` is `Double?` for exactly this reason, and
  /// `CapacityRing` owns the nil-fraction branch itself — a
  /// nil `disk.usedFraction` passes straight through rather than this view
  /// hand-rolling a second "—" ring to match `ArrayHeroCard`'s.
  private func capacityRing(capacityKilobytes: Int64) -> some View {
    CapacityRing(
      fraction: disk.usedFraction,
      caption: "of \(Formatters.kilobytes(capacityKilobytes))",
      label: "\(disk.displayName) capacity",
      identifier: "diskDetail.capacityRing",
      diameter: 110
    )
  }

  // MARK: - Device

  @ViewBuilder
  private var deviceSection: some View {
    Section("Device") {
      if let device = disk.device {
        LabeledContent("Device", value: device)
      }
      if let type = disk.type {
        LabeledContent("Type", value: type.capitalized)
      }
      if let statusText = disk.statusText {
        LabeledContent("Status", value: statusText)
      }
      if let temp = disk.temp {
        LabeledContent("Temperature", value: Formatters.temperature(temp))
          .foregroundStyle(Color(usageLevel: .forTemperature(temp)))
      }
      // Omitted (not just its value) when nil — `nil` here
      // means the server didn't report rotational-ness, not that it's
      // solid-state.
      if let rotational = disk.rotational {
        LabeledContent("Media", value: rotational ? "Hard drive" : "Solid state")
      }
      if let fsType = disk.fsType {
        LabeledContent("Filesystem", value: fsType)
      }
    }
  }

  // MARK: - Activity

  @ViewBuilder
  private var activitySection: some View {
    // A parity disk (or any disk the server hasn't reported counters for
    // yet) can have all three nil. Omitting the whole section rather than
    // showing an "Activity" header over zero rows is the same
    // no-empty-chrome reasoning `capacitySection` applies to `Capacity`.
    if disk.numReads != nil || disk.numWrites != nil || disk.numErrors != nil {
      Section("Activity") {
        // `numReads`/`numWrites`/`numErrors` are `Int64?` — nil means "not
        // reported", not zero, so each row is omitted rather than dashed.
        // A null `numErrors` rendered as "— errors" reads as fine just as
        // easily as it reads as unknown, which is exactly the
        // unknown-reads-as-zero failure mode `ArrayHeroCard`'s parity
        // `errors` handling already guards against.
        // The `String`-valued `LabeledContent(_:value:)` overload, formatting
        // the number ourselves, rather than `LabeledContent(_:value:format:)`
        // — kept consistent with every other row on this screen (Device,
        // Filesystem, …), all of which use the same overload.
        if let numReads = disk.numReads {
          LabeledContent("Reads", value: numReads.formatted(.number))
        }
        if let numWrites = disk.numWrites {
          LabeledContent("Writes", value: numWrites.formatted(.number))
        }
        if let numErrors = disk.numErrors {
          LabeledContent("Errors", value: numErrors.formatted(.number))
            .foregroundStyle(numErrors > 0 ? .red : .primary)
        }
      }
    }
  }
}

#Preview("Data disk") {
  NavigationStack {
    DiskDetailContent(disk: .previewFixture(
      id: "disk1", idx: 1, name: "disk1", device: "sdb", status: "DISK_OK", temp: 34,
      size: 4_000_000_000, fsFree: 1_600_000_000, fsUsed: 2_400_000_000, fsSize: 4_000_000_000,
      fsType: "xfs", rotational: true, numReads: 128_552_310, numWrites: 4_221_009,
      numErrors: 0, type: "DATA"
    ))
  }
}

#Preview("Parity disk — no filesystem") {
  NavigationStack {
    DiskDetailContent(disk: .previewFixture(
      id: "parity1", idx: 0, name: "parity", device: "sda", status: "DISK_OK", temp: 31,
      size: 4_000_000_000, fsFree: nil, fsUsed: nil, fsSize: nil,
      fsType: nil, rotational: true, numReads: 98_112_004, numWrites: 12_500,
      numErrors: 0, type: "PARITY"
    ))
  }
}

#Preview("Disabled disk with errors") {
  NavigationStack {
    DiskDetailContent(disk: .previewFixture(
      id: "disk2", idx: 2, name: "disk2", device: "sdc", status: "DISK_DSBL", temp: nil,
      size: 4_000_000_000, fsFree: nil, fsUsed: nil, fsSize: nil,
      fsType: nil, rotational: nil, numReads: nil, numWrites: nil,
      numErrors: 42, type: "DATA"
    ))
  }
}

#Preview("Accessibility Size (AX5)") {
  NavigationStack {
    DiskDetailContent(disk: .previewFixture(
      id: "disk1", idx: 1, name: "disk1", device: "sdb", status: "DISK_OK", temp: 34,
      size: 4_000_000_000, fsFree: 1_600_000_000, fsUsed: 2_400_000_000, fsSize: 4_000_000_000,
      fsType: "xfs", rotational: true, numReads: 128_552_310, numWrites: 4_221_009,
      numErrors: 0, type: "DATA"
    ))
  }
  .environment(\.dynamicTypeSize, .accessibility5)
}

/// The state a disk that's dropped out of the array renders — the
/// not-found branch. Previewable on its own since it needs no store.
#Preview("Not found") {
  NavigationStack {
    DiskNotFoundView()
  }
}

extension ArrayDisk {
  /// Takes every `ArrayDisk` field directly since this screen renders all of
  /// them — not `DiskListCard.rowPreviewFixture`, its convenience-fixture
  /// namesake in that adjacent file, which derives a few fields instead
  /// because the row preview it backs doesn't render them.
  fileprivate static func previewFixture(
    id: String, idx: Int?, name: String?, device: String?, status: String?, temp: Int?,
    size: Int64?, fsFree: Int64?, fsUsed: Int64?, fsSize: Int64?, fsType: String?,
    rotational: Bool?, numReads: Int64?, numWrites: Int64?, numErrors: Int64?, type: String?
  ) -> ArrayDisk {
    ArrayDisk(
      id: id, idx: idx, name: name, device: device, status: status, temp: temp,
      size: size, fsFree: fsFree, fsUsed: fsUsed, fsSize: fsSize, fsType: fsType,
      rotational: rotational, numReads: numReads, numWrites: numWrites,
      numErrors: numErrors, type: type
    )
  }
}
