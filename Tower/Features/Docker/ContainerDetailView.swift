import SwiftUI
import TowerCore
import TowerData

/// Pushed from `DockerListView`'s `ContainerRow` via `navigationDestination(for:
/// Container.ID.self)`. Takes the store and an identifier, not a
/// container value: `container` below re-resolves from `store.state` on
/// every render, so a background poll *or* a mutation fired from this very
/// screen's own Actions section reaches it while it's open.
///
/// This matters more here than it did for `DiskDetailView`: a container
/// pushed by value would still read `EXITED` after the user pressed Start
/// on this very screen, because the mutation updates `DockerStore`, not a
/// local snapshot the view captured at push time. Sharing the same store
/// instance the list uses is also what makes the in-flight guard work
/// across screens — `DockerStore.perform(_:on:)`'s `inFlight` check is keyed
/// by container ID regardless of which screen (row or detail) fired it, so
/// a second tap on either surface while the first is in flight is a no-op.
struct ContainerDetailView: View {
  let store: DockerStore
  let containerID: Container.ID
  /// The service configured against this container, if any.
  var linkedService: (Container) -> ServiceInstance? = { _ in nil }
  /// Opens that service's screen.
  var openService: (ServiceInstance) -> Void = { _ in }

  /// `nil` when this container is no longer in the latest snapshot —
  /// containers genuinely get removed (or renamed away, in Docker's model,
  /// replaced) while a user is looking at them. A real state to render
  /// (`ContentUnavailableView` below), not a defensive nicety.
  private var container: Container? {
    store.state.value?.first { $0.id == containerID }
  }

  var body: some View {
    if let container {
      ContainerDetailContent(
        store: store, container: container, linkedService: linkedService(container),
        openService: openService)
    } else {
      ContainerNotFoundView()
    }
  }
}

/// The not-found state: rendered when `ContainerDetailView`'s
/// lookup comes back nil. A dedicated type, not inlined into
/// `ContainerDetailView.body`, so it can be previewed without standing up a
/// `DockerStore` — mirrors `DiskDetailView.DiskNotFoundView`.
private struct ContainerNotFoundView: View {
  var body: some View {
    ContentUnavailableView(
      "Container Not Found",
      systemImage: "shippingbox",
      description: Text("This container is no longer available.")
    )
  }
}

/// The actual container readout, once `ContainerDetailView` has resolved a
/// non-nil container. Seven sections, each omitting itself when it has
/// nothing to show — Status and Actions never do (every container has a
/// state, a status string, and at least one applicable action), Logs is
/// always there, Config always shows at least `image`, but Service, Ports
/// and Links are genuinely empty for some containers (no service configured
/// against it, no ports or no Web UI, and neither project/support/registry
/// is guaranteed either) and must disappear rather than render an empty
/// header.
///
/// `DockerContainer.mounts` is deliberately not rendered here — it's a
/// `[JSON!]` scalar `TowerAPI` doesn't type. A blob
/// dumped from an untyped scalar would be worse than omitting it.
private struct ContainerDetailContent: View {
  let store: DockerStore
  let container: Container
  /// The service configured against this container, resolved by the caller.
  var linkedService: ServiceInstance?
  var openService: (ServiceInstance) -> Void = { _ in }

  var body: some View {
    List {
      statusSection
      ContainerActionsSection(store: store, container: container)
      serviceSection
      logsSection
      configSection
      portsSection
      linksSection
    }
    .navigationTitle(container.displayName)
    .navigationBarTitleDisplayMode(.large)
  }

  // MARK: - Logs

  /// Pushes `ContainerLogsRoute` — a titled `Section` like every
  /// other one on this screen, just with a single `NavigationLink` row
  /// instead of `LabeledContent` rows, matching how `ContainerActionsSection`
  /// mixes full-width buttons into the same `List`.
  private var logsSection: some View {
    Section("Logs") {
      NavigationLink(value: ContainerLogsRoute(containerID: container.id, containerName: container.displayName)) {
        Label("View Logs", systemImage: "doc.plaintext")
      }
      .accessibilityIdentifier("containerDetail.viewLogsButton")
    }
  }

  // MARK: - Status

  private var statusSection: some View {
    Section("Status") {
      LabeledContent("State") {
        HStack(spacing: 6) {
          StateDot(state: container.state)
          Text(container.state.displayName)
        }
      }
      LabeledContent("Status", value: container.status)
      LabeledContent("Autostart", value: container.autoStart ? "On" : "Off")
      // `isUpdateAvailable` is `Bool?` — nil means "not determined", which
      // must not render as either "up to date" or "update available".
      // Only `true` is a claim this screen can make; matches
      // `ContainerRow.updateBadge`'s identical nil/false-both-render-nothing
      // rule.
      if container.isUpdateAvailable == true {
        Label("Update Available", systemImage: "arrow.triangle.2.circlepath")
          .foregroundStyle(Color.accentColor)
          .accessibilityIdentifier("containerDetail.updateNotice")
      }
    }
  }

  // MARK: - Config

  @ViewBuilder
  private var configSection: some View {
    Section("Config") {
      LabeledContent("Image", value: container.image)
      if let networkMode = container.networkMode {
        LabeledContent("Network Mode", value: networkMode)
      }
      if let templatePath = container.templatePath {
        LabeledContent("Template Path", value: templatePath)
      }
    }
  }

  // MARK: - Ports

  @ViewBuilder
  private var portsSection: some View {
    // Many containers publish no ports at all — omit the whole
    // section rather than a header over zero rows, the same no-empty-chrome
    // rule `DiskDetailView`'s Activity section applies.
    if !container.ports.isEmpty {
      Section("Ports") {
        // `ContainerPort` is `Hashable`/`Equatable` but not `Identifiable`,
        // and two distinct ports can legitimately share every visible field
        // (same private port, different IP) — `.offset` from `enumerated()`
        // is a stable-enough `id` for a list that's re-derived fresh from
        // `container.ports` on every render, matching `DiskListCard`'s
        // identical `Array(disks.enumerated())` pattern.
        ForEach(Array(container.ports.enumerated()), id: \.offset) { _, port in
          // `ContainerPort.summary` already formats exactly what this row
          // needs — `"13378 → 80/TCP"`, or just `"80/TCP"` with the
          // public side omitted when Docker only exposes the port
          // internally — so this reuses it rather than re-deriving the same
          // string a second time.
          Text(port.summary)
        }
      }
    }
  }

  // MARK: - The service this container runs

  /// Present only when a configured service matches this container.
  ///
  /// A `Button` rather than a `NavigationLink`: the destination lives in a
  /// different tab, so this is a jump rather than a push, and rendering it as a
  /// push would promise a back button that cannot exist.
  @ViewBuilder
  private var serviceSection: some View {
    if let linkedService {
      Section("Service") {
        Button {
          openService(linkedService)
        } label: {
          HStack {
            Label(linkedService.name, systemImage: linkedService.kind.systemImage)
            Spacer()
            Image(systemName: "arrow.up.forward.app")
              .foregroundStyle(.secondary)
              .accessibilityHidden(true)
          }
        }
        .accessibilityIdentifier("container.service")
      }
    }
  }

  // MARK: - Links

  @ViewBuilder
  private var linksSection: some View {
    if hasAnyLink {
      Section("Links") {
        if let webUiURL = container.webUiURL {
          Link("Web UI", destination: webUiURL)
        }
        if let projectURL = container.projectURL {
          Link("Project", destination: projectURL)
        }
        if let supportURL = container.supportURL {
          Link("Support", destination: supportURL)
        }
        if let registryURL = container.registryURL {
          Link("Registry", destination: registryURL)
        }
      }
    }
  }

  private var hasAnyLink: Bool {
    container.webUiURL != nil || container.projectURL != nil
      || container.supportURL != nil || container.registryURL != nil
  }
}

/// The Actions section: the same action set `ContainerRow`'s context menu
/// offers, as full-width `List` rows instead of menu items. A separate type
/// (not a computed property on `ContainerDetailContent`) because it owns its
/// own `@State` for the Stop/Restart confirmation dialog — the exact same
/// shape `ContainerRow` already carries for its swipe/context-menu actions.
/// Kept as its own small, self-contained copy rather than factored out
/// alongside `ContainerRow`'s: the two surfaces render the set differently
/// enough (menu items vs. full-width buttons) that sharing the dialog
/// plumbing would mean threading a label-building closure through a shared
/// type for one field (the title string) in common. If a third container
/// action surface shows up (unlikely — VMs have their own action set),
/// that's the point to extract, matching the threshold `DashboardRow`'s own
/// doc comment documents for row layout.
private struct ContainerActionsSection: View {
  let store: DockerStore
  let container: Container

  /// Stop and Restart interrupt something the user is actively running —
  /// both get a confirmation naming the container before the mutation
  /// fires. Start/Pause/Resume have nothing to lose, so they skip this.
  @State private var pendingConfirmation: ContainerAction?

  private var isInFlight: Bool { store.inFlight.contains(container.id) }

  /// Anything currently "up" — running or paused — can legitimately be
  /// stopped; Docker rejects `start` on a container that's already up.
  /// Mirrors `ContainerRow.canStop` exactly.
  private var canStop: Bool {
    container.state == .running || container.state == .paused
  }

  var body: some View {
    Section("Actions") {
      if canStop {
        actionButton(
          "Stop", systemImage: "stop.fill", role: .destructive, identifier: "containerDetail.stopButton"
        ) {
          pendingConfirmation = .stop
        }
      } else {
        actionButton("Start", systemImage: "play.fill", identifier: "containerDetail.startButton") {
          perform(.start)
        }
      }

      actionButton(
        "Restart", systemImage: "arrow.clockwise", role: .destructive,
        identifier: "containerDetail.restartButton"
      ) {
        pendingConfirmation = .restart
      }

      // Remember: a paused container must not be offered Start (Docker
      // rejects it) — `canStop` above already routes paused containers to
      // Stop, and this offers Resume (unpause) rather than Pause for them.
      if container.state == .paused {
        actionButton("Resume", systemImage: "play.fill", identifier: "containerDetail.resumeButton") {
          perform(.unpause)
        }
      } else if container.isRunning {
        actionButton("Pause", systemImage: "pause.fill", identifier: "containerDetail.pauseButton") {
          perform(.pause)
        }
      }
    }
    // `presenting: pendingConfirmation` hands the action into the button
    // closure as a non-optional value captured when the dialog was built —
    // not re-read from `@State` at tap time, which races `isPresented`'s
    // dismissal setter (see `ContainerRow`).
    .confirmationDialog(
      confirmationTitle,
      isPresented: isPresentingConfirmation,
      titleVisibility: .visible,
      presenting: pendingConfirmation
    ) { action in
      Button(confirmationTitle, role: .destructive) {
        perform(action)
      }
      Button("Cancel", role: .cancel) {}
    }
  }

  private func perform(_ action: ContainerAction) {
    Task { await store.perform(action, on: container) }
  }

  /// A `List` row that reads as a button, disabled whenever this container has a
  /// mutation in flight — sourced from the same `DockerStore.inFlight` the list
  /// row reads, so a row and its detail screen can't both fire at once.
  ///
  /// **Leading-aligned.** Centered reads as a full-width button on an iPhone
  /// and falls apart on an iPad: the row is ~2000pt wide and
  /// the icon-and-text pair floats mid-row with the separator starting under the
  /// text. Matches `VMActionsSection` and `SettingsSheet`'s Sign Out.
  ///
  /// `.foregroundStyle` is set explicitly rather than left to `role`'s own
  /// automatic colouring: confirmed on-device that a `Label`'s SF Symbol
  /// icon stays the default accent tint under `role: .destructive` inside a
  /// `List` row even though the title text does pick up red, leaving Stop/
  /// Restart with a red word next to a blue icon. Setting it once here on
  /// the whole label keeps icon and text the same semantic colour.
  private func actionButton(
    _ title: String, systemImage: String, role: ButtonRole? = nil, identifier: String,
    action: @escaping () -> Void
  ) -> some View {
    Button(role: role, action: action) {
      Label(title, systemImage: systemImage)
        .frame(maxWidth: .infinity, alignment: .leading)
        .foregroundStyle(role == .destructive ? Color.red : Color.accentColor)
    }
    .disabled(isInFlight)
    .accessibilityIdentifier(identifier)
  }

  private var confirmationTitle: String {
    switch pendingConfirmation {
    case .stop: "Stop \(container.displayName)?"
    case .restart: "Restart \(container.displayName)?"
    case .start, .pause, .unpause, nil: ""
    }
  }

  private var isPresentingConfirmation: Binding<Bool> {
    Binding(
      get: { pendingConfirmation != nil },
      set: { isPresented in if !isPresented { pendingConfirmation = nil } }
    )
  }
}

#Preview("Running, with ports and links") {
  NavigationStack {
    ContainerDetailContent(
      store: DockerStore(repository: PreviewDockerRepository()),
      container: .previewFixture(
        id: "1", name: "code-server", image: "linuxserver/code-server:latest",
        state: .running, status: "Up 11 hours", autoStart: true, isUpdateAvailable: true,
        webUiURL: URL(string: "http://192.0.2.10:8443"),
        projectURL: URL(string: "https://github.com/linuxserver/docker-code-server"),
        supportURL: URL(string: "https://forums.unraid.net/topic/code-server"),
        registryURL: URL(string: "https://hub.docker.com/r/linuxserver/code-server"),
        templatePath: "/boot/config/plugins/dockerMan/templates-user/code-server.xml",
        networkMode: "bridge",
        ports: [
          ContainerPort(ip: "0.0.0.0", privatePort: 8_443, publicPort: 8_443, type: "TCP"),
        ]
      )
    )
  }
}

#Preview("Exited, no ports, no links") {
  NavigationStack {
    ContainerDetailContent(
      store: DockerStore(repository: PreviewDockerRepository()),
      container: .previewFixture(
        id: "2", name: "freshrss", image: "linuxserver/freshrss:latest",
        state: .exited, status: "Exited (0) 3 hours ago", autoStart: false,
        isUpdateAvailable: nil, webUiURL: nil, projectURL: nil, supportURL: nil,
        registryURL: nil, templatePath: nil, networkMode: "bridge", ports: []
      )
    )
  }
}

#Preview("Paused — Start must not be offered") {
  NavigationStack {
    ContainerDetailContent(
      store: DockerStore(repository: PreviewDockerRepository()),
      container: .previewFixture(
        id: "3", name: "syncthing", image: "linuxserver/syncthing:latest",
        state: .paused, status: "Paused", autoStart: true, isUpdateAvailable: false,
        webUiURL: nil, projectURL: nil, supportURL: nil, registryURL: nil,
        templatePath: nil, networkMode: nil, ports: []
      )
    )
  }
}

#Preview("Accessibility Size (AX5)") {
  NavigationStack {
    ContainerDetailContent(
      store: DockerStore(repository: PreviewDockerRepository()),
      container: .previewFixture(
        id: "1", name: "code-server", image: "linuxserver/code-server:latest",
        state: .running, status: "Up 11 hours", autoStart: true, isUpdateAvailable: true,
        webUiURL: URL(string: "http://192.0.2.10:8443"), projectURL: nil, supportURL: nil,
        registryURL: nil, templatePath: nil, networkMode: "bridge",
        ports: [ContainerPort(ip: "0.0.0.0", privatePort: 8_443, publicPort: 8_443, type: "TCP")]
      )
    )
  }
  .environment(\.dynamicTypeSize, .accessibility5)
}

/// The state a container that's been removed (or renamed away) renders —
/// the not-found branch. Previewable on its own since it needs no
/// store.
#Preview("Not found") {
  NavigationStack {
    ContainerNotFoundView()
  }
}

extension Container {
  /// Takes every field the detail screen renders directly — not
  /// `ContainerRow`'s own `fileprivate` `previewFixture`, which derives
  /// fewer fields because the row it backs doesn't render them. Mirrors
  /// `DiskDetailView`'s identical reasoning for keeping its own fixture
  /// separate from `DiskListCard`'s.
  fileprivate static func previewFixture(
    id: String, name: String, image: String, state: ContainerState, status: String,
    autoStart: Bool, isUpdateAvailable: Bool?, webUiURL: URL?, projectURL: URL?,
    supportURL: URL?, registryURL: URL?, templatePath: String?, networkMode: String?,
    ports: [ContainerPort]
  ) -> Container {
    Container(
      id: id, names: ["/\(name)"], image: image, state: state, status: status,
      autoStart: autoStart, isUpdateAvailable: isUpdateAvailable, isOrphaned: false,
      webUiURL: webUiURL, iconURL: nil, projectURL: projectURL, supportURL: supportURL,
      registryURL: registryURL, templatePath: templatePath, networkMode: networkMode, ports: ports
    )
  }
}

/// A `DockerRepositoryProtocol` that never actually runs — every `#Preview`
/// above only reads `store.inFlight` (always empty) through
/// `ContainerActionsSection`; none of them trigger a real action, so this
/// only needs to satisfy the protocol, not behave usefully. `DockerStore`
/// requires a concrete repository at `init`, and Xcode previews can't reach
/// `TowerData`'s `LiveDockerRepository` (no server, no keychain).
private struct PreviewDockerRepository: DockerRepositoryProtocol {
  func containers() async throws -> [Container] { [] }
  func start(id: String) async throws -> ContainerStateUpdate { fatalError("not used in previews") }
  func stop(id: String) async throws -> ContainerStateUpdate { fatalError("not used in previews") }
  func restart(id: String) async throws -> ContainerStateUpdate { fatalError("not used in previews") }
  func pause(id: String) async throws -> ContainerStateUpdate { fatalError("not used in previews") }
  func unpause(id: String) async throws -> ContainerStateUpdate { fatalError("not used in previews") }
  func logs(id: String, tail: Int?, since: String?) async throws -> ContainerLogs { fatalError("not used in previews") }
}
