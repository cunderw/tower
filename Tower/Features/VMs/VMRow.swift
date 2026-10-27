import SwiftUI
import TowerCore

/// One row in the VM list. Built from `DashboardRow` so this doesn't become
/// another hand-rolled row — see `DashboardRow`'s doc comment.
///
/// No `NavigationLink`/`Button` wrapper of its own: `VMListView` supplies that
/// (pushing the identifier), which is also why this passes
/// `showsChevron: false` — the `List` already draws a disclosure indicator for
/// a `NavigationLink` row, and `DashboardRow`'s own copy would stack visibly on
/// top of it.
///
/// Deliberately thinner than `ContainerRow`: `VmDomain` reports a name and a
/// state and nothing else (no image, no ports, no update flag), so there is no
/// second line of metadata to show. The subtitle is the state's own wording,
/// always present rather than only for non-running VMs the way
/// `ContainerRow.subtitle` does it — with no image to fall back on, a
/// running VM's row would otherwise have no subtitle at all and the list would
/// look ragged.
///
/// Swipe actions stay deliberately narrow — leading Start or Stop, trailing
/// Reboot. The full seven live in the context menu and on the detail screen: a
/// full-swipe Reset or Force Stop would put a power-cord yank one careless
/// gesture away, which is not a trade this app makes for convenience.
struct VMRow: View {
  let domain: VMDomain
  /// Whether `VMStore.inFlight` currently holds this row's ID. Swaps in a
  /// spinner while an action runs.
  let isInFlight: Bool
  let onAction: (VMAction) -> Void

  /// The action awaiting confirmation, if any — see `vmActionConfirmation`.
  @State private var pendingConfirmation: VMAction?

  var body: some View {
    DashboardRow(showsChevron: false) {
      HStack(alignment: .top, spacing: 8) {
        StateDot(state: domain.state)
          // Nudges the 8pt dot down onto the name's cap-height rather than the
          // top of the two-line block.
          .padding(.top, 6)
        VStack(alignment: .leading, spacing: 2) {
          Text(domain.displayName)
            .font(.body)
          Text(domain.state.displayName)
            .font(.caption)
            .foregroundStyle(.secondary)
            // `StateDot` already contributes `state.displayName` to the merged
            // label below, and this text repeats it verbatim for sighted users
            // (colour is never the only signal). Hiding it
            // from the merge keeps VoiceOver from saying the state twice —
            // `ContainerRow` solves the same double-read by overriding its
            // subtitle's label instead, but there the subtitle carries the
            // image as well; here there is nothing left to say.
            .accessibilityHidden(true)
        }
        Spacer()
        if isInFlight {
          // Decorative: announcing "busy" mid-VoiceOver-swipe, with no further
          // action to offer, would be noise rather than information.
          ProgressView()
            .controlSize(.small)
            .accessibilityHidden(true)
        }
      }
    }
    // Without this, VoiceOver stops on the dot, the name, and the subtitle as
    // three separate elements per row. Merging makes one swipe read state then
    // name — the order the row lays out visually.
    .accessibilityElement(children: .combine)
    .accessibilityIdentifier("vms.row.\(domain.id)")
    .swipeActions(edge: .leading, allowsFullSwipe: true) { leadingSwipeAction }
    .swipeActions(edge: .trailing, allowsFullSwipe: true) { trailingSwipeAction }
    .contextMenu { contextMenuActions }
    .vmActionConfirmation(pending: $pendingConfirmation, vmNamed: domain.displayName, perform: onAction)
  }

  // MARK: - Actions

  private func request(_ action: VMAction) {
    requestVMAction(action, vmNamed: domain.displayName, pending: $pendingConfirmation, perform: onAction)
  }

  /// The one action from this state's set that reads as "the main thing you'd
  /// want to do" — Start when the VM is off, Stop when it is up, Resume when
  /// paused. Nothing at all for an indeterminate state: the only action offered
  /// there is Force Stop, and a full-swipe Force Stop is precisely what this
  /// row refuses to have.
  private var leadingAction: VMAction? {
    let available = VMActionCatalog.actions(for: domain.state)
    return [.start, .resume, .stop].first { available.contains($0) }
  }

  @ViewBuilder
  private var leadingSwipeAction: some View {
    if let action = leadingAction {
      Button {
        request(action)
      } label: {
        Label(action.title, systemImage: VMActionCatalog.systemImage(for: action))
      }
      // Green for the actions that bring a VM up, red for the one that takes it
      // down. `.tint` on a swipe button is the button's own colour, not the
      // ambient tint, so this is safe — unlike `AnyShapeStyle.usage(_:)`, which
      // recurses if passed to `.tint`.
      .tint(VMActionCatalog.isDestructive(action) ? .red : .green)
      // Belt-and-suspenders: `VMStore.perform(_:on:)`'s own in-flight guard is
      // the real source of truth; this keeps a busy row from visually offering
      // an action it would immediately drop.
      .disabled(isInFlight)
    }
  }

  @ViewBuilder
  private var trailingSwipeAction: some View {
    // Only for a VM that can actually be rebooted. A paused or stopped VM gets
    // no trailing swipe rather than a button that would always be refused.
    if VMActionCatalog.actions(for: domain.state).contains(.reboot) {
      Button {
        request(.reboot)
      } label: {
        Label(VMAction.reboot.title, systemImage: VMActionCatalog.systemImage(for: .reboot))
      }
      .disabled(isInFlight)
    }
  }

  /// Every action this state allows, in the catalog's order — graceful first,
  /// power-cord last.
  @ViewBuilder
  private var contextMenuActions: some View {
    ForEach(VMActionCatalog.actions(for: domain.state), id: \.self) { action in
      Button(role: VMActionCatalog.isDestructive(action) ? .destructive : nil) {
        request(action)
      } label: {
        Label(action.title, systemImage: VMActionCatalog.systemImage(for: action))
      }
      .disabled(isInFlight)
    }
  }
}

#Preview {
  ZStack {
    Color(.systemGroupedBackground).ignoresSafeArea()
    VStack(spacing: 0) {
      VMRow(domain: .previewFixture(name: "Arcade Box", state: .running), isInFlight: false) { _ in }
      Divider()
      VMRow(domain: .previewFixture(name: "Media Server", state: .running), isInFlight: true) { _ in }
      Divider()
      VMRow(domain: .previewFixture(name: "Windows XP", state: .shutoff), isInFlight: false) { _ in }
      Divider()
      VMRow(domain: .previewFixture(name: "Ubuntu Build", state: .paused), isInFlight: false) { _ in }
      Divider()
      VMRow(domain: .previewFixture(name: "Old Server", state: .shutdown), isInFlight: false) { _ in }
      Divider()
      // Unnamed: `name` is nullable, and this is what the fallback renders.
      VMRow(
        domain: VMDomain(id: "hash:00000000-0000-4000-8000-000000000001", name: nil, state: .crashed),
        isInFlight: false
      ) { _ in }
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
      VMRow(domain: .previewFixture(name: "Media Server", state: .running), isInFlight: false) { _ in }
      Divider()
      VMRow(domain: .previewFixture(name: "Windows XP", state: .shutdown), isInFlight: false) { _ in }
    }
    .padding()
  }
  .environment(\.dynamicTypeSize, .accessibility5)
}

extension VMDomain {
  fileprivate static func previewFixture(name: String, state: VMState) -> VMDomain {
    VMDomain(id: "hash:\(name.lowercased().replacingOccurrences(of: " ", with: "-"))", name: name, state: state)
  }
}
