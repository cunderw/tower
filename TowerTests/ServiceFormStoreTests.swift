import Foundation
import Testing
import TowerCore
import TowerData
@testable import Tower

/// The add-service form's rules, driven without SwiftUI.
@MainActor
@Suite
struct ServiceFormStoreTests {
  private func makeStore(
    directory: ServiceDirectory = .inMemory(),
    status: ServiceStatus = .reachable(version: "1.2.3")
  ) -> ServiceFormStore {
    ServiceFormStore(directory: directory, checker: StaticServiceStatusChecker(status))
  }

  private func fill(_ store: ServiceFormStore, kind: ServiceKind = .radarr) {
    store.kind = kind
    store.urlText = "http://192.0.2.1:7878"
    switch kind.credentialStyle {
    case .apiKey:
      store.apiKey = "k3y"
    case .usernamePassword:
      store.username = "admin"
      store.password = "hunter2"
    }
  }

  // MARK: - Validation

  @Test func aFreshFormCannotBeSaved() {
    #expect(!makeStore().canSubmit)
  }

  @Test func anAddressWithoutASchemeIsRejected() {
    let store = makeStore()
    fill(store)
    store.urlText = "192.0.2.1:7878"
    #expect(store.normalizedURL == nil)
    #expect(!store.canSubmit)
    #expect(store.validationMessage?.contains("http://") == true)
  }

  @Test func theValidationMessageNamesTheFieldThatIsMissing() {
    let store = makeStore()
    store.urlText = "http://192.0.2.1:7878"
    // API key still empty.
    #expect(store.validationMessage?.contains("API key") == true)

    // A download client has nothing left to require, so the form is
    // complete the moment the kind changes.
    store.kind = .nzbget
    #expect(store.validationMessage == nil)
  }

  // MARK: - Services that need no credentials

  @Test(arguments: [ServiceKind.nzbget])
  func aDownloadClientIsSubmittableWithNoCredentials(kind: ServiceKind) {
    // NZBGet with no `ControlUsername`/`ControlPassword` serves
    // unauthenticated. Requiring a username and password would make it
    // unaddable outright — Test and Save would both be dead with no way to proceed.
    let store = makeStore()
    store.kind = kind
    store.urlText = "http://192.0.2.1:8080"

    #expect(store.username.isEmpty)
    #expect(store.password.isEmpty)
    #expect(store.canSubmit)
    #expect(store.validationMessage == nil)
  }

  @Test(arguments: [ServiceKind.nzbget])
  func aCredentiallessDownloadClientSavesAnEmptyPair(kind: ServiceKind) {
    let directory = ServiceDirectory.inMemory()
    let store = makeStore(directory: directory)
    store.kind = kind
    store.urlText = "http://192.0.2.1:8080"

    let saved = store.save()

    #expect(saved?.credentials == .usernamePassword(username: "", password: ""))
  }

  @Test func aHalfFilledCredentialPairIsSavedAsTyped() {
    // Not normalised to blank: the service is the authority on whether a
    // username with no password is enough, and dropping it would silently
    // discard what the user typed.
    let store = makeStore()
    store.kind = .nzbget
    store.urlText = "http://192.0.2.1:6789"
    store.username = "nzb"

    #expect(store.canSubmit)
    #expect(store.save()?.credentials == .usernamePassword(username: "nzb", password: ""))
  }

  @Test(arguments: [ServiceKind.radarr, .sonarr, .lidarr, .prowlarr, .bazarr, .overseerr, .tautulli])
  func anAPIKeyServiceStillRequiresItsKey(kind: ServiceKind) {
    // The other half of the rule: an *arr genuinely cannot answer without a
    // key, so relaxing the download clients must not relax these.
    let store = makeStore()
    store.kind = kind
    store.urlText = "http://192.0.2.1:7878"

    #expect(!store.canSubmit)
    #expect(store.validationMessage?.contains("API key") == true)
  }

  @Test func aCompleteFormCanBeSaved() {
    let store = makeStore()
    fill(store)
    #expect(store.canSubmit)
    #expect(store.validationMessage == nil)
  }

  // MARK: - The kind drives the credential fields

  @Test func changingTheKindClearsCredentialsTypedForThePreviousOne() {
    // Otherwise a password typed for NZBGet rides along on a Radarr record
    // that has no use for it — a credential stored somewhere the user never
    // meant to put it.
    let store = makeStore()
    fill(store, kind: .nzbget)
    #expect(store.canSubmit)

    store.kind = .radarr

    #expect(store.username.isEmpty)
    #expect(store.password.isEmpty)
    #expect(!store.canSubmit, "the form must not stay submittable across a credential-shape change")
  }

  @Test func theNameFollowsTheKindUntilTheUserTypesOne() {
    let store = makeStore()
    #expect(store.name == "Radarr")

    store.kind = .sonarr
    #expect(store.name == "Sonarr")

    store.name = "Sonarr 4K"
    store.kind = .lidarr
    #expect(store.name == "Sonarr 4K", "a name the user typed must survive a kind change")
  }

  @Test(arguments: ServiceKind.allCases)
  func everyKindSavesTheCredentialShapeItsStyleDeclares(kind: ServiceKind) {
    let directory = ServiceDirectory.inMemory()
    let store = makeStore(directory: directory)
    fill(store, kind: kind)

    let saved = store.save()

    switch kind.credentialStyle {
    case .apiKey:
      #expect(saved?.credentials == .apiKey("k3y"))
    case .usernamePassword:
      #expect(saved?.credentials == .usernamePassword(username: "admin", password: "hunter2"))
    }
  }

  // MARK: - Test connection

  @Test func testReportsAReachableService() async {
    let store = makeStore(status: .reachable(version: "5.14"))
    fill(store)
    await store.test()
    #expect(store.testResult == .reachable(version: "5.14"))
    #expect(store.testResult?.testHeadline.contains("5.14") == true)
  }

  @Test func aRejectedKeyAndAnUnreachableHostProduceDifferentCopy() async {
    // Asserted on the strings a user reads.
    let rejected = makeStore(status: .unauthorized)
    fill(rejected)
    await rejected.test()

    let down = makeStore(status: .unreachable(.serverUnreachable))
    fill(down)
    await down.test()

    #expect(rejected.testResult?.testHeadline == AppError.unauthorized.message)
    #expect(down.testResult?.testHeadline == AppError.serverUnreachable.message)
    #expect(rejected.testResult?.testHeadline != down.testResult?.testHeadline)
    #expect(rejected.testResult?.testDetail != down.testResult?.testDetail)
  }

  @Test func testingAnIncompleteFormDoesNothing() async {
    let store = makeStore()
    store.urlText = "http://192.0.2.1:7878"  // no credentials
    await store.test()
    #expect(store.testResult == nil)
  }

  @Test func editingAnInputDiscardsTheOldResult() async {
    // A green "Connected" left over from the previous address is worse than no
    // result at all — it is a claim about a server the user is no longer
    // pointing at.
    let store = makeStore()
    fill(store)
    await store.test()
    #expect(store.testResult != nil)

    store.inputChanged()

    #expect(store.testResult == nil)
  }

  // MARK: - Saving

  @Test func savingWritesToTheDirectory() {
    let directory = ServiceDirectory.inMemory()
    let store = makeStore(directory: directory)
    fill(store)
    store.name = "Radarr 4K"

    let saved = store.save()

    #expect(saved?.name == "Radarr 4K")
    #expect(try! directory.instances().map(\.name) == ["Radarr 4K"])
  }

  @Test func aSecondInstanceOfTheSameKindIsSavedAlongsideTheFirst() {
    let directory = ServiceDirectory.inMemory()
    for name in ["Radarr", "Radarr 4K"] {
      let store = makeStore(directory: directory)
      fill(store)
      store.name = name
      store.save()
    }
    #expect(try! directory.instances().map(\.name) == ["Radarr", "Radarr 4K"])
  }

  @Test func blankHeaderRowsAreNotSaved() {
    let store = makeStore()
    fill(store)
    store.addHeader()
    store.customHeaders[0].field = "CF-Access-Client-Id"
    store.customHeaders[0].value = "id"
    store.addHeader()  // left empty

    #expect(store.save()?.customHeaders == ["CF-Access-Client-Id": "id"])
  }

  @Test func surroundingWhitespaceIsTrimmedFromTheThingsThatBreakOnIt() {
    let store = makeStore()
    store.kind = .radarr
    store.name = "  Radarr 4K  "
    store.urlText = "  http://192.0.2.1:7878/  "
    store.apiKey = " k3y "

    let saved = store.save()

    #expect(saved?.name == "Radarr 4K")
    #expect(saved?.baseURL.absoluteString == "http://192.0.2.1:7878")
    #expect(saved?.credentials == .apiKey("k3y"))
  }
}
