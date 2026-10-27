/// How alarming a measurement is. Views map this to a semantic colour; the
/// thresholds themselves live here so they can be tested without SwiftUI and
/// so every screen agrees on what "warm" means.
public enum UsageLevel: Equatable, Sendable {
  case normal
  case warning
  case critical
  /// No reading available — render as unavailable, never as healthy.
  case unknown

  public static func forFraction(_ fraction: Double) -> UsageLevel {
    switch fraction {
    case ..<0.85: .normal
    case ..<0.95: .warning
    default: .critical
    }
  }

  /// Celsius. 45 °C is where Unraid's own default disk warning sits; 55 °C
  /// is its default critical threshold.
  public static func forTemperature(_ celsius: Int?) -> UsageLevel {
    guard let celsius else { return .unknown }
    switch celsius {
    case ..<45: return .normal
    case ..<55: return .warning
    default: return .critical
    }
  }
}
