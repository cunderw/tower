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
final class StubURLProtocol: URLProtocol, @unchecked Sendable {
  private static let lock = NSLock()
  nonisolated(unsafe) private static var responses: [URL: Data] = [:]

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

  override class func canInit(with request: URLRequest) -> Bool {
    guard let url = request.url else { return false }
    lock.lock()
    defer { lock.unlock() }
    return responses[url] != nil
  }

  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    guard let url = request.url else { return }
    StubURLProtocol.lock.lock()
    let body = StubURLProtocol.responses[url]
    StubURLProtocol.lock.unlock()
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
