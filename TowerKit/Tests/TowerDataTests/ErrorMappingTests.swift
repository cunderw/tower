import Apollo
import Foundation
import Testing
@testable import TowerData
import TowerCore

// MARK: - HTTP status code mapping

@Test func unauthorizedHTTPStatusMapsToUnauthorized() {
  #expect(AppError.from(httpStatusCode: 401) == .unauthorized)
  #expect(AppError.from(httpStatusCode: 403) == .unauthorized)
}

@Test func serverErrorStatusRangeMapsToServerUnreachable() {
  // The whole 5xx range should map, not just the boundary values, since a
  // regression that only special-cased 500 or 599 would still pass a
  // boundary-only test.
  #expect(AppError.from(httpStatusCode: 500) == .serverUnreachable)
  #expect(AppError.from(httpStatusCode: 502) == .serverUnreachable)
  #expect(AppError.from(httpStatusCode: 599) == .serverUnreachable)
}

@Test func unrecognizedStatusCodeMapsToUnknownWithTheCodeInTheMessage() {
  // Asserts the exact case AND payload, not just "some error came back":
  // a regression that maps unknown codes to .serverUnreachable, or drops
  // the code from the message, must fail this.
  #expect(AppError.from(httpStatusCode: 418) == .unknown("HTTP 418"))
  #expect(AppError.from(httpStatusCode: 200) == .unknown("HTTP 200"))
}

// MARK: - Transport error mapping

@Test func cannotConnectMapsToServerUnreachable() {
  let urlError = URLError(.cannotConnectToHost)
  #expect(AppError.from(transport: urlError) == .serverUnreachable)
}

@Test func cannotFindHostAndTimeoutAlsoMapToServerUnreachable() {
  #expect(AppError.from(transport: URLError(.cannotFindHost)) == .serverUnreachable)
  #expect(AppError.from(transport: URLError(.timedOut)) == .serverUnreachable)
  #expect(AppError.from(transport: URLError(.dnsLookupFailed)) == .serverUnreachable)
}

@Test func localNetworkDenialIsDistinctFromUnreachable() {
  // iOS surfaces a denied local-network prompt as NSURLErrorNetworkConnectionLost.
  // This must not read as a generic failure, because the fix is a Settings
  // toggle, not "check the address."
  let denied = URLError(.networkConnectionLost)
  let error = AppError.from(transport: denied)
  #expect(error == .localNetworkDenied)
  // Explicitly guard against collapsing into the neighboring case: these
  // two errors carry different user-facing recovery instructions, so a
  // regression that merges them would be user-visible.
  #expect(error != .serverUnreachable)
}

@Test func notConnectedToInternetMapsToOfflineNotLocalNetworkDenied() {
  // NSURLErrorNotConnectedToInternet (-1009) means there is no network
  // interface at all — airplane mode, Wi-Fi off. That is a different problem
  // from a denied local-network prompt (.networkConnectionLost): telling an
  // offline user to "allow local network access in Settings ▸ Tower" points
  // them at a toggle that isn't their problem.
  let error = AppError.from(transport: URLError(.notConnectedToInternet))
  #expect(error == .offline)
  // The whole point of the .offline case is that it is distinguishable from
  // .localNetworkDenied — assert that directly, not just that this one case
  // is correct in isolation.
  #expect(error != .localNetworkDenied)
  #expect(AppError.offline != AppError.localNetworkDenied)
}

@Test func badURLAndUnsupportedURLMapToInvalidServerURL() {
  #expect(AppError.from(transport: URLError(.badURL)) == .invalidServerURL)
  #expect(AppError.from(transport: URLError(.unsupportedURL)) == .invalidServerURL)
}

@Test func certificateAndTLSFailuresMapToInsecureConnection() {
  // A self-signed certificate is a completely normal Unraid deployment.
  // Without this mapping these fall into `.unknown`, which has no recovery
  // text — asserting the exact case (not `!= nil`) is the point.
  #expect(AppError.from(transport: URLError(.secureConnectionFailed)) == .insecureConnection)
  #expect(AppError.from(transport: URLError(.serverCertificateUntrusted)) == .insecureConnection)
  // Guard against collapsing into the generic bucket: this case exists
  // specifically because "unknown" gives the user no actionable advice.
  #expect(AppError.from(transport: URLError(.secureConnectionFailed)) != .unknown(URLError(.secureConnectionFailed).localizedDescription))
}

@Test func unmappedURLErrorCodeFallsBackToTheUnknownCaseOnly() {
  // Deliberately picks a URLError code the mapping does not special-case.
  // Pattern-matching the case (rather than comparing the associated
  // localized string) keeps this test from being brittle across OS/locale
  // string changes, while still failing if a regression routes this to
  // any of the specific, actionable cases.
  let error = AppError.from(transport: URLError(.userAuthenticationRequired))
  guard case .unknown = error else {
    Issue.record("expected .unknown, got \(error)")
    return
  }
}

@Test func nonURLErrorTransportFailureMapsToUnknownWithItsDescription() {
  struct SomeOtherTransportFailure: Error {}
  let error = SomeOtherTransportFailure()
  #expect(AppError.from(transport: error) == .unknown(String(describing: error)))
}

// MARK: - GraphQL error mapping

@Test func graphQLMessagesArePreservedAsTheGraphQLCase() {
  let messages = ["Cannot query field \"x\"", "Variable \"$id\" is never used"]
  let error = AppError.from(graphQLErrorMessages: messages)
  #expect(error == .graphQL(messages))
}

@Test func graphQLMessagesRemainReadableThroughTheMessageProperty() {
  let error = AppError.from(graphQLErrorMessages: ["Cannot query field \"x\""])
  #expect(error.message.contains("Cannot query field"))
}

// MARK: - GraphQL error mapping via `extensions.code` (Apollo `GraphQLError`)
//
// These exercise `AppError.from(graphQLErrors:)`, the overload that inspects
// `extensions["code"]` instead of only `message` — Unraid answers a bad API
// key with HTTP 200 and a GraphQL error carrying
// `extensions.code == "UNAUTHENTICATED"`, never HTTP 401/403, so the
// httpStatusCode mapping above never sees it.

/// Builds an Apollo `GraphQLError` with the given message and, optionally,
/// an `extensions.code` entry — mirroring the wire shape Unraid actually
/// sends: `{"message": "...", "extensions": {"code": "..."}}`.
private func graphQLError(message: String, code: String? = nil) -> GraphQLError {
  var object: [String: any Sendable & Hashable] = ["message": message]
  if let code {
    object["extensions"] = ["code": code]
  }
  return GraphQLError(object)
}

@Test func unauthenticatedExtensionCodeMapsToUnauthorizedExactCase() {
  let error = AppError.from(graphQLErrors: [
    graphQLError(message: "API key validation failed", code: "UNAUTHENTICATED")
  ])
  // Exact-case assertion is the point: without this overload, this error
  // lands in `.graphQL(["API key validation failed"])`, whose
  // `recoverySuggestion` is `nil`, so a wrong API key gets no recovery text.
  #expect(error == .unauthorized)
}

@Test func forbiddenExtensionCodeAlsoMapsToUnauthorizedExactCase() {
  let error = AppError.from(graphQLErrors: [
    graphQLError(message: "Not permitted", code: "FORBIDDEN")
  ])
  #expect(error == .unauthorized)
}

@Test func differentExtensionCodeStillMapsToGraphQLWithMessagesPreservedInOrder() {
  // A code the app doesn't special-case (or any non-auth code) must not be
  // swallowed into `.unauthorized` — it should still reach the user as the
  // server's actual message(s), in order.
  let error = AppError.from(graphQLErrors: [
    graphQLError(message: "Cannot query field \"x\"", code: "GRAPHQL_VALIDATION_FAILED"),
    graphQLError(message: "Variable \"$id\" is never used", code: "GRAPHQL_VALIDATION_FAILED"),
  ])
  #expect(error == .graphQL(["Cannot query field \"x\"", "Variable \"$id\" is never used"]))
}

@Test func noExtensionsAtAllStillMapsToGraphQLWithMessagesPreservedInOrder() {
  // The plain wire shape most GraphQL servers send: no `extensions` key at
  // all. Must not crash on the missing key, and must not misclassify as
  // unauthorized just because `extensions` is absent.
  let error = AppError.from(graphQLErrors: [
    graphQLError(message: "Cannot query field \"x\""),
    graphQLError(message: "second error"),
  ])
  #expect(error == .graphQL(["Cannot query field \"x\"", "second error"]))
}

@Test func mixedBatchWithOneUnauthenticatedErrorAmongOthersMapsToUnauthorized() {
  // Decision: an UNAUTHENTICATED/FORBIDDEN entry anywhere in the batch wins
  // over the rest, because at root the whole response is an authentication
  // problem the user must fix before anything else the server said is
  // actionable. See the comment on `from(graphQLErrors:)` for the rationale.
  let error = AppError.from(graphQLErrors: [
    graphQLError(message: "Some unrelated validation error", code: "GRAPHQL_VALIDATION_FAILED"),
    graphQLError(message: "API key validation failed", code: "UNAUTHENTICATED"),
  ])
  #expect(error == .unauthorized)
}
