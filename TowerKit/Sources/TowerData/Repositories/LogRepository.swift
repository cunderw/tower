import Apollo
import Foundation
import TowerAPI
import TowerCore

/// Reads the server's log files, for the syslog viewer in Settings.
///
/// Read-only — Unraid exposes no log mutations — so this is plain reads and no
/// action machinery, like `ShareRepositoryProtocol`.
public protocol LogRepositoryProtocol: Sendable {
  func logFiles() async throws -> [LogFile]

  /// One file's contents, capped at `lines` from the end.
  ///
  /// `lines` is a maximum, not an exact count. Raising it is how the viewer
  /// reaches further back — the same lever `DockerRepositoryProtocol
  /// .logs(id:tail:since:)` documents, and for the same reason: neither API
  /// offers a cursor.
  func logFile(path: String, lines: Int?) async throws -> LogFileContents
}

public struct LiveLogRepository: LogRepositoryProtocol {
  private let provider: ApolloClientProvider

  public init(provider: ApolloClientProvider) {
    self.provider = provider
  }

  public func logFiles() async throws -> [LogFile] {
    let response = try await provider.client.fetch(query: LogFilesQuery(), cachePolicy: .networkOnly)
    if let errors = response.errors, !errors.isEmpty {
      throw AppError.from(graphQLErrors: errors)
    }
    guard let data = response.data else {
      throw AppError.decoding("Empty response for LogFiles.")
    }
    // Sorted by name so the list is stable and scannable; the server returns them
    // in readdir order, which is neither.
    return data.logFiles
      .map(LogFile.init(from:))
      .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
  }

  public func logFile(path: String, lines: Int?) async throws -> LogFileContents {
    let response = try await provider.client.fetch(
      query: LogFileQuery(path: path, lines: lines.flatMap { Int32(exactly: $0) } ?? .none),
      cachePolicy: .networkOnly
    )
    if let errors = response.errors, !errors.isEmpty {
      throw AppError.from(graphQLErrors: errors)
    }
    guard let data = response.data else {
      throw AppError.decoding("Empty response for LogFile.")
    }
    return LogFileContents(from: data.logFile)
  }
}

extension LogFile {
  /// Not public — its parameter is an Apollo-generated type; see
  /// `Container.init(from:)`.
  init(from file: LogFilesQuery.Data.LogFile) {
    self.init(
      name: file.name,
      path: file.path,
      sizeBytes: file.size,
      modifiedAt: Formatters.parseTimestamp(file.modifiedAt)
    )
  }
}

extension LogFileContents {
  /// Not public — see `LogFile.init(from:)`.
  init(from contents: LogFileQuery.Data.LogFile) {
    self.init(
      path: contents.path,
      lines: LogFileContents.splitIntoLines(contents.content),
      totalLines: contents.totalLines,
      startLine: contents.startLine
    )
  }
}
