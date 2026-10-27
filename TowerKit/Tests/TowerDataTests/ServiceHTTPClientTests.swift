import Foundation
import Testing
import TowerCore
@testable import TowerData

private struct Movie: Decodable, Equatable, Sendable {
  let id: Int
  let title: String
}

private func makeClient(
  host: String,
  kind: ServiceKind = .radarr,
  path: String = "",
  credentials: ServiceCredentials = .apiKey("secret"),
  customHeaders: [String: String] = [:]
) -> ServiceHTTPClient {
  let instance = ServiceInstance(
    kind: kind,
    name: kind.displayName,
    baseURL: URL(string: "http://\(host)\(path)")!,
    credentials: credentials,
    customHeaders: customHeaders
  )
  return ServiceHTTPClient(
    instance: instance, sessionConfiguration: ServiceStubURLProtocol.configuration())
}

// MARK: - URL building

@Test func aRelativePathIsJoinedOntoTheBaseURL() async throws {
  let host = "join.test"
  ServiceStubURLProtocol.stub(host: host, reply: .json(#"{"id":1,"title":"Dune"}"#))
  let client = makeClient(host: host)

  _ = try await client.send("api/v3/movie/1", as: Movie.self)

  #expect(ServiceStubURLProtocol.requests(host: host).first?.url?.path() == "/api/v3/movie/1")
}

@Test func aTrailingSlashOnTheBaseURLDoesNotDoubleUp() async throws {
  // Users paste addresses with and without the slash; both must produce the
  // same URL rather than a //api path the service 404s.
  let host = "slash.test"
  ServiceStubURLProtocol.stub(host: host, reply: .json(#"{"id":1,"title":"Dune"}"#))
  let client = makeClient(host: host, path: "/")

  _ = try await client.send("api/v3/movie/1", as: Movie.self)

  #expect(ServiceStubURLProtocol.requests(host: host).first?.url?.path() == "/api/v3/movie/1")
}

@Test func aBasePathOnTheBaseURLIsPreserved() async throws {
  // A reverse proxy serving Radarr at /radarr is normal; dropping the base path
  // would make every request 404 with a URL that looks right in a log.
  let host = "basepath.test"
  ServiceStubURLProtocol.stub(host: host, reply: .json(#"{"id":1,"title":"Dune"}"#))
  let client = makeClient(host: host, path: "/radarr")

  _ = try await client.send("api/v3/movie/1", as: Movie.self)

  #expect(ServiceStubURLProtocol.requests(host: host).first?.url?.path() == "/radarr/api/v3/movie/1")
}

@Test func queryItemsAreSent() async throws {
  let host = "query.test"
  ServiceStubURLProtocol.stub(host: host, reply: .json(#"{"id":1,"title":"Dune"}"#))
  let client = makeClient(host: host)

  _ = try await client.send(
    "api/v3/movie", query: [URLQueryItem(name: "term", value: "du ne")], as: Movie.self)

  let url = try #require(ServiceStubURLProtocol.requests(host: host).first?.url)
  #expect(url.query() == "term=du%20ne")
}

// MARK: - Auth injection

@Test(arguments: [ServiceKind.radarr, .sonarr, .lidarr, .prowlarr, .bazarr, .overseerr])
func apiKeyServicesSendTheKeyAsAHeader(kind: ServiceKind) async throws {
  let host = "\(kind.rawValue)-auth.test"
  ServiceStubURLProtocol.stub(host: host, reply: .json(#"{"id":1,"title":"Dune"}"#))
  let client = makeClient(host: host, kind: kind, credentials: .apiKey("k3y"))

  _ = try await client.send("api", as: Movie.self)

  let request = try #require(ServiceStubURLProtocol.requests(host: host).first)
  #expect(request.value(forHTTPHeaderField: "X-Api-Key") == "k3y")
  // The key must never end up in the URL for these — query strings land in
  // proxy and server logs.
  #expect(request.url?.query() == nil)
}

@Test func tautulliSendsTheKeyAsAQueryParameter() async throws {
  // Tautulli's API takes `apikey` in the query string and ignores headers.
  let host = "tautulli-auth.test"
  ServiceStubURLProtocol.stub(host: host, reply: .json(#"{"id":1,"title":"Dune"}"#))
  let client = makeClient(host: host, kind: .tautulli, credentials: .apiKey("k3y"))

  _ = try await client.send("api/v2", query: [URLQueryItem(name: "cmd", value: "activity")], as: Movie.self)

  let request = try #require(ServiceStubURLProtocol.requests(host: host).first)
  let query = try #require(request.url?.query())
  #expect(query.contains("apikey=k3y"))
  #expect(query.contains("cmd=activity"))
  #expect(request.value(forHTTPHeaderField: "X-Api-Key") == nil)
}

@Test func nzbgetSendsBasicAuth() async throws {
  let host = "nzbget-auth.test"
  ServiceStubURLProtocol.stub(host: host, reply: .json(#"{"id":1,"title":"Dune"}"#))
  let client = makeClient(
    host: host, kind: .nzbget, credentials: .usernamePassword(username: "nzb", password: "get"))

  _ = try await client.send("jsonrpc", as: Movie.self)

  let request = try #require(ServiceStubURLProtocol.requests(host: host).first)
  let expected = "Basic " + Data("nzb:get".utf8).base64EncodedString()
  #expect(request.value(forHTTPHeaderField: "Authorization") == expected)
}

@Test func nzbgetWithNoCredentialsSendsNoAuthorizationHeaderAtAll() async throws {
  // NZBGet with no `ControlUsername`/`ControlPassword` serves unauthenticated.
  // The wrong fix is an empty Basic header: `Basic Og==` is the base64
  // of a bare colon, which asserts a credential rather than declining to, and a
  // server or proxy is entitled to reject it.
  let host = "nzbget-noauth.test"
  ServiceStubURLProtocol.stub(host: host, reply: .json(#"{"id":1,"title":"Dune"}"#))
  let client = makeClient(
    host: host, kind: .nzbget, credentials: .usernamePassword(username: "", password: ""))

  _ = try await client.send("jsonrpc", as: Movie.self)

  let request = try #require(ServiceStubURLProtocol.requests(host: host).first)
  #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
}

@Test func aHalfFilledCredentialPairIsStillSent() async throws {
  // A username with no password is a real NZBGet configuration, and guessing
  // that the user meant "no auth" would silently drop the half they typed.
  let host = "nzbget-halfauth.test"
  ServiceStubURLProtocol.stub(host: host, reply: .json(#"{"id":1,"title":"Dune"}"#))
  let client = makeClient(
    host: host, kind: .nzbget, credentials: .usernamePassword(username: "nzb", password: ""))

  _ = try await client.send("jsonrpc", as: Movie.self)

  let request = try #require(ServiceStubURLProtocol.requests(host: host).first)
  let expected = "Basic " + Data("nzb:".utf8).base64EncodedString()
  #expect(request.value(forHTTPHeaderField: "Authorization") == expected)
}

@Test func credentialsOfTheWrongShapeSurfaceAsUnauthorized() async throws {
  // The add-service flow shows fields by kind, so this shouldn't be reachable —
  // but a hand-edited or migrated record must fail as a credential problem
  // rather than sending an unauthenticated request and reporting whatever the
  // service says about it.
  let host = "mismatch-auth.test"
  ServiceStubURLProtocol.stub(host: host, reply: .json(#"{"id":1,"title":"Dune"}"#))
  let client = makeClient(
    host: host, kind: .radarr,
    credentials: .usernamePassword(username: "u", password: "p"))

  await #expect(throws: AppError.unauthorized) {
    _ = try await client.send("api", as: Movie.self)
  }
  #expect(ServiceStubURLProtocol.requests(host: host).isEmpty)
}

// MARK: - Custom headers

@Test func customHeadersAreSentOnEveryCall() async throws {
  let host = "headers.test"
  ServiceStubURLProtocol.stub(host: host, reply: .json(#"{"id":1,"title":"Dune"}"#))
  let client = makeClient(
    host: host, customHeaders: ["CF-Access-Client-Id": "id", "CF-Access-Client-Secret": "shh"])

  _ = try await client.send("api/v3/movie/1", as: Movie.self)
  _ = try await client.send("api/v3/movie/2", as: Movie.self)

  let requests = ServiceStubURLProtocol.requests(host: host)
  #expect(requests.count == 2)
  for request in requests {
    #expect(request.value(forHTTPHeaderField: "CF-Access-Client-Id") == "id")
    #expect(request.value(forHTTPHeaderField: "CF-Access-Client-Secret") == "shh")
    #expect(request.value(forHTTPHeaderField: "X-Api-Key") == "secret")
  }
}

@Test func aCustomHeaderCanOverrideTheInjectedAuthHeader() async throws {
  // Deliberate: custom headers exist for deployments Tower can't anticipate, so
  // the user's explicit value wins over the per-kind default.
  let host = "header-override.test"
  ServiceStubURLProtocol.stub(host: host, reply: .json(#"{"id":1,"title":"Dune"}"#))
  let client = makeClient(host: host, customHeaders: ["X-Api-Key": "proxy-key"])

  _ = try await client.send("api", as: Movie.self)

  let request = try #require(ServiceStubURLProtocol.requests(host: host).first)
  #expect(request.value(forHTTPHeaderField: "X-Api-Key") == "proxy-key")
}

// MARK: - Bodies

@Test func aJSONBodyIsEncodedAndTagged() async throws {
  struct Payload: Encodable, Sendable { let title: String }
  let host = "body.test"
  ServiceStubURLProtocol.stub(host: host, reply: .json(#"{"id":1,"title":"Dune"}"#))
  let client = makeClient(host: host)

  _ = try await client.send("api/v3/movie", method: .post, body: Payload(title: "Dune"), as: Movie.self)

  let request = try #require(ServiceStubURLProtocol.requests(host: host).first)
  #expect(request.httpMethod == "POST")
  #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
  #expect(request.recordedBody == Data(#"{"title":"Dune"}"#.utf8))
}

@Test func aResponselessSendAcceptsAnEmptyBody() async throws {
  // 204 with no body is normal for *arr deletes; decoding must not be attempted.
  let host = "nocontent.test"
  ServiceStubURLProtocol.stub(host: host, reply: Reply204())
  let client = makeClient(host: host)

  try await client.send("api/v3/movie/1", method: .delete)
}

private func Reply204() -> ServiceStubURLProtocol.Reply {
  ServiceStubURLProtocol.Reply(status: 204, body: Data(), headers: [:])
}

// MARK: - Error mapping

@Test(arguments: [401, 403])
func rejectedCredentialsMapToUnauthorized(status: Int) async throws {
  let host = "unauth\(status).test"
  ServiceStubURLProtocol.stub(host: host, reply: .json("{}", status: status))
  let client = makeClient(host: host)

  await #expect(throws: AppError.unauthorized) {
    _ = try await client.send("api", as: Movie.self)
  }
}

@Test func aRefusedConnectionMapsToServerUnreachable() async throws {
  let host = "refused.test"
  ServiceStubURLProtocol.stub(host: host) { _ in .failure(URLError(.cannotConnectToHost)) }
  let client = makeClient(host: host)

  await #expect(throws: AppError.serverUnreachable) {
    _ = try await client.send("api", as: Movie.self)
  }
}

@Test func aDeniedLocalNetworkPromptKeepsItsOwnCase() async throws {
  // Keeping the Unraid tabs' local-network handling is the point of routing
  // transport failures through AppError.from(transport:) rather than mapping
  // here.
  let host = "localnet.test"
  ServiceStubURLProtocol.stub(host: host) { _ in .failure(URLError(.networkConnectionLost)) }
  let client = makeClient(host: host)

  await #expect(throws: AppError.localNetworkDenied) {
    _ = try await client.send("api", as: Movie.self)
  }
}

@Test func aSelfSignedCertificateMapsToInsecureConnection() async throws {
  let host = "tls.test"
  ServiceStubURLProtocol.stub(host: host) { _ in .failure(URLError(.serverCertificateUntrusted)) }
  let client = makeClient(host: host)

  await #expect(throws: AppError.insecureConnection) {
    _ = try await client.send("api", as: Movie.self)
  }
}

@Test func anUndecodableBodyMapsToDecoding() async throws {
  let host = "decode.test"
  ServiceStubURLProtocol.stub(host: host, reply: .json(#"{"id":"one"}"#))
  let client = makeClient(host: host)

  let error = await capture { _ = try await client.send("api", as: Movie.self) }
  guard case .decoding = try #require(error) else {
    Issue.record("expected .decoding, got \(String(describing: error))")
    return
  }
}

@Test func anHTMLLoginPageMapsToDecodingNotACrash() async throws {
  // A reverse proxy that intercepts with a login page answers 200 with HTML.
  let host = "html.test"
  ServiceStubURLProtocol.stub(
    host: host,
    reply: ServiceStubURLProtocol.Reply(
      status: 200, body: Data("<html>sign in</html>".utf8),
      headers: ["Content-Type": "text/html"]))
  let client = makeClient(host: host)

  let error = await capture { _ = try await client.send("api", as: Movie.self) }
  guard case .decoding = try #require(error) else {
    Issue.record("expected .decoding, got \(String(describing: error))")
    return
  }
}

@Test func aServerErrorSurfacesTheServicesOwnMessage() async throws {
  let host = "servererror.test"
  ServiceStubURLProtocol.stub(
    host: host, reply: .json(#"{"message":"Quality profile not found"}"#, status: 500))
  let client = makeClient(host: host)

  let error = await capture { _ = try await client.send("api", as: Movie.self) }
  guard case .unknown(let detail) = try #require(error) else {
    Issue.record("expected .unknown, got \(String(describing: error))")
    return
  }
  #expect(detail.contains("Quality profile not found"))
  #expect(detail.contains("500"))
}

@Test func aNotFoundSuggestsTheAddressRatherThanTheCredentials() async throws {
  // 404 here is nearly always a wrong base path, not a missing record — the
  // *arr APIs answer an unknown id with 404 too, but a repository that asks for
  // an id it just listed is the rarer case.
  let host = "notfound.test"
  ServiceStubURLProtocol.stub(host: host, reply: .json("{}", status: 404))
  let client = makeClient(host: host)

  let error = await capture { _ = try await client.send("api", as: Movie.self) }
  guard case .unknown(let detail) = try #require(error) else {
    Issue.record("expected .unknown, got \(String(describing: error))")
    return
  }
  #expect(detail.contains("404"))
  #expect(detail.lowercased().contains("address"))
}

@Test func aCancelledRequestMapsToCancelled() async throws {
  let host = "cancel.test"
  ServiceStubURLProtocol.stub(host: host) { _ in .failure(URLError(.cancelled)) }
  let client = makeClient(host: host)

  await #expect(throws: AppError.cancelled) {
    _ = try await client.send("api", as: Movie.self)
  }
}

@Test func everyFailureIsAnAppError() async throws {
  // The client's contract: no URLError and no DecodingError escapes it, so no
  // store or view has to know what transport is underneath.
  let outcomes: [ServiceStubURLProtocol.Outcome] = [
    .failure(URLError(.cannotConnectToHost)),
    .failure(URLError(.badServerResponse)),
    .reply(.json("{}", status: 401)),
    .reply(.json("{}", status: 500)),
    .reply(.json("not json at all", status: 200)),
  ]
  for (index, outcome) in outcomes.enumerated() {
    let host = "contract\(index).test"
    ServiceStubURLProtocol.stub(host: host) { _ in outcome }
    let client = makeClient(host: host)
    let error = await capture { _ = try await client.send("api", as: Movie.self) }
    #expect(error != nil, "outcome \(index) should have failed")
  }
}

/// Runs `work` and returns the `AppError` it threw, failing the test if it threw
/// anything else — which is the contract under test in most of the cases above.
private func capture(_ work: () async throws -> Void) async -> AppError? {
  do {
    try await work()
    return nil
  } catch let error as AppError {
    return error
  } catch {
    Issue.record("expected an AppError, got \(type(of: error)): \(error)")
    return nil
  }
}

// MARK: - Auth style agrees with the domain's credential style

@Test(arguments: ServiceKind.allCases)
func theTransportsAuthStyleMatchesTheKindsCredentialStyle(kind: ServiceKind) {
  // Two switches over the same eight cases, in two layers: the form asks
  // `credentialStyle` which fields to show, and the client asks `ServiceAuthStyle`
  // what to put on the wire. If they ever disagree, the add-service form collects
  // credentials the client then refuses as the wrong shape — and the user sees
  // "credentials rejected" for a record they just typed correctly.
  switch ServiceAuthStyle(kind: kind) {
  case .apiKeyHeader, .apiKeyQuery:
    #expect(kind.credentialStyle == .apiKey)
  case .basic:
    #expect(kind.credentialStyle == .usernamePassword)
  }
}
