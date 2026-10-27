import SwiftUI
import TowerCore
import TowerData

/// Pushed from `VMListView`'s rows via `navigationDestination(for:
/// VMDomain.ID.self)`. Takes the store and an identifier, not a `VMDomain`
/// value: `domain` below re-resolves from `store.state` on every render, so a
/// background poll — or an action fired from this very screen — reaches it
/// while it is open.
///
/// `VmDomain` reports a name and a state and nothing else (no vCPU count,
/// memory, disks, or uptime), so this screen is essentially its state plus its
/// buttons. That is the API's ceiling, not an unfinished
/// screen.
struct VMDetailView: View {
  let store: VMStore
  let domainID: VMDomain.ID

  /// `nil` when this VM is no longer in the latest snapshot — a VM can be
  /// deleted, or the whole VM manager can stop reporting, while someone is
  /// looking at it. A real state to render, not a defensive nicety.
  private var domain: VMDomain? {
    store.state.value?.domains?.first { $0.id == domainID }
  }

  var body: some View {
    if let domain {
      VMDetailContent(store: store, domain: domain)
    } else {
      VMNotFoundView()
    }
  }
}

/// The not-found state. A dedicated type, not inlined into
/// `VMDetailView.body`, so it previews without standing up a `VMStore` —
/// mirrors `ContainerDetailView`'s `ContainerNotFoundView`.
private struct VMNotFoundView: View {
  var body: some View {
    ContentUnavailableView(
      "VM Not Found",
      systemImage: "desktopcomputer",
      description: Text("This virtual machine is no longer available.")
    )
  }
}

/// The readout, once `VMDetailView` has resolved a non-nil domain.
private struct VMDetailContent: View {
  let store: VMStore
  let domain: VMDomain

  var body: some View {
    List {
      statusSection
      VMActionsSection(store: store, domain: domain)
    }
    .navigationTitle(domain.displayName)
    .navigationBarTitleDisplayMode(.large)
  }

  private var statusSection: some View {
    Section("Status") {
      LabeledContent("State") {
        HStack(spacing: 6) {
          StateDot(state: domain.state)
          Text(domain.state.displayName)
        }
      }
      .accessibilityIdentifier("vmDetail.state")
      // Only for a *named* VM. `displayName` falls back to the UUID half of
      // `id` when `name` is nil, so for an unnamed VM the navigation title is
      // already showing this exact string and a second copy of it would be
      // chrome, not information.
      if domain.name != nil {
        LabeledContent("Identifier", value: shortIdentifier)
      }
    }
  }

  /// The UUID half of Unraid's `<server-hash>:<uuid>` id. The hash is identical
  /// for every entity on the box, so showing it would be noise in a row whose
  /// only purpose is letting someone match this VM against `virsh` output.
  private var shortIdentifier: String {
    domain.id.split(separator: ":").last.map(String.init) ?? domain.id
  }
}

/// The Actions section: every action `VMActionCatalog` allows for this VM's
/// state, as full-width `List` rows.
///
/// A separate type rather than a computed property on `VMDetailContent` because
/// it owns the `@State` for its confirmation dialog — the same shape
/// `ContainerActionsSection` has. What it does *not* own, unlike that type, is
/// the rules: which actions apply, which confirm, and what each confirmation
/// says all come from `VMActionCatalog`, shared with `VMRow`, because rules
/// re-implemented per surface drift apart.
private struct VMActionsSection: View {
  let store: VMStore
  let domain: VMDomain

  @State private var pendingConfirmation: VMAction?

  private var isInFlight: Bool { store.inFlight.contains(domain.id) }

  var body: some View {
    Section("Actions") {
      ForEach(VMActionCatalog.actions(for: domain.state), id: \.self) { action in
        actionButton(action)
      }
    }
    .vmActionConfirmation(pending: $pendingConfirmation, vmNamed: domain.displayName, perform: perform)
  }

  private func perform(_ action: VMAction) {
    Task { await store.perform(action, on: domain) }
  }

  /// A `List` row that reads as a button.
  ///
  /// **Leading-aligned, not centered.** Centering via
  /// `.frame(maxWidth: .infinity)` looks like a full-width button on an
  /// iPhone and falls apart on an iPad, where the row is ~2000pt wide and the
  /// icon-and-text pair floats in the middle of an empty band with the separator
  /// starting under the text.
  /// Leading alignment matches every other row in the app, including
  /// `SettingsSheet`'s own Sign Out, and reads correctly at both sizes.
  ///
  /// `.foregroundStyle` is set explicitly rather than left to `role`'s automatic
  /// colouring: confirmed on-device that a `Label`'s SF Symbol stays the default
  /// accent tint under `role: .destructive` inside a `List` row even though the
  /// title text turns red, which would leave Stop with a red word next to a blue
  /// icon.
  private func actionButton(_ action: VMAction) -> some View {
    let isDestructive = VMActionCatalog.isDestructive(action)
    return Button(role: isDestructive ? .destructive : nil) {
      requestVMAction(action, vmNamed: domain.displayName, pending: $pendingConfirmation, perform: perform)
    } label: {
      Label(action.title, systemImage: VMActionCatalog.systemImage(for: action))
        .frame(maxWidth: .infinity, alignment: .leading)
        .foregroundStyle(isDestructive ? Color.red : Color.accentColor)
    }
    .disabled(isInFlight)
    // Stable per action rather than per position, so a UI test naming
    // `vmDetail.action.forceStop` can't be silently repointed by a reordering.
    .accessibilityIdentifier("vmDetail.action.\(action.identifier)")
  }
}

#Preview("Running") {
  NavigationStack {
    VMDetailContent(
      store: VMStore(repository: PreviewVMRepository()),
      domain: VMDomain(id: "hash:00000000-0000-4000-8000-000000000001", name: "Media Server", state: .running)
    )
  }
}

#Preview("Stopped") {
  NavigationStack {
    VMDetailContent(
      store: VMStore(repository: PreviewVMRepository()),
      domain: VMDomain(id: "hash:00000000-0000-4000-8000-000000000002", name: "Windows XP", state: .shutoff)
    )
  }
}

#Preview("Unnamed and crashed") {
  NavigationStack {
    VMDetailContent(
      store: VMStore(repository: PreviewVMRepository()),
      domain: VMDomain(id: "hash:00000000-0000-4000-8000-000000000001", name: nil, state: .crashed)
    )
  }
}

#Preview("Not found") {
  NavigationStack {
    VMNotFoundView()
  }
}

/// A `VMRepositoryProtocol` that never actually runs — the previews above only
/// read `store.inFlight` (always empty); none of them trigger an action.
/// `VMStore` requires a concrete repository at `init`, and Xcode previews can't
/// reach `LiveVMRepository` (no server, no keychain).
private struct PreviewVMRepository: VMRepositoryProtocol {
  func domains() async throws -> VMInventory { VMInventory(domains: []) }
  func start(id: String) async throws { fatalError("not used in previews") }
  func stop(id: String) async throws { fatalError("not used in previews") }
  func forceStop(id: String) async throws { fatalError("not used in previews") }
  func pause(id: String) async throws { fatalError("not used in previews") }
  func resume(id: String) async throws { fatalError("not used in previews") }
  func reboot(id: String) async throws { fatalError("not used in previews") }
  func reset(id: String) async throws { fatalError("not used in previews") }
}
