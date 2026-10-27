import TowerCore

extension AppError {
  /// What to do about a rejected credential on a media service's screen.
  /// Shared with the add-service form's test result, so the two say the same
  /// thing.
  static let serviceUnauthorizedRecovery = "Check the API key or password for this service."

  /// What to do when a media service's https:// address fails on its
  /// certificate.
  static let serviceInsecureConnectionRecovery =
    "This service may use a self-signed certificate. Try its http:// address instead of https://."

  /// `recoverySuggestion`, for the screen of a media service rather than of
  /// the Unraid server.
  ///
  /// `recoverySuggestion` sends a rejected key to Unraid's Management Access
  /// settings and puts a refused certificate down to Unraid, which is right
  /// only for the Unraid server itself. A service's key, password and
  /// certificate belong to that service, so every service screen reads this
  /// instead. Every other case passes through unchanged.
  var serviceRecoverySuggestion: String? {
    switch self {
    case .unauthorized: Self.serviceUnauthorizedRecovery
    case .insecureConnection: Self.serviceInsecureConnectionRecovery
    default: recoverySuggestion
    }
  }
}
