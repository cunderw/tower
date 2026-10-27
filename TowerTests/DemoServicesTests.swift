import Foundation
import Testing
import TowerCore
@testable import Tower

/// The demo service stack — what an App Store reviewer sees on the Services tab.
@MainActor
struct DemoServicesTests {
  @Test func everyKindIsRepresented() {
    // A reviewer with no Radarr can only judge the Services tab by what the
    // demo shows them; a kind missing here is a kind a reviewer never sees
    // working.
    let kinds = Set(DemoServices.instances.map(\.kind))
    #expect(kinds == Set(ServiceKind.allCases))
  }

  @Test func theStackIncludesASecondInstanceOfOneKind() {
    // Multi-instance is the reason this data model exists; a demo with exactly
    // one of everything never shows it.
    let radarrs = DemoServices.instances.filter { $0.kind == .radarr }
    #expect(radarrs.count == 2)
    #expect(Set(radarrs.map(\.name)).count == 2)
    #expect(Set(radarrs.map(\.baseURL)).count == 2)
  }

  @Test func instanceIdsAreUniqueAndStable() {
    // Stable ids keep a reviewer's selected row from moving under them when the
    // demo environment is rebuilt on re-entry.
    #expect(Set(DemoServices.instances.map(\.id)).count == DemoServices.instances.count)
    #expect(DemoServices.instances.map(\.id) == DemoServices.instances.map(\.id))
  }

  @Test func everyInstanceIsEnabledAndAddressedOnTheDocumentationRange() {
    // Nothing here may name a real host: a screenshot of this screen ships.
    for instance in DemoServices.instances {
      #expect(instance.isEnabled)
      #expect(instance.baseURL.host() == "192.0.2.10", "demo instance \(instance.name) is off TEST-NET-1")
      #expect(instance.baseURL.port != nil)
    }
  }

  @Test func noDemoCredentialLooksLikeARealOne() {
    for instance in DemoServices.instances {
      switch instance.credentials {
      case .apiKey(let key):
        #expect(key.contains("demo"), "\(instance.name) carries a key that doesn't say it is fake")
      case .usernamePassword(let user, let password):
        #expect(user == "demo")
        #expect(password.contains("demo"))
      }
    }
  }

  @Test func credentialsMatchEachKindsStyle() {
    for instance in DemoServices.instances {
      switch (instance.kind.credentialStyle, instance.credentials) {
      case (.apiKey, .apiKey), (.usernamePassword, .usernamePassword):
        break
      default:
        Issue.record("\(instance.name) has credentials of the wrong shape for its kind")
      }
    }
  }

  @Test func theDirectoryReturnsTheWholeStack() async throws {
    let directory = DemoServices.directory()
    #expect(try directory.instances().count == DemoServices.instances.count)
  }

  @Test func theCheckerAnswersEveryInstanceWithoutANetworkCall() async {
    // Latency is simulated, not real: nothing here has an address that routes.
    let checker = DemoServiceStatusChecker()
    var statuses: [ServiceStatus] = []
    for instance in DemoServices.instances {
      statuses.append(await checker.status(for: instance))
    }

    #expect(statuses.count == DemoServices.instances.count)
    #expect(statuses.contains { $0.isReachable })
    // One service is down on purpose — a hub of nine identical green rows never
    // shows a reviewer what the badge means.
    #expect(statuses.contains { $0.isProblem })
  }
}
