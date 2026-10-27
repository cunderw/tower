import Observation
import SwiftUI
import TowerCore

/// The user's appearance choice, persisted across launches.
///
/// **`UserDefaults`, never the keychain.** A theme is a preference, not a
/// secret; nothing about it needs the keychain.
///
/// The suite is injectable so `ThemePreferenceTests` can use a scratch one rather
/// than mutating the simulator's real defaults — a test that wrote to
/// `.standard` would leak into every later test run on that device and into the
/// UI tests' idea of what the app looks like.
@MainActor
@Observable
final class ThemePreference {
  /// Reads and writes through on every change, so the value survives a launch
  /// without anyone having to remember to save it.
  var theme: AppTheme {
    didSet {
      guard theme != oldValue else { return }
      defaults.set(theme.rawValue, forKey: Self.key)
    }
  }

  static let key = "tower.appTheme"

  private let defaults: UserDefaults

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    // `AppTheme(storedValue:)` rather than a force-unwrap or `?? .system` here:
    // the stored string can be anything (an older build's value, a newer build's
    // case), and `.system` is the only fallback that can't be wrong.
    theme = AppTheme(storedValue: defaults.string(forKey: Self.key))
  }
}

extension AppTheme {
  /// `nil` for `.system`, which is how SwiftUI spells "follow the device".
  ///
  /// The mapping lives here, in the app layer, because `ColorScheme` is SwiftUI
  /// and `TowerCore` imports Foundation only — the same split
  /// `UsageLevel+Color.swift` and `StateDot`'s colour extensions use.
  var colorScheme: ColorScheme? {
    switch self {
    case .system: nil
    case .light: .light
    case .dark: .dark
    }
  }
}
