import Foundation
import Testing
import TowerCore
@testable import Tower

/// The shared interactive-search store — sorting, grabbing, and what
/// happens when a grab is refused.
@MainActor
@Suite
struct InteractiveSearchStoreTests {
  private func release(
    _ id: String, size: Int64 = 1_000, age: Double? = nil,
    approved: Bool = true, rejections: [String] = []
  ) -> ArrRelease {
    ArrRelease(
      id: id, title: id, indexer: "Example", indexerID: 1, quality: "WEBDL-1080p",
      sizeBytes: size, downloadProtocol: .usenet,
      publishDate: nil, ageHours: age, isApproved: approved, rejections: rejections)
  }

  private func makeStore(
    _ releases: [ArrRelease],
    grab: @escaping @Sendable (ArrRelease) async throws -> Void = { _ in }
  ) async -> InteractiveSearchStore {
    let store = InteractiveSearchStore(
      scope: .movie(id: 1, title: "Example Film"),
      fetch: { releases },
      grab: grab)
    await store.load()
    return store
  }

  @Test func bestMatchPutsApprovedReleasesFirst() async {
    // The list exists to pick a release from; a rejected one at the top is the
    // one thing it must not do by default.
    let store = await makeStore([
      release("rejected", size: 9_999, approved: false, rejections: ["nope"]),
      release("approved"),
    ])

    #expect(store.releases.map(\.id) == ["approved", "rejected"])
  }

  @Test func bestMatchKeepsTheServicesOrderWithinEachGroup() async {
    // Nothing on a release ranks it better than the *arr already did, so ties
    // stay in the order the service sent them.
    let store = await makeStore([
      release("rejected-a", approved: false),
      release("approved-a"),
      release("rejected-b", approved: false),
      release("approved-b"),
      release("approved-c"),
    ])

    #expect(store.releases.map(\.id) == [
      "approved-a", "approved-b", "approved-c", "rejected-a", "rejected-b",
    ])
  }

  @Test func sortingBySizeAndAge() async {
    let store = await makeStore([
      release("small-old", size: 100, age: 500),
      release("big-new", size: 900, age: 2),
    ])

    store.sort = .size
    #expect(store.releases.first?.id == "big-new")

    store.sort = .age
    #expect(store.releases.first?.id == "big-new", "newest first")
  }

  @Test func everySortOptionGivesItsOwnOrder() async {
    // Two menu items with one ordering is a menu item that does nothing.
    let store = await makeStore([
      release("rejected-big", size: 300, age: 20, approved: false, rejections: ["nope"]),
      release("approved-small-old", size: 100, age: 30),
      release("approved-mid-new", size: 200, age: 5),
    ])

    var orders: [ReleaseSort: [String]] = [:]
    for sort in ReleaseSort.allCases {
      store.sort = sort
      orders[sort] = store.releases.map(\.id)
    }

    for (index, lhs) in ReleaseSort.allCases.enumerated() {
      for rhs in ReleaseSort.allCases.dropFirst(index + 1) {
        #expect(orders[lhs] != orders[rhs], "\(lhs) and \(rhs) give the same order")
      }
    }
  }

  @Test func grabbingCountsAsSuccessAndLeavesTheListAlone() async {
    // A grab is a request to the download client, not an edit to the search
    // results — re-running the search would cost another round of indexer
    // queries for no new information.
    let store = await makeStore([release("a"), release("b")])

    await store.grab(store.releases[0])

    #expect(store.grabCount == 1)
    #expect(store.grabError == nil)
    #expect(store.releases.count == 2)
  }

  @Test func aRefusedGrabSurfacesTheServicesOwnWording() async {
    let store = await makeStore([release("a")]) { _ in
      throw AppError.unknown("Release was rejected by the indexer")
    }

    await store.grab(store.releases[0])

    #expect(store.grabCount == 0)
    #expect(store.grabError?.message.contains("rejected by the indexer") == true)
  }

  @Test func aFailedSearchIsFailedNotEmpty() async {
    // "No releases" and "the search failed" are different answers, and only one
    // of them means try again.
    let store = InteractiveSearchStore(
      scope: .movie(id: 1, title: "Example Film"),
      fetch: { throw AppError.serverUnreachable },
      grab: { _ in })

    await store.load()

    guard case .failed(let error) = store.state else {
      Issue.record("expected .failed, got \(store.state)")
      return
    }
    #expect(error == .serverUnreachable)
  }

  @Test func eachScopeCarriesItsOwnTitle() async {
    // The empty state names what was searched for, from the scope, for a
    // Radarr movie and a Sonarr episode alike.
    let movieScope = InteractiveSearchScope.movie(id: 1, title: "Film")
    let episodeScope = InteractiveSearchScope.episode(id: 2, title: "S01E01 · Pilot")
    #expect(movieScope.title == "Film")
    #expect(episodeScope.title == "S01E01 · Pilot")
  }
}
