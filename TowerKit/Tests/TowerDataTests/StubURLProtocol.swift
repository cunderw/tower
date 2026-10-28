import Foundation
import TowerData

// A `URLProtocol` that answers stubbed JSON for exact URLs, so a repository's
// error, nil-data, and refusal guards can be exercised end to end through
// Apollo's real `fetch()`/`perform()` without a server.
//
// **Installed per session, not per process.** The only way into
// `URLSession.shared` is `URLProtocol.registerClass`, and that registration is
// process-wide: live for every other test file in the run, and needing
// reference-counted register/unregister bookkeeping to limit the damage. A
// provider takes a `URLSessionConfiguration` instead, so the stub goes in that
// configuration's `protocolClasses` and reaches exactly the one session under
// test — no global state, nothing to unregister, and nothing for a forgotten
// `defer` to leak.
//
// Each test still stubs a unique placeholder host, because `responses` is shared
// across concurrently-running tests.
//
// **Routed by operation name where a test asks for it.** One repository call can
// send several queries to the same endpoint (`dashboard()` sends three), so a
// stub registered with an `operationName` answers only the request whose body
// names that operation. A request with no matching named stub falls back to the
// URL-only stub, which is all most tests register.
final class StubURLProtocol: URLProtocol, @unchecked Sendable {
  private struct OperationKey: Hashable {
    let url: URL
    let operationName: String
  }

  private static let lock = NSLock()
  nonisolated(unsafe) private static var responses: [URL: Data] = [:]
  nonisolated(unsafe) private static var operationResponses: [OperationKey: Data] = [:]
  nonisolated(unsafe) private static var recordedOperationNames: [URL: [String]] = [:]
  nonisolated(unsafe) private static var unansweredOperations: Set<OperationKey> = []

  /// A configuration that routes every request through this stub. Pass it to
  /// `ApolloClientProvider(server:sessionConfiguration:)`.
  static func configuration() -> URLSessionConfiguration {
    let configuration = URLSessionConfiguration.tower
    configuration.protocolClasses = [StubURLProtocol.self]
    return configuration
  }

  static func stub(url: URL, json: String) {
    lock.lock()
    defer { lock.unlock() }
    responses[url] = Data(json.utf8)
  }

  /// Answers `json` only to a request at `url` whose body's `operationName` is
  /// `operationName`.
  static func stub(url: URL, operationName: String, json: String) {
    lock.lock()
    defer { lock.unlock() }
    operationResponses[OperationKey(url: url, operationName: operationName)] = Data(json.utf8)
  }

  /// Never answers a request at `url` whose body's `operationName` is
  /// `operationName`: the request stays in flight until its task is cancelled.
  /// For a test that needs a cancellation to land mid-request.
  static func stubNoAnswer(url: URL, operationName: String) {
    lock.lock()
    defer { lock.unlock() }
    unansweredOperations.insert(OperationKey(url: url, operationName: operationName))
  }

  /// The `operationName` of every request received at `url`, in arrival order.
  /// A request whose body carried none records as an empty string.
  static func operationNames(url: URL) -> [String] {
    lock.lock()
    defer { lock.unlock() }
    return recordedOperationNames[url] ?? []
  }

  override class func canInit(with request: URLRequest) -> Bool {
    guard let url = request.url else { return false }
    lock.lock()
    defer { lock.unlock() }
    return responses[url] != nil
      || operationResponses.keys.contains { $0.url == url }
      || unansweredOperations.contains { $0.url == url }
  }

  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    guard let url = request.url else { return }
    // Read once: a body that arrives as `httpBodyStream` cannot be read twice.
    let operationName = request.recordedBody
      .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
      .flatMap { $0["operationName"] as? String }
    StubURLProtocol.lock.lock()
    StubURLProtocol.recordedOperationNames[url, default: []].append(operationName ?? "")
    let isUnanswered = operationName.map {
      StubURLProtocol.unansweredOperations.contains(OperationKey(url: url, operationName: $0))
    } ?? false
    let body = operationName
      .flatMap { StubURLProtocol.operationResponses[OperationKey(url: url, operationName: $0)] }
      ?? StubURLProtocol.responses[url]
    StubURLProtocol.lock.unlock()
    if isUnanswered { return }
    guard let body else {
      client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
      return
    }
    let response = HTTPURLResponse(
      url: url, statusCode: 200, httpVersion: "HTTP/1.1",
      headerFields: ["Content-Type": "application/json"]
    )!
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: body)
    client?.urlProtocolDidFinishLoading(self)
  }

  override func stopLoading() {}
}
