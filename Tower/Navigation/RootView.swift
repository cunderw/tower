import SwiftUI
import TowerCore

/// The app shell: an adaptive five-tab `TabView`.
///
/// `.tabViewStyle(.sidebarAdaptable)` is the reason this is its own type —
/// one declaration renders as a tab bar on iPhone and as a sidebar + split
/// view on iPad.
struct RootView: View {
  let server: Server
  let environment: AppEnvironment
  /// Owned by `TowerApp`, which also applies it to the whole scene — passed down
  /// so the Settings sheet can offer the picker without owning the preference.
  let theme: ThemePreference
  let onSignOut: () -> Void

  /// Regular width only — the sidebar's per-instance Services section exists
  /// there and has nowhere to live in a tab bar.
  @Environment(\.horizontalSizeClass) private var horizontalSizeClass
  /// Whether this `TabView` can show a sidebar, as its tabs' content reads it.
  /// Regular width is not enough on its own: an unfolded iPhone Duo is regular
  /// width with no sidebar, and lays the per-instance tabs out in its side tab
  /// bar. Reported up from the tabs by `TabSidebarAvailabilityReader`, because
  /// the environment value reads `false` anywhere above the `TabView`.
  @State private var isTabSidebarAvailable = TabSidebarAvailabilityReader.initialValue

  @State private var selection: TowerDestination = .tab(.dashboard)
  /// The Docker and Services lists' selections, **owned here** because the
  /// cross-link needs something above both tabs to be able to set them.
  @State private var dockerSelection: Container.ID?
  @State private var servicesSelection: UUID?
  @State private var isShowingSettings = false
  @State private var isShowingNotifications = false
  // Held here, not built inline in the `Tab` body below: constructing a
  // `DashboardStore` inline would rebuild it (and re-fire `.task { await
  // store.load() }`) on every `RootView` render, not just on tab switches.
  @State private var dashboardStore: DashboardStore
  // Same reasoning as `dashboardStore` above, one per tab that needs one.
  @State private var dockerStore: DockerStore
  @State private var vmStore: VMStore
  @State private var shareStore: ShareStore
  /// One store for the whole shell, not one per tab: the bell's badge appears on
  /// every tab and has to show the same number on all of them, and the sheet has
  /// to open onto whatever the badge was counting.
  @State private var notificationStore: NotificationStore
  /// Held here rather than built inside `SettingsSheet` so its loaded list
  /// survives the sheet being dismissed and reopened.
  @State private var logFileStore: LogFileStore
  /// The Services hub's store. One for the whole shell, like the notification
  /// store: the iPad sidebar lists the same instances the hub tab does, and two
  /// stores would check every service twice and disagree about the results.
  @State private var servicesStore: ServicesStore

  init(
    server: Server,
    environment: AppEnvironment,
    theme: ThemePreference,
    onSignOut: @escaping () -> Void
  ) {
    self.server = server
    self.environment = environment
    self.theme = theme
    self.onSignOut = onSignOut
    _dashboardStore = State(initialValue: DashboardStore(repository: environment.makeRepository(server)))
    _dockerStore = State(initialValue: DockerStore(repository: environment.makeDockerRepository(server)))
    _vmStore = State(initialValue: VMStore(repository: environment.makeVMRepository(server)))
    _shareStore = State(initialValue: ShareStore(repository: environment.makeShareRepository(server)))
    _notificationStore = State(
      initialValue: NotificationStore(repository: environment.makeNotificationRepository(server))
    )
    _logFileStore = State(initialValue: LogFileStore(repository: environment.makeLogRepository(server)))
    _servicesStore = State(
      initialValue: ServicesStore(
        directory: environment.serviceDirectory,
        checker: environment.serviceStatusChecker,
        // The same Docker repository the Docker tab uses — the container list
        // is already being fetched for this server, so the assist costs one
        // more query only when the add sheet is actually open.
        assist: DockerServiceAssist(
          serverURL: server.url, repository: environment.makeDockerRepository(server)),
        // So an edit or a delete drops that instance's retained store.
        serviceStores: environment.serviceStores
      )
    )
  }

  // MARK: - Cross-links between a service and its container

  /// The container list as last loaded. Empty when the Docker tab has never
  /// been opened, which is why every link below is optional by construction:
  /// no data, no link, and no screen changes.
  private var containers: [Container] { dockerStore.state.value ?? [] }

  private func serviceRunning(in container: Container) -> ServiceInstance? {
    ServiceContainerLink.instance(
      for: container, in: servicesStore.instances, serverURL: server.url)
  }

  private func container(running instance: ServiceInstance) -> Container? {
    ServiceContainerLink.container(for: instance, in: containers, serverURL: server.url)
  }

  /// The sidebar's per-instance Services section. In a tab bar these would be
  /// nine more items competing with the five real tabs, which is what the hub
  /// tab exists to prevent, so they appear only where a sidebar can.
  private var showsServiceTabs: Bool {
    horizontalSizeClass != .compact && isTabSidebarAvailable
  }

  /// Jumps to the Services tab with `instance` open.
  ///
  /// With the sidebar's Services section the jump is direct; without it, it is
  /// the hub tab plus the hub's selection, which `ListDetailScaffold` turns
  /// into a push or a split-view detail. Never `.service` without the section:
  /// that would select a tab that does not exist.
  private func open(service instance: ServiceInstance) {
    servicesSelection = instance.id
    selection = showsServiceTabs ? .service(instance.id) : .tab(.services)
  }

  private func open(container: Container) {
    dockerSelection = container.id
    selection = .tab(.docker)
  }

  var body: some View {
    TabView(selection: $selection) {
      Tab(TowerTab.dashboard.title, systemImage: TowerTab.dashboard.systemImage, value: TowerDestination.tab(.dashboard)) {
        DashboardView(
          store: dashboardStore,
          onSelectTab: { selection = .tab($0) },
          isShowingSettings: $isShowingSettings,
          isShowingNotifications: $isShowingNotifications,
          unreadCount: notificationStore.overview.badgeCount,
          isSelected: selection == .tab(.dashboard)
        )
        .accessibilityIdentifier("tab.dashboard.content")
        .modifier(TabSidebarAvailabilityReader(isAvailable: $isTabSidebarAvailable))
      }
      Tab(TowerTab.docker.title, systemImage: TowerTab.docker.systemImage, value: TowerDestination.tab(.docker)) {
        DockerListView(
          store: dockerStore,
          isShowingSettings: $isShowingSettings,
          isShowingNotifications: $isShowingNotifications,
          unreadCount: notificationStore.overview.badgeCount,
          isSelected: selection == .tab(.docker),
          selection: $dockerSelection,
          linkedService: serviceRunning(in:),
          openService: open(service:)
        )
        .accessibilityIdentifier("tab.docker.content")
        .modifier(TabSidebarAvailabilityReader(isAvailable: $isTabSidebarAvailable))
      }
      Tab(TowerTab.vms.title, systemImage: TowerTab.vms.systemImage, value: TowerDestination.tab(.vms)) {
        VMListView(
          store: vmStore,
          isShowingSettings: $isShowingSettings,
          isShowingNotifications: $isShowingNotifications,
          unreadCount: notificationStore.overview.badgeCount,
          isSelected: selection == .tab(.vms)
        )
        .accessibilityIdentifier("tab.vms.content")
        .modifier(TabSidebarAvailabilityReader(isAvailable: $isTabSidebarAvailable))
      }
      Tab(TowerTab.shares.title, systemImage: TowerTab.shares.systemImage, value: TowerDestination.tab(.shares)) {
        ShareListView(
          store: shareStore,
          isShowingSettings: $isShowingSettings,
          isShowingNotifications: $isShowingNotifications,
          unreadCount: notificationStore.overview.badgeCount,
          isSelected: selection == .tab(.shares)
        )
        .accessibilityIdentifier("tab.shares.content")
        .modifier(TabSidebarAvailabilityReader(isAvailable: $isTabSidebarAvailable))
      }
      Tab(TowerTab.services.title, systemImage: TowerTab.services.systemImage, value: TowerDestination.tab(.services)) {
        ServicesHubView(
          store: servicesStore,
          makeRepository: environment.makeServiceRepository,
          serviceStores: environment.serviceStores,
          containerRunning: container(running:),
          openContainer: open(container:),
          ensureContainersLoaded: {
            // Only when it has never loaded — this must not blank the Docker
            // tab's list or fight its own polling.
            if dockerStore.state.value == nil { await dockerStore.load() }
          },
          isShowingSettings: $isShowingSettings,
          isShowingNotifications: $isShowingNotifications,
          unreadCount: notificationStore.overview.badgeCount,
          isSelected: selection == .tab(.services),
          selection: $servicesSelection
        )
        .accessibilityIdentifier("tab.services.content")
        .modifier(TabSidebarAvailabilityReader(isAvailable: $isTabSidebarAvailable))
      }
      // The iPad sidebar's Services section: every configured instance by name,
      // one tap from anywhere. See `showsServiceTabs` for where it appears.
      if showsServiceTabs {
        TabSection("Services") {
          ForEach(servicesStore.enabledInstances) { instance in
            Tab(
              instance.name,
              systemImage: instance.kind.systemImage,
              value: TowerDestination.service(instance.id)
            ) {
              NavigationStack {
                ArrServiceScreen(
                  instance: instance,
                  servicesStore: servicesStore,
                  makeRepository: environment.makeServiceRepository,
                  serviceStores: environment.serviceStores
                )
                  .modifier(
                    TowerToolbarModifier(
                      isShowingNotifications: $isShowingNotifications,
                      isShowingSettings: $isShowingSettings,
                      unreadCount: notificationStore.overview.badgeCount
                    )
                  )
              }
              .accessibilityIdentifier("tab.service.\(instance.id.uuidString).content")
              .modifier(TabSidebarAvailabilityReader(isAvailable: $isTabSidebarAvailable))
            }
          }
        }
      }
    }
    .tabViewStyle(.sidebarAdaptable)
    .accessibilityIdentifier("root.tabs")
    .sheet(isPresented: $isShowingSettings) {
      SettingsSheet(
        server: server,
        // Whatever the dashboard last read. Nil until its first load resolves, and
        // the System section omits itself rather than showing empty rows.
        systemInfo: dashboardStore.state.value?.array.system,
        theme: theme,
        logFileStore: logFileStore,
        servicesStore: servicesStore,
        onSignOut: handleSignOut
      )
    }
    .sheet(isPresented: $isShowingNotifications) {
      NotificationSheet(store: notificationStore, server: server)
    }
    // The badge has to be current whichever tab is showing, and the sheet may
    // never be opened at all — so the counts poll here, at the shell, rather than
    // inside the sheet. Cheap: `overview()` is two count objects, and a failure
    // leaves the last known badge alone (see `refreshOverview()`).
    .pollingRefresh(isActive: true) { await notificationStore.refreshOverview() }
    // The sidebar's Services section is built from this list, and the sidebar
    // exists whether or not the Services tab has ever been opened — so the
    // (local, keychain) read happens at the shell. The remote status checks
    // stay in the hub, where they follow tab selection.
    .task { servicesStore.reloadInstances() }
  }

  // UI glue only — the actual privacy-sensitive sequencing (dismiss and
  // hand off to `onSignOut` even when the store failed to clear) lives in
  // `performSignOut` below, where `SignOutTests` can reach it directly.
  private func handleSignOut() {
    performSignOut(environment: environment, dismiss: { isShowingSettings = false }, onSignOut: onSignOut)
  }
}

/// Reports `isTabViewSidebarAvailable` from inside a tab's content up to
/// `RootView`, which builds the `TabView` and so cannot read it itself.
///
/// The value, not `tabBarPlacement`: on iPad the placement flips between
/// `topBar` and `sidebar` as the person toggles the sidebar, and removing the
/// instance tabs on that toggle would drop a selected instance. Availability
/// stays `true` on iPad in both layouts, and is `false` on an iPhone, the
/// unfolded iPhone Duo included.
struct TabSidebarAvailabilityReader: ViewModifier {
  @Binding var isAvailable: Bool

  /// Before any tab has reported. `false` from iOS 27, so a device without a
  /// sidebar never draws the instance tabs for a frame; before iOS 27 the
  /// value cannot be read and regular width alone decides, as it always did.
  static var initialValue: Bool {
    if #available(iOS 27, *) { false } else { true }
  }

  func body(content: Content) -> some View {
    if #available(iOS 27, *) {
      content.modifier(Reader(isAvailable: $isAvailable))
    } else {
      content
    }
  }

  @available(iOS 27, *)
  private struct Reader: ViewModifier {
    @Binding var isAvailable: Bool
    @Environment(\.isTabViewSidebarAvailable) private var isTabViewSidebarAvailable

    func body(content: Content) -> some View {
      content.onChange(of: isTabViewSidebarAvailable, initial: true) {
        isAvailable = isTabViewSidebarAvailable
      }
    }
  }
}

/// Adds the badged notification bell and the settings gear to a tab's own
/// navigation bar. Every tab carries both.
///
/// Must be applied *inside* that tab's own `NavigationStack` construction
/// (every tab's view does this, `.modifier(TowerToolbarModifier(...))` right
/// next to `.navigationTitle`), not chained onto the already-built view from
/// `RootView`. Confirmed empirically against the real simulator: a `.toolbar`
/// applied externally — whether via a `ViewModifier`, chained raw onto
/// `DashboardView(...)`, or chained onto the whole `TabView` — is silently
/// dropped in this `TabView`/`Tab` configuration and produces zero toolbar
/// items in the accessibility tree. Only `Binding`s and a plain `Int?` cross
/// the boundary here, not an opaque toolbar type, so the tab views stay
/// concretely nameable (no generic parameter) and future tabs, tests, and
/// previews aren't forced to genericize just to host these.
struct TowerToolbarModifier: ViewModifier {
  @Binding var isShowingNotifications: Bool
  @Binding var isShowingSettings: Bool
  /// `nil` when nothing is unread — see `NotificationOverview.badgeCount`. A
  /// badge reading "0" draws the eye to say nothing happened.
  let unreadCount: Int?

  func body(content: Content) -> some View {
    content.toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        Button {
          isShowingNotifications = true
        } label: {
          // The bell's glyph carries the "there is something unread" signal for
          // anyone who can't read a small badge, and the accessibility label
          // carries the count in words. Colour and a numeral are never the only
          // signals.
          Label(
            "Notifications",
            systemImage: unreadCount == nil ? "bell" : "bell.badge"
          )
        }
        .badge(unreadCount ?? 0)
        .accessibilityLabel(notificationsAccessibilityLabel)
        .accessibilityIdentifier("toolbar.notifications")
      }
      ToolbarItem(placement: .topBarTrailing) {
        Button("Settings", systemImage: "gearshape") { isShowingSettings = true }
          .accessibilityIdentifier("toolbar.settings")
      }
    }
  }

  /// "Notifications" with the count spoken as a word rather than left to the
  /// badge, which VoiceOver reads inconsistently across placements.
  private var notificationsAccessibilityLabel: String {
    guard let unreadCount else { return "Notifications" }
    return unreadCount == 1 ? "Notifications, 1 unread" : "Notifications, \(unreadCount) unread"
  }
}

/// The sign-out glue, extracted out of `RootView.handleSignOut` as a plain
/// function (no `View`, no `@State`) so `SignOutTests` can drive it directly
/// instead of only being reachable from a button closure.
///
/// This is the actual privacy guarantee: even when `environment.signOut()`
/// swallowed a failing keychain clear, `dismiss` and `onSignOut` must still
/// run unconditionally — that's what returns the app to the connect screen.
/// A test against this function catches a real future regression (someone
/// wrapping the call in a `do`/`catch`, or adding a guard that skips
/// `onSignOut()` on failure) that a test only asserting on `AppEnvironment
/// .signOut()`'s current non-throwing signature could not.
@MainActor
func performSignOut(environment: AppEnvironment, dismiss: () -> Void, onSignOut: () -> Void) {
  environment.signOut()
  dismiss()
  onSignOut()
}
