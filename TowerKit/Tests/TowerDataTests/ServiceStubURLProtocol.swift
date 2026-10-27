import Foundation

/// A `URLProtocol` for the REST service clients: programmable per host, and it
/// records what was actually sent so auth injection and custom headers can be
/// asserted on the wire rather than on the client's own idea of them.
///
/// Keyed by host because `URLProtocol` registration reaches every session using
/// the configuration and tests run concurrently — each test stubs its own
/// placeholder host, as `StubURLProtocol` does for the Apollo side.
final class ServiceStubURLProtocol: URLProtocol, @unchecked Sendable {
  struct Reply: Sendable {
    var status: Int = 200
    var body: Data = Data()
    var headers: [String: String] = ["Content-Type": "application/json"]

    static func json(_ string: String, status: Int = 200) -> Reply {
      Reply(status: status, body: Data(string.utf8))
    }
  }

  /// What the stub should do with a request: answer it, or fail the transport.
  enum Outcome: Sendable {
    case reply(Reply)
    case failure(URLError)
  }

  private static let lock = NSLock()
  nonisolated(unsafe) private static var handlers: [String: @Sendable (URLRequest) -> Outcome] = [:]
  nonisolated(unsafe) private static var recorded: [String: [URLRequest]] = [:]

  static func configuration() -> URLSessionConfiguration {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [ServiceStubURLProtocol.self]
    return configuration
  }

  static func stub(host: String, _ handler: @escaping @Sendable (URLRequest) -> Outcome) {
    lock.withLock {
      handlers[host] = handler
      recorded[host] = []
    }
  }

  /// Convenience for the common case: one canned answer for every request.
  static func stub(host: String, reply: Reply) {
    stub(host: host) { _ in .reply(reply) }
  }

  static func requests(host: String) -> [URLRequest] {
    lock.withLock { recorded[host] ?? [] }
  }

  override class func canInit(with request: URLRequest) -> Bool {
    guard let host = request.url?.host() else { return false }
    return lock.withLock { handlers[host] != nil }
  }

  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    guard let url = request.url, let host = url.host() else { return }
    let handler = ServiceStubURLProtocol.lock.withLock {
      ServiceStubURLProtocol.recorded[host, default: []].append(request)
      return ServiceStubURLProtocol.handlers[host]
    }
    guard let handler else {
      client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
      return
    }
    switch handler(request) {
    case .failure(let error):
      client?.urlProtocol(self, didFailWithError: error)
    case .reply(let reply):
      let response = HTTPURLResponse(
        url: url, statusCode: reply.status, httpVersion: "HTTP/1.1",
        headerFields: reply.headers
      )!
      client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
      client?.urlProtocol(self, didLoad: reply.body)
      client?.urlProtocolDidFinishLoading(self)
    }
  }

  override func stopLoading() {}
}

extension URLRequest {
  /// `URLProtocol` hands back a request whose body has been moved to
  /// `httpBodyStream`, so a test reading `httpBody` alone sees nil for every
  /// POST it just made.
  var recordedBody: Data? {
    if let httpBody { return httpBody }
    guard let stream = httpBodyStream else { return nil }
    stream.open()
    defer { stream.close() }
    var data = Data()
    let size = 4096
    var buffer = [UInt8](repeating: 0, count: size)
    while stream.hasBytesAvailable {
      let read = stream.read(&buffer, maxLength: size)
      if read <= 0 { break }
      data.append(contentsOf: buffer[0..<read])
    }
    return data
  }
}
