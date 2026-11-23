import Foundation
import Testing
import TowerCore
import TowerData

// `LiveSystemRepository.setArrayState`, through `StubURLProtocol`. Issue #25.
//
// No test here, and nothing else in Tower's suites, sends `setState` to a
// real server: it starts or stops someone's array.

/// A repository whose `SetArrayState` answer is `json`, or never comes when
/// `json` is `nil`.
private func makeRepository(
  host: String, json: String?,
  timeout: TimeInterval = LiveSystemRepository.defaultArrayStateTimeout
) -> (LiveSystemRepository, URL) {
  let endpoint = URL(string: "http://\(host)/graphql")!
  if let json {
    StubURLProtocol.stub(url: endpoint, operationName: "SetArrayState", json: json)
  } else {
    StubURLProtocol.stubNoAnswer(url: endpoint, operationName: "SetArrayState")
  }
  let server = Server(name: "Stub", url: URL(string: "http://\(host)")!, apiKey: "test-key")
  let repository = LiveSystemRepository(
    provider: ApolloClientProvider(server: server, sessionConfiguration: StubURLProtocol.configuration()),
    arrayStateTimeout: timeout
  )
  return (repository, endpoint)
}

private func stateResponse(_ state: String) -> String {
  #"{"data": {"array": {"__typename": "ArrayMutations", "setState": {"__typename": "UnraidArray", "id": "server:array", "state": "\#(state)"}}}}"#
}

private func input(at endpoint: URL) -> [String: Any]? {
  StubURLProtocol.variables(url: endpoint).last?["input"] as? [String: Any]
}

@Test func stopSendsStopAndNoPassphrase() async throws {
  let (repository, endpoint) = makeRepository(host: "stub-array-stop.test", json: stateResponse("STOPPED"))

  let state = try await repository.setArrayState(.stop, passphrase: nil)

  #expect(state == "STOPPED")
  let sent = try #require(input(at: endpoint))
  #expect(sent["desiredState"] as? String == "STOP")
  #expect(sent["decryptionPassword"] == nil, "a stop must not send a passphrase key at all")
}

@Test func startSendsThePassphraseAsDecryptionPassword() async throws {
  let (repository, endpoint) = makeRepository(host: "stub-array-start-luks.test", json: stateResponse("STARTED"))

  let state = try await repository.setArrayState(.start, passphrase: "correct horse")

  #expect(state == "STARTED")
  let sent = try #require(input(at: endpoint))
  #expect(sent["desiredState"] as? String == "START")
  #expect(sent["decryptionPassword"] as? String == "correct horse")
  #expect(sent["decryptionKeyfile"] == nil)
}

/// Unraid can answer before the change is done. The caller polls for the rest.
@Test func returnsTheStateTheServerReportsEvenWhenItIsTheOldOne() async throws {
  let (repository, _) = makeRepository(host: "stub-array-start-pending.test", json: stateResponse("STOPPED"))

  let state = try await repository.setArrayState(.start, passphrase: nil)

  #expect(state == "STOPPED")
}

@Test func surfacesTheServersMessage() async {
  let (repository, _) = makeRepository(
    host: "stub-array-already.test",
    json: #"{"data": null, "errors": [{"message": "The array is already started", "path": ["array", "setState"]}]}"#
  )
  do {
    _ = try await repository.setArrayState(.start, passphrase: nil)
    Issue.record("expected setArrayState to throw")
  } catch {
    #expect(error as? AppError == .graphQL(["The array is already started"]), "threw \(error)")
  }
}

@Test func mapsAnAuthErrorToUnauthorized() async {
  let (repository, _) = makeRepository(
    host: "stub-array-forbidden.test",
    json: #"{"data": null, "errors": [{"message": "Forbidden", "extensions": {"code": "FORBIDDEN"}}]}"#
  )
  do {
    _ = try await repository.setArrayState(.stop, passphrase: nil)
    Issue.record("expected setArrayState to throw")
  } catch {
    #expect(error as? AppError == .unauthorized, "threw \(error)")
  }
}

/// The server took the request and keeps working after Tower stops waiting.
/// That is not an unreachable server.
@Test func aTimeoutReturnsNilNotUnreachable() async throws {
  let (repository, _) = makeRepository(host: "stub-array-timeout.test", json: nil, timeout: 0.3)

  let state = try await repository.setArrayState(.stop, passphrase: nil)

  #expect(state == nil)
}
