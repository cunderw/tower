import SwiftUI
import TowerCore

/// One row in the shares list: the share's name, and its comment underneath when
/// it has one.
///
/// **Nothing size-related, on purpose.** The obvious row for a share would
/// carry its usage, and `Share` appears to offer exactly that — but
/// `used`/`free` report the *pool's* figures, so a list built from them reads
/// "backups 20 TB, documents 20 TB, isos 20 TB" and looks entirely
/// plausible while being wrong about every row. No test catches that; checking
/// a total against the array size does. See `Share`'s own doc comment. The pool
/// figures appear once, on the detail screen, under a section that says whose
/// they are.
///
/// Built from `DashboardRow` like every other row in the app, with
/// `showsChevron: false` because `ShareListView` wraps this in a
/// `NavigationLink` inside a real `List`, which draws its own indicator.
struct ShareRow: View {
  let share: Share

  var body: some View {
    DashboardRow(showsChevron: false) {
      VStack(alignment: .leading, spacing: 2) {
        Text(share.displayName)
          .font(.body)
        if let comment = share.comment {
          Text(comment)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }
    }
    // One VoiceOver stop per row rather than two (name, then comment), the
    // same rule as the Docker list.
    .accessibilityElement(children: .combine)
    .accessibilityIdentifier("shares.row.\(share.id)")
  }
}

#Preview {
  ZStack {
    Color(.systemGroupedBackground).ignoresSafeArea()
    VStack(spacing: 0) {
      ShareRow(share: .previewFixture(name: "appdata"))
      Divider()
      ShareRow(share: .previewFixture(name: "documents", comment: "scanned paperwork"))
      Divider()
      ShareRow(share: .previewFixture(name: "domains", comment: "saved VM instances"))
      Divider()
      ShareRow(share: .previewFixture(name: "isos", comment: "ISO images"))
      Divider()
      ShareRow(share: .previewFixture(name: "storage"))
    }
    .padding()
    .background(
      RoundedRectangle(cornerRadius: 16, style: .continuous)
        .fill(Color(.secondarySystemGroupedBackground))
    )
    .padding()
  }
}

#Preview("Accessibility Size (AX5)") {
  ZStack {
    Color(.systemGroupedBackground).ignoresSafeArea()
    VStack(spacing: 0) {
      ShareRow(share: .previewFixture(name: "documents", comment: "scanned paperwork"))
      Divider()
      ShareRow(share: .previewFixture(name: "storage"))
    }
    .padding()
  }
  .environment(\.dynamicTypeSize, .accessibility5)
}

extension Share {
  fileprivate static func previewFixture(name: String, comment: String? = nil) -> Share {
    Share(
      id: "hash:\(name)", name: name, originalName: nil, comment: comment,
      includedDisks: [], excludedDisks: [], isCached: nil, allocator: "highwater",
      splitLevel: nil, floorKilobytes: 0, copyOnWrite: "auto",
      poolUsedKilobytes: 412_000_000, poolFreeKilobytes: 588_000_000
    )
  }
}
