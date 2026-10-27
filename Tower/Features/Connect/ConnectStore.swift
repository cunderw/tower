import Foundation
import Observation
import TowerCore
import TowerData

@MainActor
@Observable
final class ConnectStore: LoadingStore {
  var urlText: String = ""
  var apiKey: String = ""
  var state: Loadable<Server> = .idle

  /// The one line `LoadingStore` needs per store — see `LoadTracker`.
  let loads = LoadTracker()

  private let serverStore: any ServerStoring
  private let makeRepository: (Server) -> any SystemRepositoryProtocol

  init(
    serverStore: any ServerStoring,
    makeRepository: @escaping (Server) -> any SystemRepositoryProtocol
  ) {
    self.serverStore = serverStore
    self.makeRepository = makeRepository
  }

  convenience init(serverStore: any ServerStoring = KeychainServerStore()) {
    self.init(serverStore: serverStore) { server in
      LiveSystemRepository(provider: ApolloClientProvider(server: server))
    }
  }

  /// Also gates on `!state.isLoading` — the only thing preventing a
  /// double-tap from racing `KeychainServerStore`'s check-then-act save path.
  var canSubmit: Bool {
    !urlText.trimmed.isEmpty && !apiKey.trimmed.isEmpty && !state.isLoading
  }

  func connect() async {
    guard let url = Self.normalizedURL(from: urlText) else {
      state = .failed(.invalidServerURL)
      return
    }
    let server = Server(name: url.host() ?? "Tower", url: url, apiKey: apiKey.trimmed)

    // `[self]` because `load` takes an escaping closure — it wraps the work
    // in a cancellable `Task`. Everything captured is main-actor
    // isolated, so this is an explicitness requirement rather than a concurrency
    // one.
    await load { [self] in
      let reachable = try await makeRepository(server).testConnection()
      guard reachable else { throw AppError.serverUnreachable }
      try serverStore.save(server)
      return server
    }
  }

  /// Accepts a pasted address, trims whitespace, drops a trailing slash, and
  /// requires an explicit scheme — a bare host silently produces a relative
  /// URL that fails much later with a confusing error.
  static func normalizedURL(from text: String) -> URL? {
    let trimmed = text.trimmed
    guard !trimmed.isEmpty else { return nil }
    var candidate = trimmed
    while candidate.hasSuffix("/") { candidate.removeLast() }
    guard let url = URL(string: candidate),
          let scheme = url.scheme, scheme == "http" || scheme == "https",
          url.host()?.isEmpty == false
    else { return nil }
    return url
  }
}

private extension String {
  var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
