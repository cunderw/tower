import Foundation
import TowerCore
import TowerData

/// The Docker half of the add-service flow: Tower already has the container
/// list, so setup drops to pasting a key.
///
/// Optional by construction — the add-service form takes `DockerServiceAssist?`
/// and does nothing different when it is `nil`. That is what lets the assist
/// disappear silently rather than degrade the form wherever no container list
/// is available. `RootView` builds one for every server, the demo's included;
/// a `nil` comes from callers that pass none, such as the stores' tests.
struct DockerServiceAssist: Sendable {
  /// The Unraid box's address — the host every candidate is built on.
  let serverURL: URL
  let repository: any DockerRepositoryProtocol

  /// Recognised, running containers as candidates. Never throws: a failed or
  /// unavailable container list means "no suggestions", not an error for
  /// someone who was going to type an address anyway.
  func candidates() async -> [ServiceCandidate] {
    do {
      return ServiceDiscovery.candidates(in: try await repository.containers(), serverURL: serverURL)
    } catch {
      return []
    }
  }
}
