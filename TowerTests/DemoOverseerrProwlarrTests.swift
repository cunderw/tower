import Foundation
import Testing
import TowerCore
import TowerData

@testable import Tower

/// Demo mode's Overseerr and Prowlarr, including the request, search and issue
/// actions checked in demo mode.
@MainActor
struct DemoOverseerrProwlarrTests {
  private func makeOverseerr() -> (DemoOverseerrRepository, DemoOverseerrServer) {
    let server = DemoOverseerrServer()
    let instance = DemoServices.instances.first { $0.kind == .overseerr }!
    return (DemoOverseerrRepository(instance: instance, server: server), server)
  }

  private func makeProwlarr() -> (DemoProwlarrRepository, DemoProwlarrServer) {
    let server = DemoProwlarrServer()
    let instance = DemoServices.instances.first { $0.kind == .prowlarr }!
    return (DemoProwlarrRepository(instance: instance, server: server), server)
  }

  // MARK: - Overseerr's dataset

  @Test func theDemoHasSomethingToApproveAndSomeHistory() async throws {
    // The demo needs a pending request, approved history, and an open issue.
    let (overseerr, _) = makeOverseerr()

    let all = try await overseerr.requests(filter: .all, page: 1).requests
    #expect(all.contains(where: { $0.status == .pending }))
    #expect(all.contains(where: { $0.status == .approved }))
    #expect(all.contains(where: { $0.status == .declined }))
    #expect(all.contains(where: { $0.mediaStatus == .available }))
    #expect(all.contains(where: { $0.mediaType == .tv && !$0.seasons.isEmpty }))

    let issues = try await overseerr.issues(includeResolved: false)
    #expect(issues.contains(where: { $0.status == .open }))
  }

  @Test func thePendingFilterHasEnoughToWorkThrough() async throws {
    let (overseerr, _) = makeOverseerr()

    let pending = try await overseerr.requests(filter: .pending, page: 1)

    #expect(pending.requests.count >= 2)
    #expect(pending.requests.allSatisfy { $0.status == .pending })
  }

  // MARK: - Approving and declining requests

  @Test func approvingMovesARequestOutOfPendingInDemoMode() async throws {
    let (overseerr, _) = makeOverseerr()
    let pendingNow = try await overseerr.requests(filter: .pending, page: 1).requests
    let target = try #require(pendingNow.first)

    try await overseerr.approve(requestID: target.id)

    let pending = try await overseerr.requests(filter: .pending, page: 1).requests
    #expect(
      !pending.contains(where: { $0.id == target.id }),
      "the approved request is still pending")
    let updated = try await overseerr.request(id: target.id)
    #expect(updated.status == .approved)
    // Approving hands it to the *arr, so the media status moves too — a demo
    // where only the badge changed would teach the wrong thing.
    #expect(updated.mediaStatus == .processing)
  }

  @Test func decliningSticksAndIsVisibleUnderItsOwnFilter() async throws {
    let (overseerr, _) = makeOverseerr()
    let pendingNow = try await overseerr.requests(filter: .pending, page: 1).requests
    let target = try #require(pendingNow.first)

    try await overseerr.decline(requestID: target.id)

    let declinedRequest = try await overseerr.request(id: target.id)
    #expect(declinedRequest.status == .declined)
    let declined = try await overseerr.requests(filter: .declined, page: 1).requests
    #expect(declined.contains(where: { $0.id == target.id }))
  }

  // MARK: - Searching and requesting

  @Test func aNewRequestAppearsInTheRequestsListInDemoMode() async throws {
    let (overseerr, _) = makeOverseerr()
    let before = try await overseerr.requests(filter: .all, page: 1).totalResults
    let winterResults = try await overseerr.search(term: "winter")
    let candidate = try #require(winterResults.first { !$0.isAlreadyInLibrary })

    _ = try await overseerr.submit(
      SubmitRequest(mediaType: candidate.mediaType, mediaID: candidate.id))

    let after = try await overseerr.requests(filter: .all, page: 1)
    #expect(after.totalResults == before + 1)
    #expect(after.requests.contains(where: { $0.title == candidate.title }))
    // It lands as pending, so it is immediately approvable — which is the
    // whole demo path.
    #expect(after.requests.first { $0.title == candidate.title }?.status == .pending)
  }

  @Test func searchOffersSomethingRequestableAndSomethingAlreadyAvailable() async throws {
    // Both states have to be reachable, or the already-in-library treatment is
    // undemonstrable.
    let (overseerr, _) = makeOverseerr()

    let results = try await overseerr.search(term: "")

    #expect(results.contains(where: { !$0.isAlreadyInLibrary }))
    #expect(results.contains(where: { $0.isAlreadyInLibrary }))
  }

  @Test func aTVRequestCarriesItsSeasonsIntoTheDemoList() async throws {
    let (overseerr, _) = makeOverseerr()
    let coastalResults = try await overseerr.search(term: "coastal")
    let series = try #require(coastalResults.first)
    let seriesSeasons = try await overseerr.seasons(tmdbID: series.id)
    #expect(seriesSeasons.count == 3)

    _ = try await overseerr.submit(
      SubmitRequest(mediaType: .tv, mediaID: series.id, seasons: [2, 3]))

    let allAfterSubmit = try await overseerr.requests(filter: .all, page: 1).requests
    let created = try #require(allAfterSubmit.first { $0.title == series.title })
    #expect(created.seasons == [2, 3])
  }

  // MARK: - Issues

  @Test func aCommentPostsAndAppearsInTheThreadInDemoMode() async throws {
    let (overseerr, _) = makeOverseerr()
    let openIssues = try await overseerr.issues(includeResolved: false)
    let issue = try #require(openIssues.first)
    let before = issue.comments.count

    try await overseerr.comment(issueID: issue.id, message: "Still happening.")

    let allIssues = try await overseerr.issues(includeResolved: true)
    let updated = try #require(allIssues.first { $0.id == issue.id })
    #expect(updated.comments.count == before + 1)
    #expect(updated.comments.last?.message == "Still happening.")
    // The server resolves the author, which is what the store's re-read exists
    // to pick up.
    #expect(updated.comments.last?.author == "You")
  }

  @Test func resolvingAnIssueIsReversibleInDemoMode() async throws {
    let (overseerr, _) = makeOverseerr()
    let openBefore = try await overseerr.issues(includeResolved: false)
    let issue = try #require(openBefore.first)

    try await overseerr.setIssueResolved(true, issueID: issue.id)
    let openAfterResolve = try await overseerr.issues(includeResolved: false)
    #expect(openAfterResolve.isEmpty)
    let allAfterResolve = try await overseerr.issues(includeResolved: true)
    #expect(allAfterResolve.first { $0.id == issue.id }?.status == .resolved)

    try await overseerr.setIssueResolved(false, issueID: issue.id)
    let reopened = try await overseerr.issues(includeResolved: false)
    #expect(reopened.contains(where: { $0.id == issue.id }))
  }

  // MARK: - Prowlarr's dataset

  @Test func theDemoHasBothHealthyAndFailingIndexers() async throws {
    let (prowlarr, _) = makeProwlarr()

    let indexers = try await prowlarr.indexers()

    #expect(indexers.count >= 3)
    #expect(indexers.contains(where: { $0.isFailing }))
    #expect(indexers.contains(where: { !$0.isFailing && $0.isEnabled }))
    #expect(
      indexers.contains(where: { !$0.isEnabled }),
      "no disabled indexer to contrast against")
  }

  @Test func theFailingIndexerAlsoFailsItsTestSoTheTwoStatesAgree() async throws {
    let (prowlarr, _) = makeProwlarr()
    let indexers = try await prowlarr.indexers()
    let failing = try #require(indexers.first(where: { $0.isFailing }))
    let healthy = try #require(indexers.first { !$0.isFailing && $0.isEnabled })

    let failingResult = try await prowlarr.test(indexerID: failing.id)
    let healthyResult = try await prowlarr.test(indexerID: healthy.id)
    #expect(failingResult.isSuccess == false)
    #expect(healthyResult.isSuccess)
  }

  @Test func togglingAnIndexerSticks() async throws {
    let (prowlarr, _) = makeProwlarr()
    let enabledNow = try await prowlarr.indexers()
    let target = try #require(enabledNow.first { $0.isEnabled })

    try await prowlarr.setEnabled(false, indexerID: target.id)

    let after = try await prowlarr.indexers()
    #expect(after.first { $0.id == target.id }?.isEnabled == false)
  }

  @Test func theDefinitionsCoverEverySupportedFieldTypeAndTheFallback() async throws {
    // The add-indexer form can only be walked in the demo if the field types
    // are here — including one the renderer can't draw, so the fallback state
    // is reachable.
    let (prowlarr, _) = makeProwlarr()

    let schemas = try await prowlarr.schemas()

    let kinds = Set(schemas.flatMap { $0.fields.map(\.kind) })
    #expect(kinds.isSuperset(of: [.textbox, .password, .number, .checkbox, .select]))
    #expect(kinds.contains(.unknown), "no unrenderable field to demo the fallback")
  }

  @Test func addingAnIndexerPutsItInTheDemoList() async throws {
    let (prowlarr, _) = makeProwlarr()
    let publicSchemas = try await prowlarr.schemas()
    let schema = try #require(publicSchemas.first { $0.definitionName == "ExamplePublic" })
    let before = try await prowlarr.indexers().count

    let saved = try await prowlarr.save(IndexerDraft(schema: schema))

    let after = try await prowlarr.indexers()
    #expect(after.count == before + 1)
    #expect(after.contains(where: { $0.id == saved.id }))
  }

  @Test func testBeforeSaveFailsWithoutCredentialsAndPassesWithThem() async throws {
    // Which is what makes test-before-save worth demonstrating at all.
    let (prowlarr, _) = makeProwlarr()
    let privateSchemas = try await prowlarr.schemas()
    let schema = try #require(privateSchemas.first { $0.definitionName == "ExamplePrivate" })
    var draft = IndexerDraft(schema: schema)

    let withoutCredentials = try await prowlarr.test(draft)
    #expect(withoutCredentials.isSuccess == false)

    draft.fields = draft.fields.map { field in
      guard field.kind == .password else { return field }
      var field = field
      field.value = .text("hunter2")
      return field
    }
    let withCredentials = try await prowlarr.test(draft)
    #expect(withCredentials.isSuccess)
  }

  // MARK: - Isolation and hygiene

  @Test func reEnteringTheDemoStartsFromTheSeedAgain() async throws {
    let (first, _) = makeOverseerr()
    let firstPending = try await first.requests(filter: .pending, page: 1).requests
    let target = try #require(firstPending.first)
    try await first.approve(requestID: target.id)
    let approved = try await first.request(id: target.id)
    #expect(approved.status == .approved)

    let (second, _) = makeOverseerr()
    let fresh = try await second.request(id: target.id)
    #expect(fresh.status == .pending)
  }

  @Test func everyDemoProwlarrURLIsAnInvalidHost() async throws {
    // Same rule as every other demo fixture: .invalid hosts only.
    let (prowlarr, _) = makeProwlarr()
    let indexers = try await prowlarr.indexers()
    let urls = indexers.flatMap { $0.fields.map(\.value.stringValue) }
      .filter { $0.hasPrefix("http") }

    #expect(!urls.isEmpty)
    #expect(urls.allSatisfy { $0.contains(".invalid") })

    let schemas = try await prowlarr.schemas()
    #expect(schemas.flatMap(\.indexerURLs).allSatisfy { $0.contains(".invalid") })
  }

  @Test func theWholeOverseerrProwlarrDemoStackIsReachableFromTheEnvironment() async throws {
    // The factory has to actually return these, or none of the above is
    // reachable from the app.
    let environment = AppEnvironment.demo
    let overseerr = DemoServices.instances.first { $0.kind == .overseerr }!
    let prowlarr = DemoServices.instances.first { $0.kind == .prowlarr }!

    #expect(
      environment.makeServiceRepository(overseerr) as? any OverseerrRepositoryProtocol != nil)
    #expect(
      environment.makeServiceRepository(prowlarr) as? any ProwlarrRepositoryProtocol != nil)
  }
}
