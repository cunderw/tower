import Testing
@testable import TowerCore

@Test func unauthorizedSuggestsCheckingTheAPIKey() {
  #expect(AppError.unauthorized.recoverySuggestion?.contains("API key") == true)
}

@Test func localNetworkDeniedPointsAtSettings() {
  let error = AppError.localNetworkDenied
  #expect(error.recoverySuggestion?.contains("Settings") == true)
  #expect(error.message.isEmpty == false)
}

@Test func offlineSuggestsConnectingToANetworkRatherThanASettingsToggle() {
  // .offline and .localNetworkDenied must read as different problems: this
  // one has no Settings toggle to point at, since there's no network at all.
  let error = AppError.offline
  #expect(error.recoverySuggestion?.contains("Wi-Fi") == true)
  #expect(error.recoverySuggestion?.contains("Settings") == false)
  #expect(error.message.isEmpty == false)
}

@Test func invalidServerURLDescribesTheShapeRatherThanNamingAnAddress() throws {
  // A sample address here would show one person's LAN address to every user.
  // The assertion is on the *absence* of any dotted quad rather than on the
  // wording: rephrasing the sentence is fine, putting somebody's server into
  // it is not, and only the second one should be able to fail this test.
  let suggestion = try #require(AppError.invalidServerURL.recoverySuggestion)
  #expect(suggestion.contains("http://"))
  #expect(suggestion.contains("https://"))
  #expect(
    suggestion.contains(/\d+\.\d+\.\d+\.\d+/) == false,
    "the suggestion names a specific address: \(suggestion)"
  )
}

@Test func insecureConnectionSuggestsTryingHTTPInsteadOfHTTPS() {
  let error = AppError.insecureConnection
  #expect(error.recoverySuggestion?.contains("self-signed") == true)
  #expect(error.recoverySuggestion?.contains("http://") == true)
  #expect(error.message.isEmpty == false)
}

@Test func graphQLErrorJoinsAllMessages() {
  let error = AppError.graphQL(["bad field", "missing arg"])
  #expect(error.message.contains("bad field"))
  #expect(error.message.contains("missing arg"))
}

@Test func actionRefusedSurfacesTheCallersMessageVerbatim() {
  // Unlike every case above, the detail *is* the user-facing sentence — the
  // repository knows which action was refused and `AppError` does not, so
  // wrapping or prefixing it here would produce "The server sent something
  // Tower couldn't read"-style noise around an already-complete message.
  let error = AppError.actionRefused("Unraid didn't force stop this VM.")
  #expect(error.message == "Unraid didn't force stop this VM.")
}

@Test func actionRefusedNamesBothCausesWithoutNamingOneFeature() {
  // The two real causes of a `false` from Unraid's `Boolean!` mutations. The
  // suggestion must not say "VM": `AppError` is shared by every feature, and
  // a case that names one would read wrong the first time something else
  // refuses an action.
  let suggestion = AppError.actionRefused("anything").recoverySuggestion
  #expect(suggestion?.contains("already be in that state") == true)
  #expect(suggestion?.contains("permission") == true)
  #expect(suggestion?.contains("VM") == false)
}

@Test func serviceUnavailableNamesTheServiceAndHowToRecover() {
  let error = AppError.serviceUnavailable("Docker")
  #expect(error.message == "Docker isn't available on this server.")
  #expect(error.recoverySuggestion == "It may be disabled or stopped. Start it in Unraid, then try again.")
}

@Test func actionRefusedIsNotConflatedWithUnknown() {
  // The distinction the case exists for: a refusal is a specific, explainable
  // outcome, and collapsing it into `.unknown` would have put
  // `String(describing:)` noise in front of the user.
  #expect(AppError.actionRefused("x") != AppError.unknown("x"))
  #expect(AppError.unknown("x").recoverySuggestion == nil)
  #expect(AppError.actionRefused("x").recoverySuggestion != nil)
}
