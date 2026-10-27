import Testing
import TowerCore

@testable import Tower

/// The recovery text a media service's screen shows, which must not send the
/// user to Unraid's settings for a key that lives in the service.
@Suite
struct AppErrorServiceRecoveryTests {
  @Test func aRejectedServiceCredentialPointsAtTheService() throws {
    let suggestion = try #require(AppError.unauthorized.serviceRecoverySuggestion)
    #expect(!suggestion.contains("Unraid"))
    #expect(!suggestion.contains("Management Access"))
    #expect(suggestion == AppError.serviceUnauthorizedRecovery)
  }

  @Test func unraidsOwnScreensStillPointAtManagementAccess() throws {
    let suggestion = try #require(AppError.unauthorized.recoverySuggestion)
    #expect(suggestion.contains("Unraid"))
    #expect(suggestion.contains("Management Access"))
  }

  @Test func aRefusedServiceCertificateDoesNotBlameUnraid() throws {
    let suggestion = try #require(AppError.insecureConnection.serviceRecoverySuggestion)
    #expect(!suggestion.contains("Unraid"))
    #expect(suggestion == AppError.serviceInsecureConnectionRecovery)
  }

  @Test func unraidsOwnScreensStillNameUnraidForARefusedCertificate() throws {
    let suggestion = try #require(AppError.insecureConnection.recoverySuggestion)
    #expect(suggestion.contains("Unraid"))
  }

  @Test(arguments: [
    AppError.serverUnreachable, .offline, .localNetworkDenied, .actionRefused("no"), .cancelled,
    .unknown("detail"),
  ])
  func everyOtherErrorPassesThroughUnchanged(_ error: AppError) {
    #expect(error.serviceRecoverySuggestion == error.recoverySuggestion)
  }
}
