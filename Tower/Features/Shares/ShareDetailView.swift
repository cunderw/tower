import SwiftUI
import TowerCore
import TowerData

/// Pushed from `ShareListView`'s rows via `navigationDestination(for:
/// Share.ID.self)`. Takes the store and an identifier, not a `Share`
/// value, so a background poll reaches this screen while it is open.
struct ShareDetailView: View {
  let store: ShareStore
  let shareID: Share.ID

  /// `nil` when this share is no longer in the latest snapshot — shares do get
  /// deleted while someone is looking at them.
  private var share: Share? {
    store.state.value?.first { $0.id == shareID }
  }

  var body: some View {
    if let share {
      ShareDetailContent(share: share)
    } else {
      ShareNotFoundView()
    }
  }
}

/// The not-found state. A dedicated type so it previews without a
/// store — mirrors `ContainerNotFoundView` and `VMNotFoundView`.
private struct ShareNotFoundView: View {
  var body: some View {
    ContentUnavailableView(
      "Share Not Found",
      systemImage: "folder",
      description: Text("This share is no longer available.")
    )
  }
}

/// The share's configuration.
///
/// Takes a `Share` and not the store: unlike `ContainerDetailContent` and
/// `VMDetailContent`, nothing on this screen can act on the share, so there is
/// no in-flight state to read and no action to dispatch.
private struct ShareDetailContent: View {
  let share: Share

  var body: some View {
    List {
      allocationSection
      disksSection
      poolSection
      identitySection
    }
    .navigationTitle(share.displayName)
    .navigationBarTitleDisplayMode(.large)
  }

  // MARK: - Allocation

  /// Omitted entirely when Unraid reported none of it — a header over zero rows
  /// is the no-empty-chrome rule `DiskDetailView`'s Activity section already
  /// follows.
  @ViewBuilder
  private var allocationSection: some View {
    if hasAnyAllocationDetail {
      Section("Allocation") {
        if let allocator = share.allocator {
          LabeledContent("Method", value: allocator.capitalized)
        }
        if let splitLevel = share.splitLevel {
          LabeledContent("Split Level", value: splitLevel)
        }
        // `0` is a real answer here — "no minimum" — so it renders as such
        // rather than being hidden as if the server hadn't said.
        if let floor = share.floorKilobytes {
          LabeledContent("Minimum Free Space", value: floor == 0 ? "None" : Formatters.kilobytes(floor))
        }
        if let copyOnWrite = share.copyOnWrite {
          LabeledContent("Copy-on-Write", value: copyOnWrite.capitalized)
        }
        // Only `true`/`false` say anything; `nil` means Unraid didn't report the
        // flag at all (Unraid 7.3 leaves it unset), and rendering that as "No"
        // would be a claim about their configuration.
        if let isCached = share.isCached {
          LabeledContent("Cached", value: isCached ? "Yes" : "No")
        }
      }
    }
  }

  private var hasAnyAllocationDetail: Bool {
    share.allocator != nil || share.splitLevel != nil || share.floorKilobytes != nil
      || share.copyOnWrite != nil || share.isCached != nil
  }

  // MARK: - Disks

  private var disksSection: some View {
    Section("Disks") {
      if share.usesAllDisks {
        // The genuine meaning of two empty lists, stated in words rather than
        // left as two absent sections. True for most shares on a real server.
        Text("All disks")
          .foregroundStyle(.secondary)
          .accessibilityIdentifier("shareDetail.allDisks")
      } else {
        if !share.includedDisks.isEmpty {
          LabeledContent("Included", value: share.includedDisks.joined(separator: ", "))
        }
        if !share.excludedDisks.isEmpty {
          LabeledContent("Excluded", value: share.excludedDisks.joined(separator: ", "))
        }
      }
    }
  }

  // MARK: - Pool

  /// The one place the pool figures appear, so they are not dropped entirely.
  ///
  /// The numbers themselves cannot say whose they are: every share on this pool
  /// reports the identical pair, and a reader who takes them for this share's
  /// usage has been misled by the screen rather than by the server.
  ///
  /// **The qualifier is in the header, not only the footer.** On an iPhone
  /// this section lands at the bottom of the screen, so a footer alone sits
  /// behind the tab bar and the figures are visible with no disclaimer at all
  /// until you scroll. A caveat that can be scrolled past is not a caveat. The
  /// header carries the short version, always on screen directly above the
  /// numbers; the footer keeps the full explanation for anyone who reads on.
  @ViewBuilder
  private var poolSection: some View {
    if share.poolUsedKilobytes != nil || share.poolFreeKilobytes != nil {
      Section {
        LabeledContent("Used", value: Formatters.kilobytes(share.poolUsedKilobytes))
          .accessibilityIdentifier("shareDetail.poolUsed")
        LabeledContent("Free", value: Formatters.kilobytes(share.poolFreeKilobytes))
      } header: {
        Text("Pool — the whole pool, not this share")
          .accessibilityIdentifier("shareDetail.poolHeader")
      } footer: {
        Text("These figures describe the whole storage pool this share lives on. Unraid doesn't report per-share usage.")
          .accessibilityIdentifier("shareDetail.poolDisclaimer")
      }
    }
  }

  // MARK: - Identity

  /// Only ever shown for a renamed share — the repository maps `nameOrig` to
  /// `nil` when it matches `name`, which is the usual case.
  @ViewBuilder
  private var identitySection: some View {
    if let originalName = share.originalName {
      Section("Identity") {
        LabeledContent("Original Name", value: originalName)
      }
    }
  }
}

#Preview("Typical share") {
  NavigationStack {
    ShareDetailContent(
      share: Share(
        id: "hash:appdata", name: "appdata", originalName: nil, comment: nil,
        includedDisks: [], excludedDisks: [], isCached: nil, allocator: "highwater",
        splitLevel: nil, floorKilobytes: 0, copyOnWrite: "auto",
        poolUsedKilobytes: 412_000_000, poolFreeKilobytes: 588_000_000
      )
    )
  }
}

#Preview("Everything populated") {
  NavigationStack {
    ShareDetailContent(
      share: Share(
        id: "hash:domains", name: "domains", originalName: "Domains",
        comment: "saved VM instances", includedDisks: ["disk1", "disk2"],
        excludedDisks: ["disk3"], isCached: true, allocator: "mostfree",
        splitLevel: "1", floorKilobytes: 500_000_000, copyOnWrite: "no",
        poolUsedKilobytes: 72_000_000_000, poolFreeKilobytes: 24_000_000_000
      )
    )
  }
}

#Preview("Nothing reported") {
  NavigationStack {
    ShareDetailContent(
      share: Share(
        id: "hash:bare", name: "bare", originalName: nil, comment: nil,
        includedDisks: [], excludedDisks: [], isCached: nil, allocator: nil,
        splitLevel: nil, floorKilobytes: nil, copyOnWrite: nil,
        poolUsedKilobytes: nil, poolFreeKilobytes: nil
      )
    )
  }
}

#Preview("Accessibility Size (AX5)") {
  NavigationStack {
    ShareDetailContent(
      share: Share(
        id: "hash:documents", name: "documents", originalName: nil,
        comment: "scanned paperwork", includedDisks: [], excludedDisks: [],
        isCached: nil, allocator: "highwater", splitLevel: nil, floorKilobytes: 0,
        copyOnWrite: "auto", poolUsedKilobytes: 72_000_000_000,
        poolFreeKilobytes: 24_000_000_000
      )
    )
  }
  .environment(\.dynamicTypeSize, .accessibility5)
}

#Preview("Not found") {
  NavigationStack {
    ShareNotFoundView()
  }
}
