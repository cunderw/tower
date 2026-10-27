import Foundation
import Testing
import TowerCore
@testable import Tower

/// Each test gets its own `UserDefaults` suite. A test writing to `.standard`
/// would leak into every later test on that simulator — and into what the UI
/// tests think the app looks like.
@MainActor
struct ThemePreferenceTests {
  private func scratchDefaults(_ name: String = UUID().uuidString) -> UserDefaults {
    let defaults = UserDefaults(suiteName: "tower.tests.\(name)")!
    defaults.removePersistentDomain(forName: "tower.tests.\(name)")
    return defaults
  }

  @Test func defaultsToFollowingTheSystem() {
    // Not light, not dark: "looks like a system app" is the stated goal, and the
    // system's own setting is the only choice that can't be wrong for a user who
    // hasn't asked for anything.
    #expect(ThemePreference(defaults: scratchDefaults()).theme == .system)
  }

  @Test func persistsAChoiceAcrossInstances() {
    // The choice survives a relaunch, expressed the way it can actually be
    // tested: a second `ThemePreference` over the same store is what a
    // relaunch looks like.
    let defaults = scratchDefaults()
    let first = ThemePreference(defaults: defaults)

    first.theme = .dark

    #expect(ThemePreference(defaults: defaults).theme == .dark)
  }

  @Test func restoringSystemIsItselfPersisted() {
    // The path a naive "only write non-default values" implementation breaks:
    // going back to System after choosing Dark has to stick, not reload as Dark.
    let defaults = scratchDefaults()
    let preference = ThemePreference(defaults: defaults)
    preference.theme = .dark

    preference.theme = .system

    #expect(ThemePreference(defaults: defaults).theme == .system)
  }

  @Test func anUnreadableStoredValueFallsBackToSystem() {
    // The stored string can be anything — an older build's value, a newer build's
    // case, or something else entirely. `nil` would mean the app has no
    // appearance rather than the system's.
    let defaults = scratchDefaults()
    defaults.set("solarized", forKey: ThemePreference.key)

    #expect(ThemePreference(defaults: defaults).theme == .system)
  }

  @Test func aStoredValueOfTheWrongTypeAlsoFallsBackToSystem() {
    let defaults = scratchDefaults()
    defaults.set(42, forKey: ThemePreference.key)

    #expect(ThemePreference(defaults: defaults).theme == .system)
  }

  @Test func writingTheSameThemeTwiceIsANoOp() {
    // Guards the `didSet` early return: without it, every render that re-assigns
    // the current value would hit `UserDefaults`.
    let defaults = scratchDefaults()
    let preference = ThemePreference(defaults: defaults)

    preference.theme = .light
    preference.theme = .light

    #expect(ThemePreference(defaults: defaults).theme == .light)
  }

  // MARK: - The SwiftUI mapping

  @Test func systemMapsToNoColorSchemeOverride() {
    // `nil` is how SwiftUI spells "follow the device" — a non-nil value here would
    // pin the app to one appearance forever.
    #expect(AppTheme.system.colorScheme == nil)
    #expect(AppTheme.light.colorScheme == .light)
    #expect(AppTheme.dark.colorScheme == .dark)
  }

  @Test func everyThemeHasCopyAndARoundTrippableRawValue() {
    for theme in AppTheme.allCases {
      #expect(!theme.displayName.isEmpty)
      #expect(AppTheme(storedValue: theme.rawValue) == theme)
    }
  }
}
