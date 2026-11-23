import Foundation
import Testing
import TowerCore
import TowerData

// `LiveSystemRepository`'s parity actions and history, through
// `StubURLProtocol`. Issue #22.
//
// The four actions return `JSON!`, and the schema calls the payload "WIP".
// Tower reads nothing from it, but Apollo still decodes it, so each payload
// shape the server could send has to decode for a successful action to read
// as a success.

private func makeRepository(host: String, json: String) -> LiveSystemRepository {
  let endpoint = URL(string: "http://\(host)/graphql")!
  StubURLProtocol.stub(url: endpoint, json: json)
  let server = Server(name: "Stub", url: URL(string: "http://\(host)")!, apiKey: "test-key")
  return LiveSystemRepository(
    provider: ApolloClientProvider(server: server, sessionConfiguration: StubURLProtocol.configuration())
  )
}

/// Every action paired with its mutation field. The field doubles as the
/// stub's payload key, so a method that sent the wrong mutation fails to
/// decode instead of passing.
private let parityActions: [(field: String, run: @Sendable (LiveSystemRepository) async throws -> Void)] = [
  ("start", { try await $0.startParityCheck(correct: false) }),
  ("pause", { try await $0.pauseParityCheck() }),
  ("resume", { try await $0.resumeParityCheck() }),
  ("cancel", { try await $0.cancelParityCheck() }),
]

private func actionResponse(field: String, payload: String) -> String {
  #"{"data": {"parityCheck": {"__typename": "ParityCheckMutations", "\#(field)": \#(payload)}}}"#
}

// MARK: - Actions

@Test(arguments: [
  #"{"ok": true, "message": "Parity check started"}"#,
  #"[{"ok": true}]"#,
  "true",
  #""ok""#,
  "1",
])
func everyParityActionSucceedsWhateverTheJSONPayload(payload: String) async throws {
  for (index, action) in parityActions.enumerated() {
    let repository = makeRepository(
      host: "stub-parity-\(action.field)-\(abs(payload.hashValue))-\(index).test",
      json: actionResponse(field: action.field, payload: payload)
    )
    // Does not throw: the response carries only this action's own field.
    try await action.run(repository)
  }
}

@Test func aParityActionSurfacesTheServersErrorMessage() async throws {
  for action in parityActions {
    let repository = makeRepository(
      host: "stub-parity-\(action.field)-error.test",
      json: #"{"data": null, "errors": [{"message": "Array must be started to check parity"}]}"#
    )
    do {
      try await action.run(repository)
      Issue.record("expected \(action.field) to throw")
    } catch let error as AppError {
      #expect(error == .graphQL(["Array must be started to check parity"]))
    }
  }
}

@Test func aParityActionMapsAnAuthErrorToUnauthorized() async throws {
  let repository = makeRepository(
    host: "stub-parity-forbidden.test",
    json: #"{"data": null, "errors": [{"message": "Forbidden", "extensions": {"code": "FORBIDDEN"}}]}"#
  )
  do {
    try await repository.cancelParityCheck()
    Issue.record("expected cancelParityCheck() to throw")
  } catch let error as AppError {
    #expect(error == .unauthorized)
  }
}

// MARK: - History

private func historyRow(date: String?, duration: String = "100", speed: String = #""120.0 MB/s""#,
                        status: String = "COMPLETED", errors: String = "0") -> String {
  let dateJSON = date.map { "\"\($0)\"" } ?? "null"
  return #"{"__typename": "ParityCheck", "date": \#(dateJSON), "duration": \#(duration), "speed": \#(speed), "status": "\#(status)", "errors": \#(errors)}"#
}

@Test func parityHistoryMapsEveryFieldTheListShows() async throws {
  let repository = makeRepository(
    host: "stub-parity-history-fields.test",
    json: #"{"data": {"parityHistory": [\#(historyRow(date: "2026-11-02T07:02:24.000Z", duration: "90128", speed: #""133.1 MB/s""#, status: "CANCELLED", errors: "3"))]}}"#
  )

  let history = try await repository.parityHistory()

  let record = try #require(history.first)
  #expect(history.count == 1)
  #expect(record.date == Formatters.parseTimestamp("2026-11-02T07:02:24.000Z"))
  #expect(record.durationSeconds == 90128)
  #expect(record.speed == "133.1 MB/s")
  #expect(record.state == .cancelled)
  #expect(record.errors == 3)
}

@Test func parityHistorySortsNewestFirstWithUndatedRowsLast() async throws {
  // The live server's order, abridged: not sorted, with an epoch row mid-list.
  let repository = makeRepository(
    host: "stub-parity-history-sort.test",
    json: #"""
    {"data": {"parityHistory": [
      \#(historyRow(date: "2020-08-07T03:01:01.000Z", errors: "1")),
      \#(historyRow(date: "1970-01-01T00:00:00.000Z", errors: "2")),
      \#(historyRow(date: "2026-11-02T07:02:24.000Z", errors: "3")),
      \#(historyRow(date: nil, errors: "4")),
      \#(historyRow(date: "2020-08-03T08:49:27.000Z", errors: "5"))
    ]}}
    """#
  )

  let history = try await repository.parityHistory()

  #expect(history.map(\.errors) == [3, 1, 5, 2, 4])
  #expect(history.map(\.id) == [0, 1, 2, 3, 4])
  // The epoch is "Unraid could not date this line", not a check in 1970.
  #expect(history[3].date == nil)
}

@Test func parityHistoryKeepsTheListWhenOneRowHasAFieldError() async throws {
  // Verbatim shape from the live server (2026-11-23): one history line's
  // error count is NaN, GraphQL cannot send that as an Int, so the server
  // nulls the field and reports an error at its path.
  let repository = makeRepository(
    host: "stub-parity-history-nan.test",
    json: #"""
    {"errors": [{"message": "Int cannot represent non-integer value: NaN", "locations": [{"line": 1, "column": 52}], "path": ["parityHistory", 1, "errors"], "extensions": {"code": "INTERNAL_SERVER_ERROR"}}],
     "data": {"parityHistory": [
      \#(historyRow(date: "2026-11-02T07:02:24.000Z")),
      \#(historyRow(date: "2020-08-07T03:01:01.000Z", speed: #""nan B/s""#, errors: "null"))
    ]}}
    """#
  )

  let history = try await repository.parityHistory()

  #expect(history.count == 2)
  #expect(history[1].errors == nil)
  #expect(history[1].speedText == nil)
}

@Test func parityHistoryThrowsForAnErrorAtTheList() async throws {
  let repository = makeRepository(
    host: "stub-parity-history-list-error.test",
    json: #"{"data": null, "errors": [{"message": "History unavailable", "path": ["parityHistory"]}]}"#
  )
  do {
    _ = try await repository.parityHistory()
    Issue.record("expected parityHistory() to throw")
  } catch let error as AppError {
    #expect(error == .graphQL(["History unavailable"]))
  }
}

@Test func parityHistoryKeepsAnAuthErrorEvenInsideARow() async throws {
  let repository = makeRepository(
    host: "stub-parity-history-auth.test",
    json: #"""
    {"errors": [{"message": "Forbidden", "path": ["parityHistory", 0, "errors"], "extensions": {"code": "FORBIDDEN"}}],
     "data": {"parityHistory": [\#(historyRow(date: "2026-11-02T07:02:24.000Z", errors: "null"))]}}
    """#
  )
  do {
    _ = try await repository.parityHistory()
    Issue.record("expected parityHistory() to throw")
  } catch let error as AppError {
    #expect(error == .unauthorized)
  }
}
