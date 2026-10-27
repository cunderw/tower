import Foundation

/// One of the server's log files, as `LogFile` reports it.
public struct LogFile: Identifiable, Equatable, Hashable, Sendable {
  /// The server's own `path`, used as the identity. There is no `id` field on
  /// this type, and a path is unique per file by definition — which also means
  /// nothing here ever constructs a path client-side.
  public var id: String { path }
  public let name: String
  public let path: String
  /// Bytes. An `Int` on the wire, not `BigInt` — log files don't reach `Int32`.
  public let sizeBytes: Int
  /// `nil` when the timestamp didn't parse. `modifiedAt` is a non-null `DateTime`
  /// on the wire, but that is a promise about presence, not readability — same
  /// rule as `ContainerLogLine.timestamp` and the custom scalars.
  public let modifiedAt: Date?

  public init(name: String, path: String, sizeBytes: Int, modifiedAt: Date?) {
    self.name = name
    self.path = path
    self.sizeBytes = sizeBytes
    self.modifiedAt = modifiedAt
  }

  /// Unraid's log directory can hold 0-byte files, and the list says so rather
  /// than letting someone open one to a blank screen and wonder whether the
  /// request failed.
  public var isEmpty: Bool { sizeBytes == 0 }
}

/// One `logFile` response.
///
/// `content` arrives as a **single string**, so the split into lines happens here
/// once, at the boundary, rather than in a view body that re-runs on every
/// render.
public struct LogFileContents: Equatable, Sendable {
  public let path: String
  public let lines: [String]
  /// The server's own count of lines in the whole file, which is what makes
  /// `isTruncated` answerable.
  public let totalLines: Int
  /// 1-indexed line number of the first line in `lines`, when the server said.
  public let startLine: Int?

  public init(path: String, lines: [String], totalLines: Int, startLine: Int?) {
    self.path = path
    self.lines = lines
    self.totalLines = totalLines
    self.startLine = startLine
  }

  /// Whether there is more file above what was fetched — the signal the viewer's
  /// "load more" needs.
  ///
  /// Compares against the server's `totalLines` rather than against the requested
  /// maximum, because those disagree in the case that matters: asking for 500
  /// lines of a 200-line file returns 200, which is not truncated even though it
  /// is short of the request.
  public var isTruncated: Bool { lines.count < totalLines }

  /// Splits a raw `content` blob into lines.
  ///
  /// Two details that a naive `split(separator: "\n")` gets wrong:
  ///
  /// - **A trailing newline must not produce a phantom empty last line.** Log
  ///   files almost always end with one, and `components(separatedBy:)` yields a
  ///   trailing `""` for it — which renders as a blank row at the bottom of every
  ///   log.
  /// - **Interior blank lines must survive.** They are real content (stack traces
  ///   and daemon restarts are full of them), so `omittingEmptySubsequences`
  ///   behaviour is wrong; only the single trailing one is dropped.
  public static func splitIntoLines(_ content: String) -> [String] {
    var lines = content.components(separatedBy: "\n")
    if lines.last?.isEmpty == true {
      lines.removeLast()
    }
    return lines
  }
}
