import ApolloWebSocket
import Foundation
import Testing
import TowerCore
@testable import TowerData

// These tests run `LiveMetricsRepository` end to end through Apollo's real
// `WebSocketTransport`, over a scripted socket. The script answers in the
// `graphql-transport-ws` frames the server sends, so the protocol handshake,
// the parsing and the mapping to `LiveMetricsUpdate` are all under test.

// MARK: - Scripted socket

/// Builds one server frame from the operation id it answers.
private typealias Frame = @Sendable (String) -> String

/// One `WebSocketTask` per transport. Answers `connection_init` with
/// `connection_ack`, and a `subscribe` with the frames scripted for that
/// operation. With no frame queued, `receive()` suspends, as a live socket
/// does between readings; a return or a throw there would end the stream.
private final class ScriptedSocket: WebSocketTask, @unchecked Sendable {
  private let lock = NSLock()
  private let script: [String: [Frame]]
  private var inbox: [String] = []
  private var waiter: CheckedContinuation<URLSessionWebSocketTask.Message, any Error>?
  private var sentFrames: [[String: Any]] = []
  private var isCancelled = false

  init(script: [String: [Frame]]) {
    self.script = script
  }

  var sent: [[String: Any]] { lock.withLock { sentFrames } }
  var cancelled: Bool { lock.withLock { isCancelled } }

  func resume() {}

  func send(_ message: URLSessionWebSocketTask.Message) async throws {
    guard case .string(let text) = message,
          let frame = try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any]
    else { return }
    lock.withLock { sentFrames.append(frame) }
    switch frame["type"] as? String {
    case "connection_init":
      deliver(#"{"type":"connection_ack"}"#)
    case "subscribe":
      let id = frame["id"] as? String ?? ""
      let payload = frame["payload"] as? [String: Any]
      let name = payload?["operationName"] as? String ?? ""
      for makeFrame in script[name] ?? [] { deliver(makeFrame(id)) }
    default:
      break
    }
  }

  func receive() async throws -> URLSessionWebSocketTask.Message {
    try await withCheckedThrowingContinuation { continuation in
      lock.withLock {
        if isCancelled {
          continuation.resume(throwing: URLError(.cancelled))
        } else if !inbox.isEmpty {
          continuation.resume(returning: .string(inbox.removeFirst()))
        } else {
          waiter = continuation
        }
      }
    }
  }

  func cancel(with closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
    lock.withLock {
      isCancelled = true
      waiter?.resume(throwing: URLError(.cancelled))
      waiter = nil
    }
  }

  private func deliver(_ text: String) {
    lock.withLock {
      if let waiter {
        self.waiter = nil
        waiter.resume(returning: .string(text))
      } else {
        inbox.append(text)
      }
    }
  }
}

private final class ScriptedSession: WebSocketURLSession, @unchecked Sendable {
  private let lock = NSLock()
  private let script: [String: [Frame]]
  private var made: [(request: URLRequest, socket: ScriptedSocket)] = []

  init(script: [String: [Frame]]) {
    self.script = script
  }

  var sockets: [(request: URLRequest, socket: ScriptedSocket)] { lock.withLock { made } }

  func webSocketTask(with request: URLRequest) -> any WebSocketTask {
    let socket = ScriptedSocket(script: script)
    lock.withLock { made.append((request, socket)) }
    return socket
  }
}

/// A `next` frame carrying `data` for the subscribe it answers.
private func next(_ data: String) -> Frame {
  { id in #"{"id":"\#(id)","type":"next","payload":{"data":\#(data)}}"# }
}

private func complete() -> Frame {
  { id in #"{"id":"\#(id)","type":"complete"}"# }
}

private func graphQLError(_ message: String) -> Frame {
  { id in #"{"id":"\#(id)","type":"error","payload":[{"message":"\#(message)"}]}"# }
}

private let cpu47 = next(#"{"systemMetricsCpu":{"__typename":"CpuUtilization","percentTotal":47.5}}"#)
private let memory58 = next(
  #"{"systemMetricsMemory":{"__typename":"MemoryUtilization","percentTotal":57.7,"used":60368560128,"total":67023622144}}"#
)

private func sensor(_ type: String, _ value: Double, unit: String = "CELSIUS") -> String {
  #"{"__typename":"TemperatureSensor","type":"\#(type)","current":{"__typename":"TemperatureReading","value":\#(value),"unit":"\#(unit)"}}"#
}

private func temperature(_ sensors: [String]) -> Frame {
  next(
    #"{"systemMetricsTemperature":{"__typename":"TemperatureMetrics","sensors":[\#(sensors.joined(separator: ","))]}}"#
  )
}

private let server = Server(
  name: "Scripted", url: URL(string: "http://tower.test")!, apiKey: "scripted-key")

/// Reads `count` updates, then stops listening.
private func firstUpdates(
  _ count: Int, from repository: LiveMetricsRepository
) async throws -> [LiveMetricsUpdate] {
  var updates: [LiveMetricsUpdate] = []
  for try await update in repository.liveMetrics() {
    updates.append(update)
    if updates.count == count { break }
  }
  return updates
}

/// Polls `condition` for up to two seconds. The caller `#expect`s the
/// condition afterwards, so a deadline reached is a failure, not a pass.
private func eventually(_ condition: () -> Bool) async throws {
  for _ in 0..<200 where !condition() {
    try await Task.sleep(for: .milliseconds(10))
  }
}

// MARK: - Handshake

@Suite(.timeLimit(.minutes(1)))
struct LiveMetricsRepositoryTests {
  @Test func eachSubscriptionAuthenticatesInConnectionInitOnItsOwnSocket() async throws {
    let session = ScriptedSession(script: ["LiveCpu": [cpu47]])
    let repository = LiveMetricsRepository(server: server, session: session)

    _ = try await firstUpdates(1, from: repository)

    // Three transports, one per subscription.
    #expect(session.sockets.count == 3)
    for (request, socket) in session.sockets {
      #expect(request.url?.absoluteString == "ws://tower.test/graphql")
      #expect(request.value(forHTTPHeaderField: "Sec-WebSocket-Protocol") == "graphql-transport-ws")
      // The server reads the key from the payload, not from a header.
      #expect(request.value(forHTTPHeaderField: "x-api-key") == nil)
      try await eventually { socket.sent.contains { $0["type"] as? String == "connection_init" } }
      let initFrame = socket.sent.first { $0["type"] as? String == "connection_init" }
      let payload = initFrame?["payload"] as? [String: Any]
      #expect(payload?["x-api-key"] as? String == "scripted-key")
    }
  }

  // MARK: - Mapping

  @Test func mapsCpuAndMemoryReadings() async throws {
    let session = ScriptedSession(script: ["LiveCpu": [cpu47], "LiveMemory": [memory58]])
    let repository = LiveMetricsRepository(server: server, session: session)

    let updates = try await firstUpdates(2, from: repository)

    #expect(updates.contains(.cpu(percent: 47.5)))
    #expect(updates.contains(.memory(percent: 57.7, usedBytes: 60_368_560_128, totalBytes: 67_023_622_144)))
  }

  // The shape a 4.37 server sends: CPU cores, plus `CUSTOM` sensors that
  // include a fan at 704 and voltages near zero. Only CPU sensors count.
  @Test func temperatureIsTheHottestCpuSensorAndIgnoresEveryOtherType() async throws {
    let session = ScriptedSession(script: [
      "LiveTemperature": [
        temperature([
          sensor("CPU_CORE", 33), sensor("CPU_PACKAGE", 41), sensor("CPU_CORE", 38),
          sensor("CUSTOM", 704), sensor("MOTHERBOARD", 50), sensor("DISK", 45),
        ])
      ]
    ])
    let repository = LiveMetricsRepository(server: server, session: session)

    let updates = try await firstUpdates(1, from: repository)

    #expect(updates == [.cpuTemperature(TemperatureReading(value: 41, unit: .celsius))])
  }

  @Test func temperatureKeepsTheServersUnit() async throws {
    let session = ScriptedSession(script: [
      "LiveTemperature": [temperature([sensor("CPU_PACKAGE", 105.8, unit: "FAHRENHEIT")])]
    ])
    let repository = LiveMetricsRepository(server: server, session: session)

    let updates = try await firstUpdates(1, from: repository)

    #expect(updates == [.cpuTemperature(TemperatureReading(value: 105.8, unit: .fahrenheit))])
  }

  @Test func noCpuSensorOrNoTemperatureAtAllReadsAsNoReading() async throws {
    let session = ScriptedSession(script: [
      "LiveTemperature": [
        temperature([sensor("CUSTOM", 32.25), sensor("NVME", 40)]),
        next(#"{"systemMetricsTemperature":null}"#),
      ]
    ])
    let repository = LiveMetricsRepository(server: server, session: session)

    let updates = try await firstUpdates(2, from: repository)

    #expect(updates == [.cpuTemperature(nil), .cpuTemperature(nil)])
  }

  // MARK: - Lifetime

  // The issue's stop criterion: leaving the dashboard or backgrounding the
  // app cancels the stream, and that must close every socket.
  @Test func cancellingTheStreamClosesEverySocket() async throws {
    let session = ScriptedSession(script: ["LiveCpu": [cpu47], "LiveMemory": [memory58]])
    let repository = LiveMetricsRepository(server: server, session: session)

    _ = try await firstUpdates(2, from: repository)

    try await eventually { session.sockets.allSatisfy { $0.socket.cancelled } }
    #expect(session.sockets.count == 3)
    #expect(session.sockets.allSatisfy { $0.socket.cancelled })
  }

  // A subscription that fails beside two live ones must not leave its metric
  // dead for the rest of the visit. It ends the whole stream, so the
  // dashboard's retry restarts all three.
  @Test func oneFailingSubscriptionEndsTheStreamAndClosesEverySocket() async throws {
    let session = ScriptedSession(script: [
      "LiveCpu": [graphQLError("Forbidden resource")],
      // Memory and temperature send and then stay open, as live ones do.
      "LiveMemory": [memory58],
      "LiveTemperature": [temperature([sensor("CPU_CORE", 30)])],
    ])
    let repository = LiveMetricsRepository(server: server, session: session)

    var thrown: (any Error)?
    do {
      for try await _ in repository.liveMetrics() {}
    } catch {
      thrown = error
    }

    #expect(thrown != nil)
    #expect(session.sockets.count == 3)
    #expect(session.sockets.allSatisfy { $0.socket.cancelled })
  }

  // A clean `complete` from one subscription ends the stream the same way.
  @Test func oneCompletedSubscriptionEndsTheStreamWithoutAnError() async throws {
    let session = ScriptedSession(script: [
      "LiveCpu": [cpu47, complete()],
      "LiveMemory": [memory58],
    ])
    let repository = LiveMetricsRepository(server: server, session: session)

    for try await _ in repository.liveMetrics() {}

    #expect(session.sockets.allSatisfy { $0.socket.cancelled })
  }

  // MARK: - Endpoint

  @Test func webSocketEndpointSwapsTheScheme() {
    let plain = Server(name: "a", url: URL(string: "http://10.0.0.5")!, apiKey: "k")
    let slashed = Server(name: "b", url: URL(string: "http://tower.local:8080/")!, apiKey: "k")
    let secure = Server(name: "c", url: URL(string: "https://tower.example")!, apiKey: "k")
    #expect(plain.webSocketEndpoint.absoluteString == "ws://10.0.0.5/graphql")
    #expect(slashed.webSocketEndpoint.absoluteString == "ws://tower.local:8080/graphql")
    #expect(secure.webSocketEndpoint.absoluteString == "wss://tower.example/graphql")
  }
}

// MARK: - Live server

// The one check that runs Apollo's real frames over a real `URLSession`
// against a real Unraid server. Opt-in only, in `LiveShareRepositoryTests`'
// `LiveServerCredentials`/`.enabled(if:)` pattern, and reported as skipped
// whenever `UNRAID_URL`/`UNRAID_API_KEY` are not set:
// ```
// set -a; source .env.local; set +a
// cd TowerKit && swift test --filter LiveMetricsLiveServerTests
// ```
// Subscriptions only: nothing here changes the server.

private enum LiveServerCredentials {
  static var server: Server? {
    let environment = ProcessInfo.processInfo.environment
    guard let urlString = environment["UNRAID_URL"], let url = URL(string: urlString),
          let apiKey = environment["UNRAID_API_KEY"], !apiKey.isEmpty
    else { return nil }
    return Server(name: "Live", url: url, apiKey: apiKey)
  }
}

@Suite(.enabled(if: LiveServerCredentials.server != nil), .timeLimit(.minutes(1)))
struct LiveMetricsLiveServerTests {
  // Temperature arrives about 6 s after the subscribe, so this listens until
  // each metric has sent once.
  @Test func eachMetricArrivesFromARealServer() async throws {
    let server = try #require(LiveServerCredentials.server)
    let repository = LiveMetricsRepository(server: server)

    var latest: [LiveMetric: LiveMetricsUpdate] = [:]
    for try await update in repository.liveMetrics() {
      latest[update.metric] = update
      if latest.count == LiveMetric.allCases.count { break }
    }

    for metric in LiveMetric.allCases {
      print("[live-metrics] \(metric): \(latest[metric].map(String.init(describing:)) ?? "none")")
    }
    guard case .cpu(let cpu) = latest[.cpu] else {
      Issue.record("no CPU reading")
      return
    }
    #expect((0...100).contains(cpu))
    guard case .memory(let percent, let used, let total) = latest[.memory] else {
      Issue.record("no memory reading")
      return
    }
    #expect((0...100).contains(percent))
    #expect(total > 0 && used <= total)
    #expect(latest[.cpuTemperature] != nil)
  }
}
