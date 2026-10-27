import SwiftUI

/// The dashboard's tappable-row recipe: arbitrary leading content plus a
/// trailing chevron affordance, consistent vertical padding, and a hit
/// target that covers the whole row rather than just its non-`Spacer()`
/// content.
///
/// Deliberately doesn't wrap `Button`/`NavigationLink` itself — one caller
/// acts (`ServicesCard`, a callback that switches tabs), the other navigates
/// (`DiskListCard`, `NavigationLink(value:)`) — callers supply that outer
/// shell (and its own `.buttonStyle(.plain)` and `.accessibilityIdentifier`)
/// and get only the shared layout/accessibility recipe from this type.
///
/// One type because copies of this recipe drift (vertical padding, chevron
/// font). It is 8pt and `.caption2` here, and every row that wants the recipe
/// uses this type rather than a copy.
struct DashboardRow<Content: View>: View {
  /// Whether this row draws its own trailing chevron. Defaults to `true`
  /// for the dashboard cards: `ServicesCard` and `DiskListCard` both
  /// render outside a real `List` (dashboard cards are a plain `VStack`), so
  /// their `NavigationLink`/`Button` gets no disclosure affordance for
  /// free — `DashboardRow` supplies one itself.
  ///
  /// Inside an actual `List` with `NavigationLink(value:)` rows, as in
  /// `ContainerRow` (`DockerListView`), `List` draws its own disclosure
  /// indicator, and leaving this at its default draws two stacked,
  /// slightly-offset "›" glyphs per row. Callers there pass
  /// `showsChevron: false` so the system one is the only one shown.
  var showsChevron: Bool = true
  @ViewBuilder let content: () -> Content

  var body: some View {
    HStack(alignment: .top, spacing: 8) {
      content()
      if showsChevron {
        chevron
      }
    }
    .padding(.vertical, 8)
    // The whole row is the hit target, not just its non-`Spacer()` content —
    // a `Spacer()` and empty trailing space are otherwise transparent to hit
    // testing under a `.plain` button style.
    .contentShape(Rectangle())
  }

  private var chevron: some View {
    Image(systemName: "chevron.right")
      .font(.caption2)
      .foregroundStyle(.tertiary)
      // Purely decorative — the row's own accessibility label already
      // conveys the reading. A bare `Image(systemName:)` happens to
      // contribute nothing to a merged accessibility label today, but rows
      // that add a state dot or an update badge alongside it would turn that
      // implicit "contributes nothing" into "contributes something nobody
      // decided on". Hiding it explicitly, once, here, keeps that decision
      // made regardless of what else ends up in a row's content.
      .accessibilityHidden(true)
  }
}

#Preview {
  ZStack {
    Color(.systemGroupedBackground).ignoresSafeArea()
    VStack(spacing: 0) {
      DashboardRow {
        HStack {
          Label("Docker", systemImage: "shippingbox")
          Spacer()
          Text("14 of 16 running")
            .foregroundStyle(.secondary)
        }
      }
      Divider()
      DashboardRow {
        VStack(alignment: .leading, spacing: 4) {
          Text("disk1")
          Text("sdb")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }
    }
    .padding()
    .background(
      RoundedRectangle(cornerRadius: 16, style: .continuous)
        .fill(Color(.secondarySystemGroupedBackground))
    )
    .padding()
  }
}
