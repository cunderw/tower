import SwiftUI
import TowerCore

/// One row in the Docker container list. Built entirely from `DashboardRow`
/// so this doesn't become a third hand-rolled row — see
/// `DashboardRow`'s doc comment.
///
/// No `NavigationLink`/`Button` wrapper of its own — `DockerListView`
/// supplies that, wrapping each `ContainerRow` in
/// `NavigationLink(value: container.id)` inside its real `List`, which is
/// also why this passes `showsChevron: false` to `DashboardRow` below: the
/// `List` already draws its own disclosure indicator for a `NavigationLink`
/// row, and `DashboardRow`'s own copy would otherwise stack visibly on top
/// of it.
struct ContainerRow: View {
  let container: Container
  /// Whether `DockerStore.inFlight` currently holds this row's ID — a
  /// mutation is running against it right now. Swaps the update badge for a
  /// spinner and disables the row's own actions so a second tap can't race
  /// the first (belt-and-suspenders alongside `DockerStore.perform(_:on:)`'s
  /// own in-flight guard, which is the actual source of truth).
  let isInFlight: Bool
  let onAction: (ContainerAction) -> Void

  /// Stop and Restart interrupt something the user is actively running —
  /// both get a confirmation naming the container before `onAction` fires.
  /// Start has nothing to lose, so it skips this entirely.
  @State private var pendingConfirmation: ContainerAction?

  var body: some View {
    // `showsChevron: false` — this row is wrapped in a
    // `NavigationLink(value:)` inside `DockerListView`'s real `List`, which
    // already draws its own system disclosure indicator. `DashboardRow`'s
    // default chevron is for its List-less callers (`ServicesCard`,
    // `DiskListCard`); leaving it on here stacked visibly on top of the
    // system one.
    DashboardRow(showsChevron: false) {
      HStack(alignment: .top, spacing: 8) {
        StateDot(state: container.state)
          // Nudges the 8pt dot down to sit on the name's cap-height rather
          // than the top of the whole two-line block.
          .padding(.top, 6)
        VStack(alignment: .leading, spacing: 2) {
          Text(container.displayName)
            .font(.body)
          Text(subtitle)
            .font(.caption)
            .foregroundStyle(.secondary)
            // `StateDot` already contributes `state.displayName` to the
            // merged label below. `subtitle`'s visible text repeats that
            // word for non-running containers so a sighted user can read
            // the state without decoding colour (see `subtitle`'s doc
            // comment) — but merged verbatim that would make VoiceOver say
            // the state twice in a row ("Exited, code-server, Exited,
            // image…"). Overriding the label to just the image keeps the
            // spoken state to the one `StateDot` already provides.
            .accessibilityLabel(container.image)
        }
        Spacer()
        if isInFlight {
          // Decorative only: announcing "busy" mid-VoiceOver-swipe with no
          // further action to take would be noise, not information. Not
          // asserted by a UI test — `FakeDockerRepository`
          // resolves every action immediately, so there is no in-flight window
          // for a test to observe without adding an artificial delay to the
          // fake, which would trade a real assertion for a slower suite.
          ProgressView()
            .controlSize(.small)
            .accessibilityHidden(true)
        } else if container.isUpdateAvailable == true {
          updateBadge
        }
      }
    }
    // Without this, VoiceOver stops on `StateDot`, the name, the subtitle,
    // and the update badge as four separate elements per row — ~90 swipes
    // to traverse a 24-container list. Merging makes one swipe read the
    // whole row: state, name, image, then "Update" when present — the same
    // order the row lays out visually.
    .accessibilityElement(children: .combine)
    .accessibilityIdentifier("docker.row.\(container.id)")
    .swipeActions(edge: .leading, allowsFullSwipe: true) { leadingSwipeAction }
    .swipeActions(edge: .trailing, allowsFullSwipe: true) { trailingSwipeAction }
    .contextMenu { contextMenuActions }
    // `presenting: pendingConfirmation` hands the action straight into the
    // `actions:` closure as a non-optional `ContainerAction`, captured at
    // the moment SwiftUI builds this dialog's buttons — not re-read from
    // `@State` when a button is tapped. Reading `pendingConfirmation`
    // inside the button's own action closure races `isPresented`'s
    // dismissal setter, which nils `pendingConfirmation`
    // out: if SwiftUI drives `isPresented → false` before invoking the
    // button's action — undefined ordering, not guaranteed by the API —
    // the tap becomes a silent no-op with no mutation, no error, and no
    // haptic.
    .confirmationDialog(
      confirmationTitle,
      isPresented: isPresentingConfirmation,
      titleVisibility: .visible,
      presenting: pendingConfirmation
    ) { action in
      Button(confirmationTitle, role: .destructive) {
        onAction(action)
      }
      Button("Cancel", role: .cancel) {}
    }
  }

  // MARK: - Actions

  /// Whether Stop is the right action to offer — anything currently "up",
  /// running *or* paused, can legitimately be stopped; `!canStop` is the
  /// complement, "can be started." A plain "Start when not running" would leave
  /// `.paused` falling through to Start (Docker rejects `start` on an
  /// already-paused container, since it's still "up") and would offer no way
  /// to Stop one at all. `container.isRunning` alone isn't the right test
  /// across all three states; this is.
  private var canStop: Bool {
    container.state == .running || container.state == .paused
  }

  /// Start (green, no confirmation) when the container can genuinely be
  /// started; Stop (red, confirmed) for anything already up, running or
  /// paused.
  @ViewBuilder
  private var leadingSwipeAction: some View {
    Group {
      if canStop {
        Button {
          pendingConfirmation = .stop
        } label: {
          Label("Stop", systemImage: "stop.fill")
        }
        .tint(.red)
      } else {
        Button {
          onAction(.start)
        } label: {
          Label("Start", systemImage: "play.fill")
        }
        .tint(.green)
      }
    }
    // Belt-and-suspenders: `DockerStore.perform(_:on:)`'s own `inFlight`
    // guard is the real source of truth, this just keeps a busy row from
    // visually offering an action it would immediately drop.
    .disabled(isInFlight)
  }

  private var trailingSwipeAction: some View {
    Button {
      pendingConfirmation = .restart
    } label: {
      Label("Restart", systemImage: "arrow.clockwise")
    }
    .disabled(isInFlight)
  }

  /// Every applicable action plus Pause/Unpause, and an "Open Web UI" link
  /// when the server reported one.
  @ViewBuilder
  private var contextMenuActions: some View {
    Group {
      if canStop {
        Button(role: .destructive) {
          pendingConfirmation = .stop
        } label: {
          Label("Stop", systemImage: "stop.fill")
        }
      } else {
        Button {
          onAction(.start)
        } label: {
          Label("Start", systemImage: "play.fill")
        }
      }

      Button(role: .destructive) {
        pendingConfirmation = .restart
      } label: {
        Label("Restart", systemImage: "arrow.clockwise")
      }

      if container.state == .paused {
        Button {
          onAction(.unpause)
        } label: {
          Label("Resume", systemImage: "play.fill")
        }
      } else if container.isRunning {
        Button {
          onAction(.pause)
        } label: {
          Label("Pause", systemImage: "pause.fill")
        }
      }
    }
    .disabled(isInFlight)

    // Always enabled, even mid-action — opening the Web UI doesn't touch
    // the container, so there's no race for `isInFlight` to guard against.
    if let webUiURL = container.webUiURL {
      Link(destination: webUiURL) {
        Label("Open Web UI", systemImage: "safari")
      }
    }
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

  /// Just the image for a running container — the common case, exactly
  /// mirroring `DiskListCard`'s healthy disk (no extra status text). For any
  /// non-running state, the state name is prefixed so it reads in text, not
  /// only through `StateDot`'s colour and accessibility label — the same
  /// "device · statusText" pattern `DiskListCard` uses for an unhealthy disk,
  /// applied here to a container that isn't running.
  private var subtitle: String {
    guard !container.isRunning else { return container.image }
    return "\(container.state.displayName) · \(container.image)"
  }

  /// A `Text` in a `.capsule` background, `.caption2`.
  /// Only ever shown for `isUpdateAvailable == true` — `nil` and `false`
  /// both render nothing, since only `true` is a claim this app can make.
  private var updateBadge: some View {
    Text("Update")
      .font(.caption2)
      .fontWeight(.semibold)
      .padding(.horizontal, 8)
      .padding(.vertical, 3)
      .background(Capsule().fill(Color.accentColor.opacity(0.15)))
      .foregroundStyle(Color.accentColor)
      .accessibilityIdentifier("docker.row.\(container.id).updateBadge")
  }
}

#Preview {
  ZStack {
    Color(.systemGroupedBackground).ignoresSafeArea()
    VStack(spacing: 0) {
      ContainerRow(container: .previewFixture(id: "1", name: "code-server", state: .running), isInFlight: false) { _ in }
      Divider()
      ContainerRow(
        container: .previewFixture(id: "2", name: "webtop", state: .running, isUpdateAvailable: true),
        isInFlight: false
      ) { _ in }
      Divider()
      ContainerRow(container: .previewFixture(id: "3", name: "freshrss", state: .exited), isInFlight: false) { _ in }
      Divider()
      ContainerRow(container: .previewFixture(id: "4", name: "syncthing", state: .paused), isInFlight: false) { _ in }
      Divider()
      ContainerRow(container: .previewFixture(id: "5", name: "sonarr", state: .running), isInFlight: true) { _ in }
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
      ContainerRow(container: .previewFixture(id: "1", name: "code-server", state: .running), isInFlight: false) { _ in }
      Divider()
      ContainerRow(
        container: .previewFixture(id: "2", name: "webtop", state: .exited, isUpdateAvailable: true),
        isInFlight: false
      ) { _ in }
    }
    .padding()
  }
  .environment(\.dynamicTypeSize, .accessibility5)
}

extension Container {
  fileprivate static func previewFixture(
    id: String, name: String, state: ContainerState, isUpdateAvailable: Bool? = nil
  ) -> Container {
    Container(
      id: id, names: ["/\(name)"], image: "linuxserver/\(name):latest", state: state,
      status: state == .running ? "Up 2 hours" : "Exited (0) 3 hours ago", autoStart: true,
      isUpdateAvailable: isUpdateAvailable, isOrphaned: false, webUiURL: nil, iconURL: nil,
      projectURL: nil, supportURL: nil, registryURL: nil, templatePath: nil, networkMode: nil,
      ports: []
    )
  }
}
