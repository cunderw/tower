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
/// `connection_ack`, and a `subscribe` with the frames its session scripts for
/// that operation. With no frame queued, `receive()` suspends, as a live
/// socket does between readings; a return or a throw there would end the
/// stream. `push(_:)` sends a later reading on an open subscription.
private final class ScriptedSocket: WebSocketTask, @unchecked Sendable {
  private let lock = NSLock()
  private let framesFor: @Sendable (String) -> [Frame]
  private var inbox: [String] = []
  private var waiter: CheckedContinuation<URLSessionWebSocketTask.Message, any Error>?
  private var sentFrames: [[String: Any]] = []
  private var isCancelled = false
  private var subscription: (name: String, id: String)?

  init(framesFor: @escaping @Sendable (String) -> [Frame]) {
    self.framesFor = framesFor
  }

  var sent: [[String: Any]] { lock.withLock { sentFrames } }
  var cancelled: Bool { lock.withLock { isCancelled } }
  /// The operation this socket subscribed to, once it has.
  var operation: String? { lock.withLock { subscription?.name } }

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
      lock.withLock { subscription = (name, id) }
      for makeFrame in framesFor(name) { deliver(makeFrame(id)) }
    default:
      break
    }
  }

  func push(_ frame: Frame) {
    guard let id = lock.withLock({ subscription?.id }) else { return }
    deliver(frame(id))
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

/// Makes one `ScriptedSocket` per transport. `attempts[name][n]` is what the
/// n-th subscribe to `name` receives; the last entry repeats for every later
/// attempt. `script:` is the one-attempt form.
private final class ScriptedSession: WebSocketURLSession, @unchecked Sendable {
  private let lock = NSLock()
  private let attempts: [String: [[Frame]]]
  private var subscribeCounts: [String: Int] = [:]
  private var made: [(request: URLRequest, socket: ScriptedSocket)] = []

  init(attempts: [String: [[Frame]]]) {
    self.attempts = attempts
  }

  convenience init(script: [String: [Frame]]) {
    self.init(attempts: script.mapValues { [$0] })
  }

  var sockets: [(request: URLRequest, socket: ScriptedSocket)] { lock.withLock { made } }

  /// The sockets that subscribed to `operation`, oldest first.
  func sockets(for operation: String) -> [ScriptedSocket] {
    sockets.map(\.socket).filter { $0.operation == operation }
  }

  func webSocketTask(with request: URLRequest) -> any WebSocketTask {
    let socket = ScriptedSocket { [weak self] name in self?.frames(for: name) ?? [] }
    lock.withLock { made.append((request, socket)) }
    return socket
  }

  private func frames(for name: String) -> [Frame] {
    lock.withLock {
      let attempt = subscribeCounts[name, default: 0]
      subscribeCounts[name] = attempt + 1
      guard let scripted = attempts[name], !scripted.isEmpty else { return [] }
      return scripted[min(attempt, scripted.count - 1)]
    }
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

private let memory61 = next(
  #"{"systemMetricsMemory":{"__typename":"MemoryUtilization","percentTotal":61.0,"used":40884409507,"total":67023622144}}"#
)

/// What a listening task has received, readable while it still listens.
private final class Received: @unchecked Sendable {
  private let lock = NSLock()
  private var all: [LiveMetricsUpdate] = []
  private var didEnd = false

  var updates: [LiveMetricsUpdate] { lock.withLock { all } }
  var ended: Bool { lock.withLock { didEnd } }

  func count(of metric: LiveMetric) -> Int {
    lock.withLock { all.filter { $0.metric == metric }.count }
  }

  /// Reads `stream` to its end, then marks the end, error or not.
  func drain(_ stream: AsyncThrowingStream<LiveMetricsUpdate, any Error>) async {
    do {
      for try await update in stream { lock.withLock { all.append(update) } }
    } catch {}
    lock.withLock { didEnd = true }
  }
}

/// A retry interval the test ends by hand. Each `wait()` lasts until the test
/// calls `release()` once for it, in order. It polls with `Task.sleep`, so a
/// cancelled wait throws, as the real one does.
private final class RetryClock: @unchecked Sendable {
  private let lock = NSLock()
  private var started = 0
  private var released = 0

  var waits: Int { lock.withLock { started } }

  func release() { lock.withLock { released += 1 } }

  func wait() async throws {
    let index = lock.withLock {
      started += 1
      return started - 1
    }
    while lock.withLock({ index >= released }) {
      try await Task.sleep(for: .milliseconds(5))
    }
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

  // MARK: - Per-subscription retry

  // The older-server case: a server whose API lacks one of the three
  // subscriptions fails it at once, every time. The other two must keep
  // sending, on the sockets they opened, for as long as the dashboard listens.
  @Test func aSubscriptionTheServerLacksLeavesTheOtherTwoLive() async throws {
    let session = ScriptedSession(script: [
      "LiveCpu": [graphQLError(#"Cannot query field \"systemMetricsCpu\" on type \"Subscription\"."#)],
      "LiveMemory": [memory58],
      "LiveTemperature": [temperature([sensor("CPU_CORE", 30)])],
    ])
    let repository = LiveMetricsRepository(
      server: server, session: session, retryAfter: .seconds(30),
      sleep: { _ in try await Task.sleep(for: .milliseconds(5)) }
    )
    let received = Received()
    let listening = Task { await received.drain(repository.liveMetrics()) }

    // CPU fails and retries at least twice.
    try await eventually { session.sockets(for: "LiveCpu").count >= 3 || received.ended }
    // Memory still delivers a new reading after those failures.
    session.sockets(for: "LiveMemory").first?.push(memory61)
    try await eventually { received.count(of: .memory) >= 2 || received.ended }

    #expect(!received.ended, "one failing subscription ended the stream")
    #expect(session.sockets(for: "LiveCpu").count >= 3)
    #expect(session.sockets(for: "LiveMemory").count == 1)
    #expect(session.sockets(for: "LiveTemperature").count == 1)
    #expect(session.sockets(for: "LiveMemory").allSatisfy { !$0.cancelled })
    #expect(session.sockets(for: "LiveTemperature").allSatisfy { !$0.cancelled })
    #expect(received.count(of: .memory) >= 2)
    #expect(received.count(of: .cpuTemperature) >= 1)
    #expect(received.count(of: .cpu) == 0)

    listening.cancel()
    await listening.value
    try await eventually { session.sockets.allSatisfy { $0.socket.cancelled } }
    #expect(session.sockets.allSatisfy { $0.socket.cancelled })
  }

  @Test func aFailedSubscriptionRestartsAfterOneIntervalWhileTheOthersRun() async throws {
    let clock = RetryClock()
    let session = ScriptedSession(attempts: [
      "LiveCpu": [[graphQLError("Temporarily unavailable")], [cpu47]],
      "LiveMemory": [[memory58]],
    ])
    let repository = LiveMetricsRepository(
      server: server, session: session, retryAfter: .seconds(30),
      sleep: { _ in try await clock.wait() }
    )
    let received = Received()
    let listening = Task { await received.drain(repository.liveMetrics()) }

    try await eventually { clock.waits == 1 && received.count(of: .memory) == 1 }
    // Waiting out the interval: no second CPU subscribe yet.
    #expect(clock.waits == 1)
    #expect(session.sockets(for: "LiveCpu").count == 1)
    #expect(received.count(of: .memory) == 1)

    clock.release()
    try await eventually { received.count(of: .cpu) == 1 }
    #expect(received.updates.contains(.cpu(percent: 47.5)))
    #expect(session.sockets(for: "LiveCpu").count == 2)
    #expect(session.sockets(for: "LiveMemory").count == 1)
    #expect(session.sockets(for: "LiveMemory").allSatisfy { !$0.cancelled })
    #expect(!received.ended)

    listening.cancel()
    await listening.value
    try await eventually { session.sockets.allSatisfy { $0.socket.cancelled } }
    #expect(session.sockets.allSatisfy { $0.socket.cancelled })
  }

  // Leaving the tab during a subscription's retry wait must not wait it out.
  @Test func cancellingDuringARetryWaitClosesEverySocketAtOnce() async throws {
    let session = ScriptedSession(script: [
      "LiveCpu": [graphQLError("Temporarily unavailable")],
      "LiveMemory": [memory58],
    ])
    // The real `Task.sleep`, for an hour: only cancellation can end it.
    let repository = LiveMetricsRepository(
      server: server, session: session, retryAfter: .seconds(3_600),
      sleep: { try await Task.sleep(for: $0) }
    )
    let received = Received()
    let listening = Task { await received.drain(repository.liveMetrics()) }
    try await eventually {
      received.count(of: .memory) == 1
        && session.sockets(for: "LiveCpu").first?.cancelled == true
    }

    listening.cancel()
    await listening.value

    try await eventually { session.sockets.allSatisfy { $0.socket.cancelled } }
    #expect(session.sockets.allSatisfy { $0.socket.cancelled })
    #expect(session.sockets(for: "LiveCpu").count == 1)
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
