import Apollo
import ApolloAPI
import Foundation
import TowerCore

/// Builds a configured `ApolloClient` for one server.
///
/// The API key travels in the `x-api-key` header on every request.
public struct ApolloClientProvider: Sendable {
  public let server: Server

  /// Deliberately **not** public. The app target constructs a provider and
  /// hands it to a repository, but must never reach the client directly — a
  /// public `ApolloClient` would let any feature module run raw generated
  /// queries and bypass the repository boundary, which is the one rule
  /// keeping views and stores testable without Apollo.
  let client: ApolloClient

  /// Also not public — held only so tests (via `@testable import`) can
  /// confirm that `AuthenticatedInterceptorProvider`, not
  /// `DefaultInterceptorProvider`, is the interceptor provider actually
  /// wired into the transport backing `client`. `ApolloClient`'s own
  /// `networkTransport` is internal to the Apollo module, so this is the
  /// only reachable seam for that check.
  let transport: RequestChainNetworkTransport

  /// - Parameters:
  ///   - server: The server this provider talks to.
  ///   - sessionConfiguration: Defaults to `.tower`, which shares no cache,
  ///     cookie jar, or credential store with anything else in the process. Pass
  ///     a custom one to install `protocolClasses` for a test (see
  ///     `StubURLProtocol`).
  ///   - sessionDelegate: The seam for per-server TLS trust decisions —
  ///     trust-on-first-use or certificate pinning for Unraid's usual
  ///     self-signed cert. Apollo hands a delegate that also conforms to
  ///     `URLSessionTaskDelegate` to every task it creates, so
  ///     `urlSession(_:didReceive:completionHandler:)` is reachable from here
  ///     without touching Apollo.
  ///
  ///     **The session retains a non-nil delegate until it is invalidated**, and
  ///     nothing invalidates these sessions — a provider lives as long as the
  ///     repository holding it. That is fine for the one-provider-per-server
  ///     lifetime the app has today, and it is the thing to solve *before*
  ///     shipping a delegate: whoever adds one owns deciding where
  ///     `finishTasksAndInvalidate()` goes. Nothing passes one today.
  public init(
    server: Server,
    sessionConfiguration: URLSessionConfiguration = .tower,
    sessionDelegate: (any URLSessionDelegate)? = nil
  ) {
    self.server = server

    let store = ApolloStore(cache: InMemoryNormalizedCache())
    let provider = AuthenticatedInterceptorProvider(apiKey: server.apiKey)
    let transport = RequestChainNetworkTransport(
      // Its own session, not `URLSession.shared`. `.shared` has no
      // delegate seam at all — you cannot attach one — which made per-server TLS
      // trust impossible without a broader refactor, and it shares its
      // `URLCache`, `HTTPCookieStorage`, and `URLCredentialStorage` with every
      // other user of `.shared` in the process. Not a live leak while auth is a
      // static header with no cookies or challenges, but the risk arrives the
      // moment any credential or trust caching does — or the moment a user
      // reconnects to a *different* box at a LAN address they used before.
      urlSession: URLSession(
        configuration: sessionConfiguration,
        delegate: sessionDelegate,
        delegateQueue: nil
      ),
      interceptorProvider: provider,
      store: store,
      endpointURL: server.graphQLEndpoint
    )
    self.transport = transport
    self.client = ApolloClient(networkTransport: transport, store: store)
  }
}

extension URLSessionConfiguration {
  /// Tower's session configuration: nothing shared, nothing cached.
  ///
  /// Built from `.ephemeral` so no cookie jar, credential store, or cache is
  /// written to disk or shared with the rest of the process, then narrowed
  /// further:
  ///
  /// - `urlCache = nil` and `.reloadIgnoringLocalCacheData` — a monitoring client
  ///   must never render a cached response as current state. Apollo's own
  ///   `.networkOnly` policy covers its normalized cache; this covers the layer
  ///   underneath it, which Apollo does not control.
  /// - `httpCookieStorage`/`urlCredentialStorage = nil` — Unraid authenticates
  ///   with a static `x-api-key` header, so there is nothing legitimate for
  ///   either to hold, and both are how "reconnected to a different server at
  ///   the same LAN address" turns into stale-identity bugs.
  ///
  /// The request timeout is left at the default 60s deliberately: a slow load
  /// is made escapable in `LoadingStore`, where every feature inherits it, not
  /// by a timeout tuned here.
  public static var tower: URLSessionConfiguration {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.urlCache = nil
    configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
    configuration.httpCookieStorage = nil
    configuration.httpShouldSetCookies = false
    configuration.urlCredentialStorage = nil
    return configuration
  }
}

/// Injects `x-api-key` ahead of the default interceptor chain.
///
/// Unraid authenticates every GraphQL request with this header; there is no
/// bearer token or session cookie involved.
struct AuthHeaderInterceptor: GraphQLInterceptor {
  let apiKey: String

  func intercept<Request: GraphQLRequest>(
    request: Request,
    next: NextInterceptorFunction<Request>
  ) async throws -> InterceptorResultStream<Request> {
    var authenticated = request
    authenticated.additionalHeaders["x-api-key"] = apiKey
    return await next(authenticated)
  }
}

/// Composes `AuthHeaderInterceptor` ahead of Apollo's default interceptor
/// chain.
///
/// `InterceptorProvider` (as resolved from apollo-ios 2.3.0) declares four
/// requirements — `graphQLInterceptors`, `cacheInterceptor`, `httpInterceptors`,
/// and `responseParser` — each with a default implementation supplied by a
/// protocol extension. `DefaultInterceptorProvider` itself has no public
/// initializer (and no `store` parameter); it only exposes a
/// `DefaultInterceptorProvider.shared` singleton. This type delegates the three
/// untouched requirements to that singleton and overrides only
/// `graphQLInterceptors` to prepend the auth header interceptor.
struct AuthenticatedInterceptorProvider: InterceptorProvider {
  let apiKey: String

  func graphQLInterceptors<Operation: GraphQLOperation>(
    for operation: Operation
  ) -> [any GraphQLInterceptor] {
    [AuthHeaderInterceptor(apiKey: apiKey)]
      + DefaultInterceptorProvider.shared.graphQLInterceptors(for: operation)
  }

  func cacheInterceptor<Operation: GraphQLOperation>(
    for operation: Operation
  ) -> any CacheInterceptor {
    DefaultInterceptorProvider.shared.cacheInterceptor(for: operation)
  }

  func httpInterceptors<Operation: GraphQLOperation>(
    for operation: Operation
  ) -> [any HTTPInterceptor] {
    DefaultInterceptorProvider.shared.httpInterceptors(for: operation)
  }

  func responseParser<Operation: GraphQLOperation>(
    for operation: Operation
  ) -> any ResponseParsingInterceptor {
    DefaultInterceptorProvider.shared.responseParser(for: operation)
  }
}
