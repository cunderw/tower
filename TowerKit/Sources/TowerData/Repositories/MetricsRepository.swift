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
/// **One transport per subscription, and they end together.** Each of the
/// three subscriptions gets its own `WebSocketTransport`, with reconnection
/// off. When any one of them ends or fails, the other two are cancelled and
/// the merged stream ends, so the dashboard's retry restarts all three. A
/// subscription left dead beside two live ones would keep its metric on the
/// poll for the rest of the visit, with nothing to restart it.
///
/// **No cache.** `.networkOnly` with `writeResultsToCache: false`: a live
/// reading is shown once and replaced, and a monitoring client never shows a
/// cached reading as current.
public struct LiveMetricsRepository: MetricsStreaming {
  private let server: Server
  private let session: any WebSocketURLSession

  /// One `.tower` session for the repository's lifetime, which is the
  /// dashboard store's. Like `ApolloClientProvider`'s session, it has no
  /// delegate, so it retains nothing that would need invalidating.
  public init(server: Server) {
    self.init(server: server, session: URLSession(configuration: .tower))
  }

  /// The seam for tests: a mock `WebSocketURLSession` sees every frame the
  /// transport sends and scripts every frame it receives.
  init(server: Server, session: any WebSocketURLSession) {
    self.server = server
    self.session = session
  }

  /// Merges the three subscriptions into one stream. The first subscription to
  /// end, cleanly or with an error, ends the stream: the other two are
  /// cancelled, every socket is closed, and the stream finishes with that
  /// subscription's error, if it had one. Cancelling the stream cancels all
  /// three and closes their sockets.
  public func liveMetrics() -> AsyncThrowingStream<LiveMetricsUpdate, any Error> {
    AsyncThrowingStream { continuation in
      let task = Task {
        let firstError = await withTaskGroup(of: (any Error)?.self) { group in
          group.addTask {
            await forward(LiveCpuSubscription(), to: continuation) { data in
              .cpu(percent: data.systemMetricsCpu.percentTotal)
            }
          }
          group.addTask {
            await forward(LiveMemorySubscription(), to: continuation) { data in
              let memory = data.systemMetricsMemory
              return .memory(
                percent: memory.percentTotal, usedBytes: memory.used, totalBytes: memory.total)
            }
          }
          group.addTask {
            await forward(LiveTemperatureSubscription(), to: continuation) { data in
              .cpuTemperature(Self.hottestCPUSensor(in: data.systemMetricsTemperature))
            }
          }
          // The first subscription to end decides; the rest are cancelled and
          // drained, so every socket is closed before the stream finishes.
          let firstEnd = await group.next() ?? nil
          group.cancelAll()
          for await _ in group {}
          return firstEnd
        }
        continuation.finish(throwing: firstError)
      }
      continuation.onTermination = { _ in task.cancel() }
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
