import SwiftUI
import TowerCore
import TowerData

/// The Settings sheet: which server you're attached to, what it's running, how
/// Tower should look, and a way to leave.
///
/// The dashboard's System card carries the glanceable readings (CPU and memory
/// load, core counts, OS and uptime). This sheet repeats the OS, core counts and
/// uptime beside the CPU model, which isn't glanceable and would cost dashboard
/// space, and the syslog viewer.
struct SettingsSheet: View {
  let server: Server
  /// The system readout the dashboard already loaded, passed in rather than
  /// re-queried: `DashboardStore` fetches it every 30 seconds anyway, and a second
  /// query here would ask the server for something it just answered.
  ///
  /// `nil` while the dashboard hasn't loaded yet (or failed to) — the section
  /// omits itself rather than rendering a screenful of em-dashes.
  let systemInfo: SystemInfo?
  let theme: ThemePreference
  /// Built by `RootView` so this sheet doesn't have to know what backs it — the
  /// same reason `DockerStore.makeLogsStore(containerID:)` exists.
  let logFileStore: LogFileStore
  /// The hub's store, so Add Service is reachable from here as well as from the
  /// Services tab — the one shared store, so a service added here shows up on
  /// the hub without a second read.
  let servicesStore: ServicesStore
  let onSignOut: () -> Void

  @Environment(\.dismiss) private var dismiss
  @State private var isShowingSignOutConfirmation = false
  @State private var addServiceStore: ServiceFormStore?

  var body: some View {
    NavigationStack {
      List {
        Section("Server") {
          LabeledContent("Name", value: server.name)
          LabeledContent("Address", value: server.url.absoluteString)
          LabeledContent("API Key", value: maskedAPIKey)
        }

        systemSection

        Section("Services") {
          NavigationLink {
            ServicesManagementView(store: servicesStore)
          } label: {
            Label("Manage Services", systemImage: "square.stack.3d.up")
          }
          .accessibilityIdentifier("settings.manageServices")

          Button("Add Service", systemImage: "plus") {
            addServiceStore = servicesStore.makeServiceFormStore()
          }
          .accessibilityIdentifier("settings.addService")
        }

        Section("Logs") {
          NavigationLink {
            LogFileListView(store: logFileStore)
          } label: {
            Label("Server Logs", systemImage: "doc.plaintext")
          }
          .accessibilityIdentifier("settings.logs")
        }

        Section("Appearance") {
          Picker("Theme", selection: Binding(get: { theme.theme }, set: { theme.theme = $0 })) {
            ForEach(AppTheme.allCases, id: \.self) { option in
              Text(option.displayName).tag(option)
            }
          }
          .accessibilityIdentifier("settings.theme")
        }

        Section {
          Button("Sign Out", role: .destructive) {
            isShowingSignOutConfirmation = true
          }
          .accessibilityIdentifier("settings.signOut")
        }

        Section("About") {
          LabeledContent("Name", value: appName)
          LabeledContent("Version", value: appVersion)
        }
      }
      .navigationTitle("Settings")
      .sheet(item: $addServiceStore) { addStore in
        ServiceFormSheet(store: addStore) { saved in
          Task { await servicesStore.adopt(saved) }
        }
      }
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button("Done") { dismiss() }
            .accessibilityIdentifier("settings.done")
        }
      }
      .confirmationDialog(
        "Sign Out?",
        isPresented: $isShowingSignOutConfirmation,
        titleVisibility: .visible
      ) {
        Button("Sign Out", role: .destructive) { onSignOut() }
          // The dialog's action surfaces in the UI-test tree as two nested
          // buttons sharing this identifier and one frame, and does with or
          // without `.combine`. A UI test reaches it with `.firstMatch`.
          // `.combine` stays because what VoiceOver reads here has not been
          // checked, and removing it changes nothing in the UI-test tree.
          .accessibilityElement(children: .combine)
          .accessibilityIdentifier("settings.confirmSignOut")
        Button("Cancel", role: .cancel) {}
      } message: {
        Text("Tower will forget this server's address and API key.")
      }
    }
  }

  /// Omitted entirely when the dashboard hasn't produced a reading yet, and each
  /// row omitted when its own field is nil. Nothing here renders a plausible
  /// substitute for a missing value.
  @ViewBuilder
  private var systemSection: some View {
    if let systemInfo, hasAnySystemDetail(systemInfo) {
      Section("System") {
        if let os = operatingSystem(systemInfo) {
          LabeledContent("OS", value: os)
        }
        if let cpuBrand = systemInfo.cpuBrand {
          LabeledContent("CPU", value: cpuBrand)
        }
        if let cores = cpuTopology(systemInfo) {
          LabeledContent("Cores", value: cores)
        }
        if let uptime = uptime(systemInfo) {
          LabeledContent("Uptime", value: uptime)
            .accessibilityIdentifier("settings.uptime")
        }
      }
    }
  }

  private func hasAnySystemDetail(_ info: SystemInfo) -> Bool {
    operatingSystem(info) != nil || info.cpuBrand != nil || cpuTopology(info) != nil
      || uptime(info) != nil
  }

  /// "Unraid OS 7.3.0", or whichever half the server actually reported.
  private func operatingSystem(_ info: SystemInfo) -> String? {
    switch (info.distro, info.release) {
    case let (.some(distro), .some(release)): "\(distro) \(release)"
    case let (.some(distro), .none): distro
    case let (.none, .some(release)): release
    case (.none, .none): nil
    }
  }

  /// "8 cores · 16 threads", degrading to whichever number came back.
  private func cpuTopology(_ info: SystemInfo) -> String? {
    switch (info.cpuCores, info.cpuThreads) {
    case let (.some(cores), .some(threads)): "\(cores) cores · \(threads) threads"
    case let (.some(cores), .none): "\(cores) cores"
    case let (.none, .some(threads)): "\(threads) threads"
    case (.none, .none): nil
    }
  }

  /// **`bootTimestamp` is a boot time, not an uptime** — `info.os.uptime` is
  /// misleadingly named in Unraid's schema, and rendering it raw would show a
  /// date where a duration belongs. `Formatters.uptime(since:)` is the one place
  /// that conversion happens; a timestamp that won't parse yields nil and the row
  /// disappears rather than showing "0m".
  private func uptime(_ info: SystemInfo) -> String? {
    // Parses first rather than calling `Formatters.uptime(sinceTimestamp:)`,
    // which returns the string "Unknown" for a value it can't read. That is right
    // for the dashboard, where the row is part of a fixed card; here every other
    // row omits itself when its field is absent, and one row reading "Unknown"
    // among them would look like a different kind of answer.
    info.bootTimestamp
      .flatMap(Formatters.parseTimestamp)
      .map { Formatters.uptime(since: $0) }
  }

  // Never the full key: a fixed run of bullets plus the last 4 characters
  // is enough to recognize which key is stored without a screenshot or a
  // shoulder-surf recovering something usable. Never logged, never handed
  // to an accessibility label beyond what's already shown on screen here.
  private var maskedAPIKey: String {
    "••••••••" + server.apiKey.suffix(4)
  }

  private var appName: String {
    (Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
      ?? (Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String)
      ?? "Tower"
  }

  private var appVersion: String {
    let shortVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
    return "\(shortVersion) (\(build))"
  }
}

#if DEBUG
#Preview("Everything reported") {
  SettingsSheet(
    server: Server(name: "Tower", url: URL(string: "http://192.0.2.10")!, apiKey: "abcd1234efgh5678"),
    systemInfo: SystemInfo(
      distro: "Unraid OS", release: "7.3.0", bootTimestamp: "2026-01-01T00:00:00Z",
      cpuBrand: "Example 8-Core CPU", cpuCores: 8, cpuThreads: 16,
      cpuPercent: 12, memoryPercent: 88, memoryUsedBytes: nil, memoryTotalBytes: nil
    ),
    theme: ThemePreference(defaults: .previewSuite),
    logFileStore: LogFileStore(repository: PreviewLogRepository()),
    servicesStore: ServicesStore(
      directory: ServiceDirectory.inMemory(), checker: StaticServiceStatusChecker()),
    onSignOut: {}
  )
}

/// The state before the dashboard has answered — the System section must be
/// absent, not a column of em-dashes.
#Preview("Nothing reported yet") {
  SettingsSheet(
    server: Server(name: "Tower", url: URL(string: "http://192.0.2.10")!, apiKey: "abcd1234efgh5678"),
    systemInfo: nil,
    theme: ThemePreference(defaults: .previewSuite),
    logFileStore: LogFileStore(repository: PreviewLogRepository()),
    servicesStore: ServicesStore(
      directory: ServiceDirectory.inMemory(), checker: StaticServiceStatusChecker()),
    onSignOut: {}
  )
}

/// Never runs — the previews above only render the row that would push the log
/// list, never the list itself.
private struct PreviewLogRepository: LogRepositoryProtocol {
  func logFiles() async throws -> [LogFile] { [] }
  func logFile(path: String, lines: Int?) async throws -> LogFileContents {
    LogFileContents(path: path, lines: [], totalLines: 0, startLine: nil)
  }
}

extension UserDefaults {
  /// A scratch suite so previews don't write a theme into the simulator's real
  /// defaults and change what every other preview and UI test sees.
  ///
  /// A computed property, not a `static let`: `UserDefaults` isn't `Sendable`, so
  /// a stored static is a concurrency error under strict checking. Each preview
  /// getting its own instance of the same suite is fine — `UserDefaults` is the
  /// shared store, not the object.
  fileprivate static var previewSuite: UserDefaults {
    UserDefaults(suiteName: "tower.previews") ?? .standard
  }
}
#endif
