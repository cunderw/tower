import Apollo
import ApolloAPI
import Foundation
import Testing
@testable import TowerData
import TowerAPI
import TowerCore

// These tests exercise `AuthHeaderInterceptor` and `AuthenticatedInterceptorProvider`
// directly, without a live server. `AuthHeaderInterceptor.intercept(request:next:)`
// is called with a `next` closure that never actually reaches the network —
// it inspects the forwarded request and immediately finishes an empty stream —
// so this proves the header is set on the outgoing request without any
// networking or mocking framework.

private func makeRequest(apiKey: String? = nil) -> JSONRequest<TestConnectionQuery> {
  var request = JSONRequest(
    operation: TestConnectionQuery(),
    graphQLEndpoint: URL(string: "http://192.0.2.10/graphql")!,
    fetchBehavior: .NetworkOnly,
    writeResultsToCache: false,
    requestTimeout: nil
  )
  if let apiKey {
    request.additionalHeaders["x-api-key"] = apiKey
  }
  return request
}

private func emptyStream() -> InterceptorResultStream<JSONRequest<TestConnectionQuery>> {
  NonCopyableAsyncThrowingStream(
    stream: AsyncThrowingStream<ParsedResult<TestConnectionQuery>, any Error> { continuation in
      continuation.finish()
    }
  )
}

@Test func authHeaderInterceptorSetsTheAPIKeyHeaderOnTheForwardedRequest() async throws {
  let interceptor = AuthHeaderInterceptor(apiKey: "secret-key-123")
  let request = makeRequest()

  _ = try await interceptor.intercept(request: request) { forwarded in
    #expect(forwarded.additionalHeaders["x-api-key"] == "secret-key-123")
    return emptyStream()
  }
}

@Test func authHeaderInterceptorPreservesOtherHeadersRatherThanReplacingTheDictionary() async throws {
  // A regression that reassigns `additionalHeaders` wholesale (instead of
  // adding a key) would silently drop `JSONRequest`'s own default headers.
  let interceptor = AuthHeaderInterceptor(apiKey: "secret-key-123")
  let request = makeRequest()
  #expect(request.additionalHeaders["Content-Type"] == "application/json")

  _ = try await interceptor.intercept(request: request) { forwarded in
    #expect(forwarded.additionalHeaders["Content-Type"] == "application/json")
    #expect(forwarded.additionalHeaders["x-api-key"] == "secret-key-123")
    return emptyStream()
  }
}

@Test func authHeaderInterceptorOverwritesAnyPreexistingAPIKeyHeader() async throws {
  // Guards against a regression that only sets the header when absent
  // (e.g. via a merge that favors existing values), which would let a
  // stale key silently survive a key rotation.
  let interceptor = AuthHeaderInterceptor(apiKey: "new-key")
  let request = makeRequest(apiKey: "stale-key")

  _ = try await interceptor.intercept(request: request) { forwarded in
    #expect(forwarded.additionalHeaders["x-api-key"] == "new-key")
    return emptyStream()
  }
}

@Test func authenticatedInterceptorProviderPutsTheAuthInterceptorFirst() {
  let provider = AuthenticatedInterceptorProvider(apiKey: "secret-key-123")
  let interceptors = provider.graphQLInterceptors(for: TestConnectionQuery())
  let defaults = DefaultInterceptorProvider.shared.graphQLInterceptors(for: TestConnectionQuery())

  // Exact count: one auth interceptor plus whatever the default chain
  // supplies. A regression that forgets to append the defaults, or that
  // duplicates the auth interceptor, changes this count.
  #expect(interceptors.count == defaults.count + 1)
  #expect(interceptors.first is AuthHeaderInterceptor)
  #expect((interceptors.first as? AuthHeaderInterceptor)?.apiKey == "secret-key-123")
}

@Test func apolloClientProviderRetainsTheServerItWasBuiltWith() {
  let server = Server(
    name: "Tower",
    url: URL(string: "http://192.0.2.10")!,
    apiKey: "secret-key-123"
  )
  let provider = ApolloClientProvider(server: server)
  #expect(provider.server == server)
}

@Test func initWiresTheAuthenticatedInterceptorProviderIntoTheTransport() {
  // The missing link the interceptor/ordering unit tests above don't cover:
  // this proves `ApolloClientProvider.init` actually threads
  // AuthenticatedInterceptorProvider into the transport backing `client`,
  // rather than, say, `DefaultInterceptorProvider.shared`. Swapping in the
  // latter at the construction call site would still pass every other test
  // in this file but must fail this one. `client.networkTransport` itself is
  // internal to the Apollo module, so `transport` is held separately (and
  // is the exact same instance passed into `client`) purely to make this
  // reachable.
  let server = Server(
    name: "Tower",
    url: URL(string: "http://192.0.2.10")!,
    apiKey: "secret-key-123"
  )
  let provider = ApolloClientProvider(server: server)

  guard let authProvider = provider.transport.interceptorProvider as? AuthenticatedInterceptorProvider else {
    Issue.record(
      "expected AuthenticatedInterceptorProvider, got \(type(of: provider.transport.interceptorProvider))"
    )
    return
  }
  #expect(authProvider.apiKey == "secret-key-123")
}

// MARK: - Its own session

@Test func eachProviderOwnsASessionThatIsNotTheSharedOne() {
  // Why each provider owns a session: `URLSession.shared` has no delegate seam
  // at all, so per-server TLS trust is impossible, and its cache/cookie/credential
  // storage is shared with every other user of `.shared` in the process.
  let provider = ApolloClientProvider(server: Server(name: "A", url: URL(string: "http://192.0.2.10")!, apiKey: "k"))
  let session = try? #require(provider.transport.urlSession as? URLSession)

  #expect(session !== URLSession.shared)
  #expect(session?.configuration.urlCache == nil, "a monitoring client must not serve a cached response as current state")
  #expect(session?.configuration.httpCookieStorage == nil)
  #expect(session?.configuration.urlCredentialStorage == nil)
  #expect(session?.configuration.requestCachePolicy == .reloadIgnoringLocalCacheData)
}

@Test func twoProvidersForTheSameServerDoNotShareASession() {
  // Two boxes at the same LAN address over time: if the sessions were shared,
  // whatever the first cached or trusted would follow the second.
  let server = Server(name: "A", url: URL(string: "http://192.0.2.10")!, apiKey: "k")
  let first = ApolloClientProvider(server: server).transport.urlSession as? URLSession
  let second = ApolloClientProvider(server: server).transport.urlSession as? URLSession

  #expect(first !== second)
}

@Test func aSessionDelegateReachesTheSessionSoTLSTrustHasASeam() {
  // Not a TLS test — there is no self-signed server here to challenge against.
  // It proves the seam is connected: a delegate handed to the provider is the
  // session's delegate, and Apollo passes a `URLSessionTaskDelegate` through to
  // every task it creates (see `ApolloURLSession`'s `URLSession` conformance), so
  // `urlSession(_:didReceive:completionHandler:)` is reachable without touching
  // Apollo when trust-on-first-use or pinning lands.
  final class RecordingDelegate: NSObject, URLSessionTaskDelegate {}
  let delegate = RecordingDelegate()
  let provider = ApolloClientProvider(
    server: Server(name: "A", url: URL(string: "http://192.0.2.10")!, apiKey: "k"),
    sessionDelegate: delegate
  )
  let session = provider.transport.urlSession as? URLSession

  #expect(session?.delegate === delegate)
  // The session retains it until invalidated — documented on the initializer,
  // and the reason nothing passes one yet.
  session?.finishTasksAndInvalidate()
}

@Test func reconnectingToADifferentServerAtTheSameAddressDoesNotServeTheFirstResponse() async throws {
  // Same URL, two different servers over time: the second provider must see the
  // second server's answer, not the first's.
  //
  // **What this does and doesn't prove.** It proves the two providers share no
  // response state — separate `ApolloStore`s, separate sessions. It does *not*
  // prove the `URLCache` change matters, because `StubURLProtocol` answers with
  // `cacheStoragePolicy: .notAllowed`, so nothing would be cached at the HTTP
  // layer even with `.shared`. Proving that would need a real server with cache
  // headers, which this suite deliberately doesn't have; the configuration
  // assertions in `eachProviderOwnsASessionThatIsNotTheSharedOne` are what cover
  // it, and they're checked against the session Apollo actually holds rather than
  // against the code that built it.
  let endpoint = URL(string: "http://stub-reconnect-same-address.test/graphql")!
  let server = Server(name: "Same address", url: URL(string: "http://stub-reconnect-same-address.test")!, apiKey: "k")

  StubURLProtocol.stub(
    url: endpoint,
    json: #"{"data": {"info": {"__typename": "Info", "os": {"__typename": "InfoOs", "platform": "Linux"}}}}"#
  )
  let firstBox = LiveSystemRepository(
    provider: ApolloClientProvider(server: server, sessionConfiguration: StubURLProtocol.configuration())
  )
  #expect(try await firstBox.testConnection())

  // A different machine now answers at that address, and it isn't Unraid.
  StubURLProtocol.stub(
    url: endpoint,
    json: #"{"data": {"info": {"__typename": "Info", "os": {"__typename": "InfoOs", "platform": null}}}}"#
  )
  let secondBox = LiveSystemRepository(
    provider: ApolloClientProvider(server: server, sessionConfiguration: StubURLProtocol.configuration())
  )

  #expect(try await secondBox.testConnection() == false, "the second provider served the first server's response")
}
