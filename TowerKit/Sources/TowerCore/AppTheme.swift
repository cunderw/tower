import Foundation

/// The user's appearance preference.
///
/// Lives in `TowerCore` rather than the app target despite being a UI concept,
/// for the same reason `UsageLevel` does: it is a plain value with no SwiftUI in
/// it, and `TowerCore` imports `Foundation` only. The mapping to a
/// `ColorScheme?` is in the app layer (`ThemePreference.swift`), which is
/// also what would keep this usable from a widget extension without dragging
/// SwiftUI into the model layer.
public enum AppTheme: String, CaseIterable, Hashable, Sendable {
  /// Follow the system setting — the default, and what "looks like a system app"
  /// means when the user hasn't asked for anything else.
  case system
  case light
  case dark

  public var displayName: String {
    switch self {
    case .system: "System"
    case .light: "Light"
    case .dark: "Dark"
    }
  }

  /// Restores a stored preference, falling back to `.system` for anything
  /// unreadable.
  ///
  /// The fallback matters: this value comes out of `UserDefaults`, which can hold
  /// a string written by an older or newer build, and a `nil` here would mean the
  /// app has *no* appearance rather than the system's. `.system` is the only
  /// answer that can't be wrong.
  public init(storedValue: String?) {
    self = storedValue.flatMap(AppTheme.init(rawValue:)) ?? .system
  }
}
