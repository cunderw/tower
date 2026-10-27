import Foundation
import Testing
import TowerCore
import TowerData
@testable import Tower

@MainActor
struct ShareStoreTests {
  @Test func loadsShares() async {
    let shares = [Share.stub(id: "1"), Share.stub(id: "2")]
    let store = ShareStore(repository: StubShareRepository(results: [.success(shares)]))
    await store.load()
    #expect(store.state.value == shares)
  }

  @Test func surfacesFailuresAsAppError() async {
    let store = ShareStore(repository: StubShareRepository(results: [.failure(.unauthorized)]))
    await store.load()
    #expect(store.state.error == .unauthorized)
  }

  @Test func refreshKeepsPreviousDataOnFailure() async {
    // `refresh()` uses `mutate`, not `load`, so a transient poll failure 30
    // seconds in doesn't blank a working list.
    let shares = [Share.stub(id: "1")]
    let store = ShareStore(repository: StubShareRepository(results: [
      .success(shares),
      .failure(.serverUnreachable),
    ]))
    await store.load()
    await store.refresh()

    #expect(store.state.value == shares)
    #expect(store.state.error != nil)
  }

  @Test func refreshBeforeAnyLoadPerformsTheInitialLoad() async {
    // A poll can fire before the first load resolves (a tab selected while
    // `.idle`). Falling through to `mutate` there would leave `.actionFailed`
    // with no data to preserve.
    let shares = [Share.stub(id: "1")]
    let store = ShareStore(repository: StubShareRepository(results: [.success(shares)]))

    await store.refresh()

    #expect(store.state.value == shares)
  }

  // MARK: - Search

  @Test func searchFiltersByNameCaseInsensitively() async {
    let store = ShareStore(repository: StubShareRepository(results: [.success([
      Share.stub(id: "1", name: "Appdata"),
      Share.stub(id: "2", name: "downloads"),
    ])]))
    await store.load()

    store.searchText = "appd"

    #expect(store.filteredShares.map(\.id) == ["1"])
  }

  @Test func searchMatchesTheComment() async {
    // Comments are the only distinguishing text some shares have: searching
    // "paperwork" should find the share whose comment reads "scanned
    // paperwork", not only one named `paperwork`.
    let store = ShareStore(repository: StubShareRepository(results: [.success([
      Share.stub(id: "1", name: "scans", comment: "scanned paperwork"),
      Share.stub(id: "2", name: "isos", comment: "ISO images"),
    ])]))
    await store.load()

    store.searchText = "PAPERWORK"

    #expect(store.filteredShares.map(\.id) == ["1"])
  }

  @Test func searchMatchesTheFallbackNameOfAnUnnamedShare() async {
    // `name` is nullable and `displayName` falls back to the share-name half of
    // the id. Search has to see what the row shows, or an unnamed share becomes
    // unfindable.
    let store = ShareStore(repository: StubShareRepository(results: [.success([
      Share.stub(id: "hash:isos", name: nil),
      Share.stub(id: "2", name: "downloads"),
    ])]))
    await store.load()

    store.searchText = "iso"

    #expect(store.filteredShares.map(\.id) == ["hash:isos"])
  }

  @Test func searchIgnoresANilComment() async {
    // The comment match must not crash or match everything when `comment` is nil
    // — most shares on a real server have none.
    let store = ShareStore(repository: StubShareRepository(results: [.success([
      Share.stub(id: "1", name: "appdata", comment: nil),
    ])]))
    await store.load()

    store.searchText = "anything"

    #expect(store.filteredShares.isEmpty)
  }

  @Test func emptySearchReturnsEverything() async {
    let shares = [Share.stub(id: "1"), Share.stub(id: "2")]
    let store = ShareStore(repository: StubShareRepository(results: [.success(shares)]))
    await store.load()

    store.searchText = "   "

    #expect(store.filteredShares == shares)
  }

  @Test func aSearchThatMatchesNothingIsNotTheSameAsAnEmptyServer() async {
    // What lets the view show "no results" instead of "this server has no
    // shares": `state.value` is non-empty even though `filteredShares` is empty.
    let store = ShareStore(repository: StubShareRepository(results: [.success([
      Share.stub(id: "1", name: "appdata"),
    ])]))
    await store.load()

    store.searchText = "nothing matches this"

    #expect(store.filteredShares.isEmpty)
    #expect(store.state.value?.isEmpty == false)
  }

  @Test func filteredSharesIsEmptyBeforeTheFirstLoad() async {
    let store = ShareStore(repository: StubShareRepository(results: []))
    #expect(store.filteredShares.isEmpty)
  }
}

/// `results` is a queue rather than a single fixed outcome — same reasoning as
/// `DockerStoreTests.StubDockerRepository`. No action methods, because
/// `ShareRepositoryProtocol` has none.
private final class StubShareRepository: ShareRepositoryProtocol, @unchecked Sendable {
  enum Result { case success([Share]), failure(AppError) }

  private var results: [Result]

  init(results: [Result] = []) {
    self.results = results
  }

  func shares() async throws -> [Share] {
    precondition(!results.isEmpty, "shares() called more times than results were stubbed")
    switch results.removeFirst() {
    case .success(let shares): return shares
    case .failure(let error): throw error
    }
  }
}

extension Share {
  /// A local fixture — `TowerCoreTests`' helpers live in `TowerKit`'s own test
  /// target and aren't visible from `TowerTests`.
  fileprivate static func stub(
    id: String, name: String? = "share", comment: String? = nil
  ) -> Share {
    Share(
      id: id, name: name, originalName: nil, comment: comment,
      includedDisks: [], excludedDisks: [], isCached: nil, allocator: "highwater",
      splitLevel: nil, floorKilobytes: 0, copyOnWrite: "auto",
      poolUsedKilobytes: 1, poolFreeKilobytes: 1
    )
  }
}
