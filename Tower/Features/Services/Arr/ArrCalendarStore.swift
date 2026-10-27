import Foundation
import Observation
import TowerCore
import TowerData

/// The shared calendar: what is coming, grouped by day.
///
/// **A list, not a month grid** — the right call for a phone: the question is
/// "what's next", and a grid answers "what happened in March" at the cost of
/// most of the screen.
@MainActor
@Observable
final class ArrCalendarStore: RefreshableStore {
  var state: Loadable<[ArrCalendarEntry]> = .idle
  let loads = LoadTracker()

  private let source: any ArrPickerSource
  private let now: @Sendable () -> Date

  init(source: any ArrPickerSource, now: @escaping @Sendable () -> Date = { Date() }) {
    self.source = source
    self.now = now
  }

  /// A week back and four weeks forward. Backwards as well because "did last
  /// night's episode land" is the same question as "what's next", and a
  /// forward-only calendar can't answer it.
  private var window: (start: Date, end: Date) {
    let today = now()
    return (
      today.addingTimeInterval(-7 * 86_400),
      today.addingTimeInterval(28 * 86_400)
    )
  }

  func load() async {
    let window = window
    await load { [self] in try await source.calendar(start: window.start, end: window.end) }
  }

  func refresh() async {
    guard state.value != nil else { return await load() }
    let window = window
    await mutate { [self] in try await source.calendar(start: window.start, end: window.end) }
  }

  var isEmpty: Bool {
    guard let entries = state.value else { return false }
    return entries.isEmpty
  }

  /// Entries grouped by calendar day, oldest first.
  ///
  /// Entries with no date at all are dropped rather than bucketed under
  /// "today": a release with no date is not happening today, and putting it
  /// there is a claim the API never made.
  var days: [ArrCalendarDay] {
    let calendar = Calendar.current
    let grouped = Dictionary(grouping: (state.value ?? []).compactMap { entry -> (Date, ArrCalendarEntry)? in
      guard let date = entry.date else { return nil }
      return (calendar.startOfDay(for: date), entry)
    }) { $0.0 }

    return grouped
      .map { day, pairs in
        ArrCalendarDay(
          date: day,
          entries: pairs.map(\.1).sorted { ($0.date ?? .distantPast) < ($1.date ?? .distantPast) })
      }
      .sorted { $0.date < $1.date }
  }
}

struct ArrCalendarDay: Identifiable, Equatable {
  let date: Date
  let entries: [ArrCalendarEntry]

  var id: Date { date }

  func isToday(_ now: Date = Date()) -> Bool {
    Calendar.current.isDate(date, inSameDayAs: now)
  }
}

/// The shared history feed.
@MainActor
@Observable
final class ArrHistoryStore: RefreshableStore {
  var state: Loadable<ArrHistoryPage> = .idle
  let loads = LoadTracker()

  private let source: any ArrPickerSource

  init(source: any ArrPickerSource) {
    self.source = source
  }

  var records: [ArrHistoryRecord] { state.value?.records ?? [] }

  var isEmpty: Bool {
    guard let page = state.value else { return false }
    return page.records.isEmpty
  }

  func load() async {
    await load { [self] in try await source.history(page: 1) }
  }

  func refresh() async {
    guard state.value != nil else { return await load() }
    await mutate { [self] in try await source.history(page: 1) }
  }
}
