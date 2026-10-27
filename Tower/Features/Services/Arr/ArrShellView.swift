import SwiftUI
import TowerCore
import TowerData

/// The five sections every *arr opens into.
///
/// `CaseIterable` order is display order, and it is LunaSea's order.
enum ArrShellSection: String, CaseIterable, Identifiable, Hashable {
  case library, queue, calendar, history, more

  var id: String { rawValue }

  var title: String {
    switch self {
    case .library: "Library"
    case .queue: "Queue"
    case .calendar: "Calendar"
    case .history: "History"
    case .more: "More"
    }
  }

  var systemImage: String {
    switch self {
    case .library: "square.stack"
    case .queue: "arrow.down.circle"
    case .calendar: "calendar"
    case .history: "clock.arrow.circlepath"
    case .more: "ellipsis.circle"
    }
  }
}

/// The per-instance shell: one segmented control over five sections, with the
/// Library section supplied by whichever service this is.
///
/// **Generic over the library, not over the service.** Queue, calendar,
/// history, and More are the same screens for every *arr — that is the whole
/// point of `ArrClientCore` — so they are built here from the shared surface.
/// Only the library differs, so only the library is injected, and Lidarr
/// passes its own.
///
/// **Sections are lazy.** A section's content is only built once it has been
/// visited, so opening a Radarr doesn't fire five requests at a service that
/// may be on the other end of a VPN. Once visited, a section's state survives
/// switching away and back — which is why the visited set is tracked rather
/// than rebuilding on every selection change.
struct ArrShellView<Library: View>: View {
  let instance: ServiceInstance
  /// The shared surface this instance's sections are built on — the seam, not
  /// `ArrClientCore` itself, so demo and fake repositories can answer it.
  let arr: any ArrPickerSource
  /// Opens a media item from a history row, when this service's library can
  /// show one. `nil` leaves history rows as plain rows rather than links that
  /// go nowhere.
  var openMedia: ((Int) -> Void)?
  /// Lets a queue row open the download client actually fetching it. A row
  /// stays plain when this is `nil` or when `link(for:)` finds no client for
  /// it, as with the UI-test fakes and any stack without a download client.
  var downloadClients: DownloadClientNavigator?
  @ViewBuilder let library: () -> Library

  @State private var section: ArrShellSection = .library
  /// Built on first visit and kept afterwards, so switching away and back
  /// doesn't refetch — and so an unvisited section has no store at all.
  @State private var queueStore: ArrQueueStore?
  @State private var calendarStore: ArrCalendarStore?
  @State private var historyStore: ArrHistoryStore?
  @State private var moreStore: ArrMoreStore?
  /// Sections the user has opened. Everything not in here has never been built,
  /// and so has never fetched anything.
  @State private var visited: Set<ArrShellSection> = [.library]

  var body: some View {
    VStack(spacing: 0) {
      Picker("Section", selection: $section) {
        ForEach(ArrShellSection.allCases) { section in
          // Icons, not words: five text segments do not fit an iPhone, and the
          // accessibility label carries the name for VoiceOver either way.
          Label(section.title, systemImage: section.systemImage)
            .labelStyle(.iconOnly)
            .accessibilityLabel(section.title)
            .tag(section)
        }
      }
      .pickerStyle(.segmented)
      .padding(.horizontal)
      .padding(.bottom, 8)
      // The shell's marker lives on the control, not on the enclosing stack:
      // an identifier set on a container **overrides every child's**, so a
      // `VStack` carrying `arr.shell` renamed the library rows and the section
      // placeholders underneath it (confirmed from a real accessibility dump —
      // the same propagation trap as `ContentUnavailableView`).
      .accessibilityIdentifier("arr.shell")

      content
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    .navigationTitle(instance.name)
    .navigationBarTitleDisplayMode(.inline)
    .onChange(of: section) { _, newValue in visited.insert(newValue) }
  }

  private func calendarStoreIfNeeded() -> ArrCalendarStore {
    if let calendarStore { return calendarStore }
    let store = ArrCalendarStore(source: arr)
    Task { @MainActor in calendarStore = store }
    return store
  }

  private func moreStoreIfNeeded() -> ArrMoreStore {
    if let moreStore { return moreStore }
    let store = ArrMoreStore(source: arr)
    Task { @MainActor in moreStore = store }
    return store
  }

  private func historyStoreIfNeeded() -> ArrHistoryStore {
    if let historyStore { return historyStore }
    let store = ArrHistoryStore(source: arr)
    Task { @MainActor in historyStore = store }
    return store
  }

  /// Creates the queue store the first time the section is opened.
  private func queueStoreIfNeeded() -> ArrQueueStore {
    if let queueStore { return queueStore }
    let store = ArrQueueStore(source: arr)
    // Assigning during a body evaluation is safe here because it happens once,
    // on the render that first shows the section, and the value is derived
    // rather than a response to user input.
    Task { @MainActor in queueStore = store }
    return store
  }

  @ViewBuilder
  private var content: some View {
    switch section {
    case .library:
      library()
    case .queue:
      ArrQueueView(
        store: queueStoreIfNeeded(), isVisible: section == .queue,
        downloadClients: downloadClients)
    case .calendar:
      ArrCalendarView(store: calendarStoreIfNeeded())
    case .history:
      ArrHistoryView(store: historyStoreIfNeeded(), openMedia: openMedia)
    case .more:
      ArrMoreView(store: moreStoreIfNeeded())
    }
  }
}
