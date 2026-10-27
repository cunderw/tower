import Foundation
import Testing
import TowerCore
import TowerData
@testable import Tower

@MainActor
struct LogFileStoreTests {
  @Test func loadsFiles() async {
    let files = [LogFile.stub(name: "syslog"), LogFile.stub(name: "docker.log")]
    let store = LogFileStore(repository: StubLogRepository(files: [.success(files)]))
    await store.load()
    #expect(store.state.value == files)
  }

  @Test func refreshKeepsPreviousDataOnFailure() async {
    let files = [LogFile.stub(name: "syslog")]
    let store = LogFileStore(repository: StubLogRepository(files: [
      .success(files), .failure(.serverUnreachable),
    ]))
    await store.load()
    await store.refresh()

    #expect(store.state.value == files)
    #expect(store.state.error != nil)
  }
}

@MainActor
struct LogViewerStoreTests {
  @Test func firstLoadRequestsABoundedWindowRatherThanTheWholeFile() async {
    // syslog grows without limit and `docker.log` can run to tens of KB, so an
    // unbounded first request is the one thing this screen must not do.
    let repository = StubLogRepository(contents: [.success(.stub(lines: 200, totalLines: 900))])
    let store = LogViewerStore(repository: repository, file: .stub(name: "docker.log"))

    await store.load()

    #expect(repository.requestedLines == [LogViewerStore.initialLines])
    #expect(store.state.value?.isTruncated == true)
  }

  @Test func loadMoreMultipliesTheWindowRatherThanAddingAPage() async {
    // The API has no cursor: `lines` counts back from the end, so reaching further
    // means re-requesting a bigger tail and re-downloading what's already shown.
    // Multiplying keeps round trips logarithmic in how far back someone scrolls.
    let repository = StubLogRepository(contents: [
      .success(.stub(lines: 200, totalLines: 900)),
      .success(.stub(lines: 800, totalLines: 900)),
    ])
    let store = LogViewerStore(repository: repository, file: .stub(name: "docker.log"))
    await store.load()

    await store.loadMore()

    #expect(repository.requestedLines == [200, 800])
    #expect(store.requestedLines == 800)
    #expect(store.state.value?.lines.count == 800)
  }

  @Test func loadMoreDoesNothingWhenTheWholeFileIsAlreadyShown() async {
    // A button that can't do anything is never offered — and the store enforces it
    // rather than trusting the view to.
    let repository = StubLogRepository(contents: [.success(.stub(lines: 12, totalLines: 12))])
    let store = LogViewerStore(repository: repository, file: .stub(name: "syslog"))
    await store.load()

    await store.loadMore()

    #expect(repository.requestedLines == [LogViewerStore.initialLines], "a second request was made for a complete file")
  }

  @Test func aFailedLoadMoreLeavesTheWindowWhereItWas() async {
    // Raising `requestedLines` before the larger request succeeds would leave the
    // store claiming to hold more than it does, and the next `loadMore()` would
    // skip a step — asking for 3,200 lines when 800 was never fetched.
    let repository = StubLogRepository(contents: [
      .success(.stub(lines: 200, totalLines: 900)),
      .failure(.serverUnreachable),
    ])
    let store = LogViewerStore(repository: repository, file: .stub(name: "docker.log"))
    await store.load()

    await store.loadMore()

    #expect(store.requestedLines == 200)
    #expect(store.state.value?.lines.count == 200, "the lines already shown must survive")
    #expect(store.state.error == nil, "a failed widening is not an error over a working screen")
  }

  @Test func refreshReRequestsTheCurrentWindowNotTheInitialOne() async {
    // Someone who loaded 800 lines and pulls to refresh must not silently lose 600
    // of them.
    let repository = StubLogRepository(contents: [
      .success(.stub(lines: 200, totalLines: 900)),
      .success(.stub(lines: 800, totalLines: 900)),
      .success(.stub(lines: 800, totalLines: 905)),
    ])
    let store = LogViewerStore(repository: repository, file: .stub(name: "docker.log"))
    await store.load()
    await store.loadMore()

    await store.refresh()

    #expect(repository.requestedLines == [200, 800, 800])
    #expect(store.state.value?.totalLines == 905)
  }

  @Test func refreshKeepsTheLinesOnScreenWhenItFails() async {
    let repository = StubLogRepository(contents: [
      .success(.stub(lines: 200, totalLines: 900)),
      .failure(.serverUnreachable),
    ])
    let store = LogViewerStore(repository: repository, file: .stub(name: "docker.log"))
    await store.load()

    await store.refresh()

    #expect(store.state.value?.lines.count == 200)
    #expect(store.state.error == .serverUnreachable)
  }

  @Test func anEmptyFileLoadsWithoutBeingTreatedAsTruncated() async {
    // Empty log files are common. Empty is a real state.
    let repository = StubLogRepository(contents: [.success(.stub(lines: 0, totalLines: 0))])
    let store = LogViewerStore(repository: repository, file: .stub(name: "cron", sizeBytes: 0))
    await store.load()

    #expect(store.state.value?.lines.isEmpty == true)
    #expect(store.state.value?.isTruncated == false)
  }
}

private final class StubLogRepository: LogRepositoryProtocol, @unchecked Sendable {
  enum FilesResult { case success([LogFile]), failure(AppError) }
  enum ContentsResult { case success(LogFileContents), failure(AppError) }

  private let lock = NSLock()
  private var files: [FilesResult]
  private var contents: [ContentsResult]
  private var _requestedLines: [Int?] = []

  /// Every `lines` argument the store passed, in order — the behaviour under test
  /// for both the initial window and every widening.
  var requestedLines: [Int?] { lock.withLock { _requestedLines } }

  init(files: [FilesResult] = [], contents: [ContentsResult] = []) {
    self.files = files
    self.contents = contents
  }

  func logFiles() async throws -> [LogFile] {
    let next: FilesResult = lock.withLock {
      precondition(!files.isEmpty, "logFiles() called more times than results were stubbed")
      return files.removeFirst()
    }
    switch next {
    case .success(let files): return files
    case .failure(let error): throw error
    }
  }

  func logFile(path: String, lines: Int?) async throws -> LogFileContents {
    let next: ContentsResult = lock.withLock {
      _requestedLines.append(lines)
      precondition(!contents.isEmpty, "logFile() called more times than results were stubbed")
      return contents.removeFirst()
    }
    switch next {
    case .success(let contents): return contents
    case .failure(let error): throw error
    }
  }
}

extension LogFile {
  fileprivate static func stub(
    name: String = "syslog", sizeBytes: Int = 1_024
  ) -> LogFile {
    LogFile(name: name, path: "/var/log/\(name)", sizeBytes: sizeBytes, modifiedAt: nil)
  }
}

extension LogFileContents {
  fileprivate static func stub(lines: Int, totalLines: Int) -> LogFileContents {
    LogFileContents(
      path: "/var/log/docker.log",
      lines: lines == 0 ? [] : ((totalLines - lines + 1)...totalLines).map { "line \($0)" },
      totalLines: totalLines,
      startLine: lines == 0 ? nil : totalLines - lines + 1
    )
  }
}
