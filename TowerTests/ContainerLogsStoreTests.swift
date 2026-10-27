import Foundation
import Testing
import TowerCore
import TowerData
@testable import Tower

// `ContainerLogsStore`'s own domain-logic surface: the mapping layer
// (`ContainerLogLine.init(from:)`/`ContainerLogs.init(from:)`) is covered by
// `TowerKit`'s `DockerLogsMappingTests`; this file covers the store's
// `hasMore`/`loadMore()` pagination logic instead — genuinely nontrivial,
// since Unraid treats `tail` as a maximum, not an exact count, so "did this
// fetch reach the end of history" has to be inferred from whether the
// response came back shorter than what was asked for.
@MainActor
struct ContainerLogsStoreTests {
  @Test func loadRequestsPageSizeAndKeepsHasMoreTrueWhenTheResponseIsFull() async {
    let repository = StubLogsRepository(results: [.success(makeLines(count: ContainerLogsStore.pageSize))])
    let store = ContainerLogsStore(repository: repository, containerID: "1")

    await store.load()

    #expect(store.state.value?.count == ContainerLogsStore.pageSize)
    #expect(store.hasMore == true)
    #expect(repository.requestedTails == [ContainerLogsStore.pageSize])
  }

  // A response strictly shorter than what was requested is the one reliable
  // "you've reached the start of this container's history" signal `tail`
  // (a maximum) can give.
  @Test func loadSetsHasMoreFalseWhenTheResponseIsShorterThanRequested() async {
    let repository = StubLogsRepository(results: [.success(makeLines(count: 50))])
    let store = ContainerLogsStore(repository: repository, containerID: "1")

    await store.load()

    #expect(store.state.value?.count == 50)
    #expect(store.hasMore == false)
  }

  @Test func loadMoreGrowsTailByPageSizeAndReplacesStateWithTheLargerFetch() async {
    let repository = StubLogsRepository(results: [
      .success(makeLines(count: ContainerLogsStore.pageSize)),
      .success(makeLines(count: ContainerLogsStore.pageSize * 2)),
    ])
    let store = ContainerLogsStore(repository: repository, containerID: "1")
    await store.load()

    await store.loadMore()

    #expect(store.state.value?.count == ContainerLogsStore.pageSize * 2)
    #expect(repository.requestedTails == [ContainerLogsStore.pageSize, ContainerLogsStore.pageSize * 2])
    #expect(store.hasMore == true)
  }

  // The container's entire log history is exactly one page (200 lines):
  // asking for 400 still only returns 200, which must flip `hasMore` to
  // `false` rather than inviting a third, equally fruitless request.
  @Test func loadMoreSetsHasMoreFalseWhenTheServerStopsReturningMoreLines() async {
    let repository = StubLogsRepository(results: [
      .success(makeLines(count: ContainerLogsStore.pageSize)),
      .success(makeLines(count: ContainerLogsStore.pageSize)),
    ])
    let store = ContainerLogsStore(repository: repository, containerID: "1")
    await store.load()

    await store.loadMore()

    #expect(store.state.value?.count == ContainerLogsStore.pageSize)
    #expect(store.hasMore == false)
  }

  @Test func loadMoreIsANoOpOnceHasMoreIsFalse() async {
    let repository = StubLogsRepository(results: [.success(makeLines(count: 50))])
    let store = ContainerLogsStore(repository: repository, containerID: "1")
    await store.load()
    #expect(store.hasMore == false)

    await store.loadMore()

    // No second call reached the repository at all.
    #expect(repository.requestedTails == [ContainerLogsStore.pageSize])
  }

  // `loadMore()` must go through `mutate`, not `load` — a failure 200 lines
  // in must keep those lines on screen and surface the error transiently,
  // never blank a working log view. Mirrors
  // `DockerStoreTests.refreshKeepsPreviousDataOnFailure`.
  @Test func loadMoreFailureKeepsCurrentLinesAndSurfacesTheError() async {
    let repository = StubLogsRepository(results: [
      .success(makeLines(count: ContainerLogsStore.pageSize)),
      .failure(.serverUnreachable),
    ])
    let store = ContainerLogsStore(repository: repository, containerID: "1")
    await store.load()

    await store.loadMore()

    #expect(store.state.value?.count == ContainerLogsStore.pageSize)
    #expect(store.state.error == .serverUnreachable)
  }

  @Test func loadResetsDepthSoARepeatedLoadStartsBackAtOnePage() async {
    let repository = StubLogsRepository(results: [
      .success(makeLines(count: ContainerLogsStore.pageSize)),
      .success(makeLines(count: ContainerLogsStore.pageSize * 2)),
      .success(makeLines(count: ContainerLogsStore.pageSize)),
    ])
    let store = ContainerLogsStore(repository: repository, containerID: "1")
    await store.load()
    await store.loadMore()

    await store.load()

    #expect(repository.requestedTails == [
      ContainerLogsStore.pageSize, ContainerLogsStore.pageSize * 2, ContainerLogsStore.pageSize,
    ])
    #expect(store.state.value?.count == ContainerLogsStore.pageSize)
  }
}

private func makeLines(count: Int) -> [ContainerLogLine] {
  (0..<count).map { ContainerLogLine(timestamp: nil, message: "line \($0)") }
}

/// `results` is a queue rather than a single fixed outcome, same reasoning
/// as `DockerStoreTests.StubDockerRepository`. Only `logs(id:tail:since:)`
/// is ever called by these tests — the other six methods exist solely to
/// satisfy `DockerRepositoryProtocol`.
private final class StubLogsRepository: DockerRepositoryProtocol, @unchecked Sendable {
  enum Result { case success([ContainerLogLine]), failure(AppError) }

  private var results: [Result]
  private(set) var requestedTails: [Int?] = []

  init(results: [Result]) {
    self.results = results
  }

  func containers() async throws -> [Container] { [] }
  func start(id: String) async throws -> ContainerStateUpdate { preconditionFailure("not used") }
  func stop(id: String) async throws -> ContainerStateUpdate { preconditionFailure("not used") }
  func restart(id: String) async throws -> ContainerStateUpdate { preconditionFailure("not used") }
  func pause(id: String) async throws -> ContainerStateUpdate { preconditionFailure("not used") }
  func unpause(id: String) async throws -> ContainerStateUpdate { preconditionFailure("not used") }

  func logs(id: String, tail: Int?, since: String?) async throws -> ContainerLogs {
    requestedTails.append(tail)
    precondition(!results.isEmpty, "logs() called more times than results were stubbed")
    switch results.removeFirst() {
    case .success(let lines): return ContainerLogs(containerId: id, lines: lines, cursor: nil)
    case .failure(let error): throw error
    }
  }
}
