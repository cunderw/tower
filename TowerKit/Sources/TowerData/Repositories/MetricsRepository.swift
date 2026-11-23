import Apollo
import ApolloAPI
import ApolloWebSocket
import Foundation
import TowerAPI
import TowerCore

/// Live CPU, memory and CPU temperature over the server's GraphQL
/// subscriptions (issue #24). Apollo's types stay in this file: the stream
/// carries `TowerCore`'s `LiveMetricsUpdate` only.
///
/// **The protocol.** The server speaks `graphql-transport-ws` on
/// `ws://<host>/graphql` and reads the API key from the `connection_init`
/// payload, not from a header. Measured against an Unraid 7.3 server: CPU sends
/// about every second, memory every 2 s, and temperature every 5 s, with the
/// first temperature about 6 s after the subscribe.
///
/// **One transport per subscription, and each retries on its own.** Each of
/// the three subscriptions runs in its own loop, on its own
/// `WebSocketTransport` with Apollo's reconnection off. When one ends or
/// fails, its loop waits `retryAfter` and subscribes again on a new
/// transport; the other two keep running. A server whose API lacks one of the
/// subscriptions fails it at once on every attempt, and its users still get
/// the other two live. While a subscription is down, its metric falls back to
/// the poll.
///
/// **No cache.** `.networkOnly` with `writeResultsToCache: false`: a live
/// reading is shown once and replaced, and a monitoring client never shows a
/// cached reading as current.
public struct LiveMetricsRepository: MetricsStreaming {
  private let server: Server
  private let session: any WebSocketURLSession
  private let retryAfter: Duration
  private let sleep: @Sendable (Duration) async throws -> Void

  /// One `.tower` session for the repository's lifetime, which is the
  /// dashboard store's. Like `ApolloClientProvider`'s session, it has no
  /// delegate, so it retains nothing that would need invalidating.
  ///
  /// - Parameter retryAfter: How long a subscription that ended or failed
  ///   waits before it subscribes again. The app passes its poll interval.
  public init(server: Server, retryAfter: Duration = .seconds(30)) {
    self.init(
      server: server, session: URLSession(configuration: .tower), retryAfter: retryAfter,
      sleep: { try await Task.sleep(for: $0) }
    )
  }

  /// The seam for tests: a mock `WebSocketURLSession` sees every frame the
  /// transport sends and scripts every frame it receives, and `sleep` lets a
  /// test end a retry wait by hand. `sleep` must throw when cancelled, as
  /// `Task.sleep` does, or a cancelled stream waits out the interval.
  init(
    server: Server, session: any WebSocketURLSession, retryAfter: Duration = .seconds(30),
    sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
  ) {
    self.server = server
    self.session = session
    self.retryAfter = retryAfter
    self.sleep = sleep
  }

  /// Merges the three subscriptions into one stream. A subscription that ends
  /// or fails subscribes again after `retryAfter`, and the others carry on,
  /// so the stream itself never ends on its own and never throws. Cancelling
  /// the stream (the dashboard leaves the screen, or the app goes to the
  /// background) ends all three at once, including one in its retry wait, and
  /// closes every socket.
  public func liveMetrics() -> AsyncThrowingStream<LiveMetricsUpdate, any Error> {
    AsyncThrowingStream { continuation in
      let task = Task {
        await withTaskGroup(of: Void.self) { group in
          group.addTask {
            await keepForwarding(LiveCpuSubscription(), to: continuation) { data in
              .cpu(percent: data.systemMetricsCpu.percentTotal)
            }
          }
          group.addTask {
            await keepForwarding(LiveMemorySubscription(), to: continuation) { data in
              let memory = data.systemMetricsMemory
              return .memory(
                percent: memory.percentTotal, usedBytes: memory.used, totalBytes: memory.total)
            }
          }
          group.addTask {
            await keepForwarding(LiveTemperatureSubscription(), to: continuation) { data in
              .cpuTemperature(Self.hottestCPUSensor(in: data.systemMetricsTemperature))
            }
          }
        }
        continuation.finish()
      }
      continuation.onTermination = { _ in task.cancel() }
    }
  }

  /// Runs one subscription until cancelled: forwards it, and each time it
  /// ends or fails, waits `retryAfter` and forwards it again on a new
  /// transport. The error that ended an attempt is dropped; the dashboard
  /// shows no error for a live stream.
  private func keepForwarding<Subscription: GraphQLSubscription>(
    _ subscription: Subscription,
    to continuation: AsyncThrowingStream<LiveMetricsUpdate, any Error>.Continuation,
    map: @escaping @Sendable (Subscription.Data) -> LiveMetricsUpdate
  ) async {
    while !Task.isCancelled {
      _ = await forward(subscription, to: continuation, map: map)
      // Cancellation ended that attempt: stop now, with no wait.
      guard !Task.isCancelled else { return }
      do { try await sleep(retryAfter) } catch { return }
    }
  }

  /// Runs one subscription on its own transport and yields each mapped
  /// response. Returns the error that ended it, or `nil` for a clean end.
  private func forward<Subscription: GraphQLSubscription>(
    _ subscription: Subscription,
    to continuation: AsyncThrowingStream<LiveMetricsUpdate, any Error>.Continuation,
    map: @Sendable (Subscription.Data) -> LiveMetricsUpdate
  ) async -> (any Error)? {
    let store = ApolloStore(cache: InMemoryNormalizedCache())
    let transport = WebSocketTransport(
      urlSession: session,
      store: store,
      endpointURL: server.webSocketEndpoint,
      configuration: WebSocketTransport.Configuration(
        // Negative is off. A dropped socket ends this subscription, and the
        // dashboard falls back to its poll.
        reconnectionInterval: -1,
        connectingPayload: ["x-api-key": server.apiKey]
      )
    )
    let client = ApolloClient(networkTransport: transport, store: store)
    var failure: (any Error)?
    do {
      let responses = try client.subscribe(
        subscription: subscription,
        cachePolicy: .networkOnly,
        requestConfiguration: RequestConfiguration(writeResultsToCache: false)
      )
      for try await response in responses {
        if let errors = response.errors, !errors.isEmpty {
          throw AppError.from(graphQLErrors: errors)
        }
        guard let data = response.data else {
          throw AppError.decoding("Empty response for \(Subscription.operationName).")
        }
        continuation.yield(map(data))
      }
    } catch {
      failure = error
    }
    // Closes the socket at this known point. Releasing the transport closes
    // it too, in its deinit, which is why the kit tests pass with or without
    // this call. The call keeps the close from depending on when the last
    // reference to the transport goes.
    await transport.pause()
    return failure
  }

  /// The hottest `CPU_PACKAGE` or `CPU_CORE` sensor, in the unit the server
  /// reports. `nil` when the server reports no CPU sensor.
  ///
  /// The server's `summary` is not used: on a 4.37 server `summary.hottest`
  /// is a fan reading of 704, two bogus sensors count as critical, and the
  /// average includes voltages. The server's `status` is not read either.
  static func hottestCPUSensor(
    in metrics: LiveTemperatureSubscription.Data.SystemMetricsTemperature?
  ) -> TemperatureReading? {
    let readings = (metrics?.sensors ?? []).compactMap { sensor -> TemperatureReading? in
      switch sensor.type {
      case .case(.cpuPackage), .case(.cpuCore): break
      default: return nil
      }
      guard let unit = TemperatureReading.Unit(sensor.current.unit) else { return nil }
      return TemperatureReading(value: sensor.current.value, unit: unit)
    }
    return readings.max { $0.value < $1.value }
  }
}

extension TemperatureReading.Unit {
  /// `nil` for a unit this build does not know, so an unknown unit hides the
  /// reading rather than showing it with the wrong symbol.
  init?(_ unit: GraphQLEnum<TowerAPI.TemperatureUnit>) {
    switch unit {
    case .case(.celsius): self = .celsius
    case .case(.fahrenheit): self = .fahrenheit
    case .case(.kelvin): self = .kelvin
    case .case(.rankine): self = .rankine
    case .unknown: return nil
    }
  }
}

extension Server {
  /// The GraphQL endpoint with a websocket scheme: `ws` for `http`, `wss` for
  /// `https`. Unraid serves GraphQL on http only, so `ws` is the live case.
  var webSocketEndpoint: URL {
    var components = URLComponents(url: graphQLEndpoint, resolvingAgainstBaseURL: false)
    components?.scheme = graphQLEndpoint.scheme == "https" ? "wss" : "ws"
    return components?.url ?? graphQLEndpoint
  }
}
