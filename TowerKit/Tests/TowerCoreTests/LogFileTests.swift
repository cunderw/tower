import Foundation
import Testing
@testable import TowerCore

@Test func aZeroByteFileReportsItselfEmpty() {
  // Unraid's log directory can hold 0-byte files. The list says so rather than
  // letting someone open one to a blank screen and wonder whether the request
  // failed.
  #expect(LogFile.stub(sizeBytes: 0).isEmpty)
  #expect(!LogFile.stub(sizeBytes: 1).isEmpty)
}

@Test func theFilesPathIsItsIdentity() {
  // `LogFile` has no `id` field on the wire, and a path is unique per file by
  // definition — which is also why nothing constructs one client-side.
  #expect(LogFile.stub(path: "/var/log/syslog").id == "/var/log/syslog")
}

// MARK: - Line splitting

@Test func aTrailingNewlineDoesNotProduceAPhantomLastLine() {
  // Log files almost always end with a newline, and `components(separatedBy:)`
  // yields a trailing "" for it — a blank row at the bottom of every log.
  #expect(LogFileContents.splitIntoLines("one\ntwo\n") == ["one", "two"])
}

@Test func aFileWithNoTrailingNewlineKeepsItsLastLine() {
  // The other direction, and the bug an over-eager fix introduces: dropping the
  // last element unconditionally loses real content.
  #expect(LogFileContents.splitIntoLines("one\ntwo") == ["one", "two"])
}

@Test func interiorBlankLinesSurvive() {
  // Real content — stack traces and daemon restarts are full of them — so
  // `omittingEmptySubsequences` would be wrong. Only the single trailing one goes.
  #expect(LogFileContents.splitIntoLines("one\n\ntwo\n") == ["one", "", "two"])
}

@Test func onlyOneTrailingBlankLineIsDropped() {
  // A file ending in two newlines has one genuinely blank final line.
  #expect(LogFileContents.splitIntoLines("one\n\n") == ["one", ""])
}

@Test func anEmptyFileSplitsToNoLinesRatherThanOneBlankOne() {
  #expect(LogFileContents.splitIntoLines("") == [])
}

@Test func aSingleLineWithNoNewlineIsOneLine() {
  #expect(LogFileContents.splitIntoLines("just this") == ["just this"])
}

// MARK: - Truncation

@Test func fewerLinesThanTheFileHasMeansTruncated() {
  let contents = LogFileContents(
    path: "/var/log/syslog", lines: ["a", "b"], totalLines: 900, startLine: 899
  )
  #expect(contents.isTruncated)
}

@Test func aShortFileFetchedWholeIsNotTruncated() {
  // The case comparing against the *requested* maximum gets wrong: asking for 500
  // lines of a 200-line file returns 200, which is complete despite being short of
  // the request.
  let contents = LogFileContents(
    path: "/var/log/cron", lines: ["a", "b"], totalLines: 2, startLine: 1
  )
  #expect(!contents.isTruncated)
}

@Test func anEmptyFileIsNotTruncated() {
  let contents = LogFileContents(path: "/var/log/btmp", lines: [], totalLines: 0, startLine: nil)
  #expect(!contents.isTruncated)
}

extension LogFile {
  fileprivate static func stub(
    name: String = "syslog", path: String = "/var/log/syslog",
    sizeBytes: Int = 1_024, modifiedAt: Date? = nil
  ) -> LogFile {
    LogFile(name: name, path: path, sizeBytes: sizeBytes, modifiedAt: modifiedAt)
  }
}
