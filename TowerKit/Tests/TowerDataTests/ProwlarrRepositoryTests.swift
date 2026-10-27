import Foundation
import Testing
import TowerCore

@testable import TowerData

/// `LiveProwlarrRepository` end to end: committed fixtures answered
/// through the real `ServiceHTTPClient` and a stubbed `URLProtocol`.
///
/// The schema round trip gets the most attention here, because it is the one
/// place a mapping bug **rewrites the user's configuration**: Prowlarr's PUT
/// rebuilds the indexer from the body, so a field Tower decoded as the wrong type and
/// re-encoded would quietly change a setting nobody touched.
private func fixture(_ name: String) throws -> Data {
  let url = try #require(
    Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures/Prowlarr"),
    "missing fixture \(name)")
  return try Data(contentsOf: url)
}

private func makeRepository(host: String) -> LiveProwlarrRepository {
  let instance = ServiceInstance(
    kind: .prowlarr, name: "Prowlarr", baseURL: URL(string: "http://\(host)")!,
    credentials: .apiKey("k"))
  return LiveProwlarrRepository(
    instance: instance,
    client: ServiceHTTPClient(
      instance: instance, sessionConfiguration: ServiceStubURLProtocol.configuration()))
}

private func stub(host: String, _ answer: @escaping @Sendable (String) -> Data) {
  ServiceStubURLProtocol.stub(host: host) { request in
    .reply(.init(status: 200, body: answer(request.url?.path() ?? "")))
  }
}

private func requests(_ host: String) -> [URLRequest] {
  ServiceStubURLProtocol.requests(host: host)
}

private func lastBody(_ host: String) -> String {
  String(decoding: requests(host).last?.recordedBody ?? Data(), as: UTF8.self)
}

// MARK: - Indexers

@Suite struct ProwlarrIndexerTests {
  private func stubIndexers(host: String) throws {
    let indexers = try fixture("indexers.json")
    let status = try fixture("indexer-status.json")
    stub(host: host) { path in path.hasSuffix("indexerstatus") ? status : indexers }
  }

  @Test func theIndexerListMapsProtocolPrivacyAndEnabledState() async throws {
    let host = "pl-list.invalid"
    try stubIndexers(host: host)

    let indexers = try await makeRepository(host: host).indexers()

    #expect(indexers.count == 2)
    // Sorted by name, so "Example Private" leads "Example Public". Selected by
    // id rather than index, so the assertions test the mapping and not the
    // sort — which has its own check below.
    #expect(indexers.map(\.name) == ["Example Private", "Example Public"])
    let publicIndexer = try #require(indexers.first { $0.id == 1 })
    #expect(publicIndexer.name == "Example Public")
    #expect(publicIndexer.isEnabled)
    // A protocol Tower does not name is carried verbatim and shown as nothing.
    #expect(publicIndexer.downloadProtocol.apiValue == "other")
    #expect(publicIndexer.downloadProtocol.displayName == nil)
    #expect(publicIndexer.privacy == .publicIndexer)
    #expect(publicIndexer.supportsSearch)

    let privateIndexer = try #require(indexers.first { $0.id == 2 })
    #expect(!privateIndexer.isEnabled)
    #expect(privateIndexer.downloadProtocol == .usenet)
    #expect(privateIndexer.privacy == .privateIndexer)
    #expect(privateIndexer.tagIDs == [3])
  }

  @Test func aFailingIndexerIsMarkedFromTheSeparateStatusEndpoint() async throws {
    // `/indexer` says nothing about whether an indexer is currently failing —
    // that lives in `/indexerstatus`, and it is the most useful thing the list
    // can show.
    let host = "pl-status.invalid"
    try stubIndexers(host: host)

    let indexers = try await makeRepository(host: host).indexers()

    let failing = try #require(indexers.first { $0.id == 2 })
    #expect(failing.isFailing)
    #expect(failing.disabledUntil != nil)
    let healthy = try #require(indexers.first { $0.id == 1 })
    #expect(!healthy.isFailing)
  }

  @Test func aProwlarrThatWontReportStatusStillReportsItsIndexers() async throws {
    let host = "pl-nostatus.invalid"
    let indexers = try fixture("indexers.json")
    ServiceStubURLProtocol.stub(host: host) { request in
      if request.url?.path().hasSuffix("indexerstatus") == true {
        return .reply(.init(status: 500, body: Data()))
      }
      return .reply(.init(status: 200, body: indexers))
    }

    let result = try await makeRepository(host: host).indexers()

    #expect(result.count == 2, "the list was lost with the status")
    #expect(result.allSatisfy { !$0.isFailing })
  }

  // MARK: - The field types

  @Test func everyFieldTypeTheFormRendersIsMapped() async throws {
    // The add-indexer form renders text, number, select, and checkbox fields.
    let host = "pl-fields.invalid"
    let schema = try fixture("indexer-schema.json")
    stub(host: host) { _ in schema }

    let schemas = try await makeRepository(host: host).schemas()
    let fields = try #require(schemas.first).fields

    // Sorted by the API's own `order`, not the array's order — the fixture
    // deliberately sends them shuffled.
    #expect(fields.map(\.name) == [
      "username", "password", "sort", "retentionDays", "englishOnly", "internalToken",
    ])

    let text = try #require(fields.first { $0.name == "username" })
    #expect(text.kind == .textbox)
    #expect(text.value == .text(""))

    let password = try #require(fields.first { $0.name == "password" })
    #expect(password.kind == .password)
    #expect(password.kind.isSecret)

    let number = try #require(fields.first { $0.name == "retentionDays" })
    #expect(number.kind == .number)
    #expect(number.value == .number(1440))
    #expect(number.isAdvanced)

    // A select's value arrives as a number and must become `.option`, or the
    // picker has nothing to match against.
    let select = try #require(fields.first { $0.name == "sort" })
    #expect(select.kind == .select)
    #expect(select.value == .option(0))
    #expect(select.options.map(\.name) == ["created", "size"])
    #expect(select.options.first?.hint == "Newest first")

    let checkbox = try #require(fields.first { $0.name == "englishOnly" })
    #expect(checkbox.kind == .checkbox)
    #expect(checkbox.value == .boolean(false))

    // `hidden` is a *string* on the wire, not a bool.
    let hidden = try #require(fields.first { $0.name == "internalToken" })
    #expect(hidden.isHidden)
  }

  @Test func aCheckboxStaysABooleanAcrossARoundTrip() throws {
    // JSON `true` decodes as `1` through some number paths, and a checkbox
    // that round-trips as the number 1 stops being a checkbox — which, on a
    // PUT that rebuilds the indexer from the body, rewrites the user's setting.
    let decoded = try JSONDecoder().decode(AnyFieldValue.self, from: Data("true".utf8))
    #expect(decoded.value == .boolean(true))

    let reencoded = try JSONEncoder().encode(decoded)
    #expect(String(decoding: reencoded, as: UTF8.self) == "true")
  }

  @Test func aWholeNumberGoesBackAsAnIntegerNotAFloat() throws {
    // Prowlarr rejects `"port": 9117.0` on some contracts.
    let value = AnyFieldValue(.number(9117))
    let encoded = try JSONEncoder().encode(value)
    #expect(String(decoding: encoded, as: UTF8.self) == "9117")
  }

  @Test func anUnrecognisedFieldValueDoesNotBreakTheWholeIndexer() throws {
    // One field Tower doesn't model must not make the indexer undecodable.
    let decoded = try JSONDecoder().decode(
      AnyFieldValue.self, from: Data(#"{"nested":"object"}"#.utf8))
    #expect(decoded.value == .empty)
  }

  // MARK: - Enable / disable

  @Test func enablingReadsTheIndexerBackAndPutsTheWholeThing() async throws {
    // A PATCH-shaped body would clear every field it omitted — including the
    // API key. So the indexer is read back and returned whole with one field
    // changed, and this asserts the *other* fields survived.
    let host = "pl-enable.invalid"
    let single = Data(
      """
      {
        "id": 1, "name": "Example Private", "definitionName": "ExamplePrivate",
        "implementation": "Cardigann", "configContract": "CardigannSettings",
        "enable": true, "priority": 10, "protocol": "usenet", "privacy": "private",
        "appProfileId": 1, "redirect": true, "downloadClientId": 2,
        "fields": [
          { "order": 0, "name": "apiKey", "label": "API Key", "value": "secret-value",
            "type": "password" },
          { "order": 1, "name": "vip", "label": "VIP", "value": true, "type": "checkbox" }
        ]
      }
      """.utf8)
    ServiceStubURLProtocol.stub(host: host) { request in
      if request.httpMethod == "PUT" { return .reply(.init(status: 200, body: Data("{}".utf8))) }
      return .reply(.init(status: 200, body: single))
    }

    try await makeRepository(host: host).setEnabled(false, indexerID: 1)

    let put = try #require(requests(host).last)
    #expect(put.httpMethod == "PUT")
    let body = String(decoding: put.recordedBody ?? Data(), as: UTF8.self)
    #expect(body.contains("\"enable\":false"), "got \(body)")
    // The credential and the rest of the resource came back untouched.
    #expect(body.contains("secret-value"), "the API key was dropped by the round trip")
    #expect(body.contains("\"configContract\":\"CardigannSettings\""))
    // And the checkbox is still a boolean, not the number 1.
    #expect(body.contains("\"value\":true"), "the checkbox round-tripped as a number")
    // Prowlarr rebuilds the indexer from the body and rejects a PUT without a
    // positive app profile; redirect and the download client are reset when
    // missing.
    #expect(body.contains("\"appProfileId\":1"), "appProfileId was dropped: \(body)")
    #expect(body.contains("\"redirect\":true"), "redirect was dropped: \(body)")
    #expect(body.contains("\"downloadClientId\":2"), "downloadClientId was dropped: \(body)")
  }

  // MARK: - Test

  @Test func aSuccessfulTestIsAnEmpty200() async throws {
    let host = "pl-testok.invalid"
    ServiceStubURLProtocol.stub(host: host) { request in
      // The repository reads the indexer, then POSTs it to /indexer/test.
      if request.httpMethod == "POST" { return .reply(.init(status: 200, body: Data())) }
      return .reply(.init(status: 200, body: Data(#"{"id":1,"name":"X","enable":true}"#.utf8)))
    }

    let result = try await makeRepository(host: host).test(indexerID: 1)

    #expect(result.isSuccess)
    #expect(result.messages.isEmpty)
  }

  @Test func aRejectedTestIsAFailureWithTheServicesReasonRatherThanAThrow() async throws {
    // `POST /indexer/test` answers 400 with validation failures. Throwing would
    // make the caller treat a normal outcome as an error, and reporting only
    // the status code would say "unreachable" for a wrong password.
    let host = "pl-testfail.invalid"
    ServiceStubURLProtocol.stub(host: host) { request in
      if request.httpMethod == "POST" {
        return .reply(
          .init(
            status: 400,
            body: Data(#"{"message":"Unable to connect to indexer: 403 Forbidden"}"#.utf8)))
      }
      return .reply(.init(status: 200, body: Data(#"{"id":1,"name":"X","enable":true}"#.utf8)))
    }

    let result = try await makeRepository(host: host).test(indexerID: 1)

    #expect(!result.isSuccess)
    #expect(result.messages.first?.contains("403 Forbidden") == true, "got \(result.messages)")
  }
}

// MARK: - Stats and history

@Suite struct ProwlarrStatsTests {
  @Test func statsMapCountersAndComputeASuccessRate() async throws {
    let host = "pl-stats.invalid"
    let body = try fixture("indexerstats.json")
    stub(host: host) { _ in body }

    let stats = try await makeRepository(host: host).stats()

    #expect(stats.count == 2)
    let busy = try #require(stats.first { $0.indexerID == 1 })
    #expect(busy.queries == 200)
    #expect(busy.failedQueries == 4)
    #expect(busy.averageResponseTimeMilliseconds == 412)
    #expect(abs((busy.successRate ?? 0) - 0.98) < 0.001)

    // A brand-new indexer is not "0% successful".
    let unused = try #require(stats.first { $0.indexerID == 2 })
    #expect(unused.successRate == nil)
  }

  @Test func historyLiftsTheQueryAndSourceOutOfProwlarrsLooseDataBag() async throws {
    let host = "pl-history.invalid"
    let body = try fixture("history.json")
    stub(host: host) { _ in body }

    let records = try await makeRepository(host: host).history(indexerID: nil)

    #expect(records.count == 2)
    #expect(records[0].query == "example film")
    #expect(records[0].source == "Radarr")
    #expect(records[0].isSuccessful)
    #expect(!records[1].isSuccessful)
    #expect(records[1].query == nil)
  }

  @Test func perIndexerHistoryFiltersServerSide() async throws {
    let host = "pl-history-filtered.invalid"
    let body = try fixture("history.json")
    stub(host: host) { _ in body }

    _ = try await makeRepository(host: host).history(indexerID: 2)

    #expect(requests(host).last?.url?.query()?.contains("indexerId=2") == true)
  }
}

// MARK: - Save

@Suite struct ProwlarrSaveTests {
  @Test func aNewIndexerSendsTheSchemasProtocolBackVerbatim() async throws {
    // Prowlarr builds the indexer from the body, and Tower keeps the
    // protocol as Prowlarr's own string, so a value Tower does not name must
    // go back exactly as it came.
    let host = "pl-save.invalid"
    try stubAddFlow(host: host, profiles: #"[{"id":1,"name":"Standard"}]"#)
    let repository = makeRepository(host: host)
    let schema = try #require(try await repository.schemas().first)

    try await repository.save(IndexerDraft(schema: schema))

    let post = try #require(requests(host).last)
    #expect(post.httpMethod == "POST")
    let sent = String(decoding: post.recordedBody ?? Data(), as: UTF8.self)
    #expect(sent.contains("\"protocol\":\"other\""), "got \(sent)")
  }

  // MARK: - App profile

  // Prowlarr rejects an indexer without a positive `appProfileId`, on a create
  // and on `/indexer/test` alike. The schema carries none, and Prowlarr's own
  // form picks the first profile by name, so Tower does the same.

  @Test func aNewIndexerIsSavedUnderTheFirstAppProfileByName() async throws {
    let host = "pl-save-profile.invalid"
    try stubAddFlow(host: host, profiles: Self.twoProfiles)
    let repository = makeRepository(host: host)
    let schema = try #require(try await repository.schemas().first)

    try await repository.save(IndexerDraft(schema: schema))

    let post = try #require(requests(host).last)
    #expect(post.httpMethod == "POST")
    #expect(post.url?.path() == "/api/v1/indexer")
    let sent = String(decoding: post.recordedBody ?? Data(), as: UTF8.self)
    #expect(sent.contains("\"appProfileId\":7"), "got \(sent)")
  }

  @Test func profileNamesAreOrderedByTheirNumbersNotTheirDigits() async throws {
    // Prowlarr's form sorts names numerically, so "Profile 2" leads
    // "Profile 10" there, and has to here.
    let host = "pl-save-numeric.invalid"
    try stubAddFlow(
      host: host, profiles: #"[{"id":10,"name":"Profile 10"},{"id":2,"name":"Profile 2"}]"#)
    let repository = makeRepository(host: host)
    let schema = try #require(try await repository.schemas().first)

    try await repository.save(IndexerDraft(schema: schema))

    let sent = String(decoding: requests(host).last?.recordedBody ?? Data(), as: UTF8.self)
    #expect(
      sent.contains("\"appProfileId\":2,") || sent.contains("\"appProfileId\":2}"),
      "got \(sent)")
  }

  @Test func aDraftIsTestedUnderTheFirstAppProfileByName() async throws {
    let host = "pl-test-profile.invalid"
    try stubAddFlow(host: host, profiles: Self.twoProfiles)
    let repository = makeRepository(host: host)
    let schema = try #require(try await repository.schemas().first)

    let result = try await repository.test(IndexerDraft(schema: schema))

    #expect(result.isSuccess)
    let post = try #require(requests(host).last)
    #expect(post.httpMethod == "POST")
    #expect(post.url?.path() == "/api/v1/indexer/test")
    let sent = String(decoding: post.recordedBody ?? Data(), as: UTF8.self)
    #expect(sent.contains("\"appProfileId\":7"), "got \(sent)")
  }

  @Test func testingADraftWithNoAppProfileFailsWithAReasonAndSendsNothing() async throws {
    // A failed result, not a throw: the add form reads a throw as "Prowlarr
    // didn't answer the test", which would hide the reason.
    let host = "pl-test-noprofile.invalid"
    try stubAddFlow(host: host, profiles: "[]")
    let repository = makeRepository(host: host)
    let schema = try #require(try await repository.schemas().first)

    let result = try await repository.test(IndexerDraft(schema: schema))

    #expect(!result.isSuccess)
    #expect(
      result.messages.first?.contains("app profiles") == true, "got \(result.messages)")
    #expect(!requests(host).contains { $0.httpMethod == "POST" })
  }

  @Test func savingADraftWithNoAppProfileIsRefusedAndSendsNothing() async throws {
    let host = "pl-save-noprofile.invalid"
    try stubAddFlow(host: host, profiles: "[]")
    let repository = makeRepository(host: host)
    let schema = try #require(try await repository.schemas().first)

    do {
      try await repository.save(IndexerDraft(schema: schema))
      Issue.record("a save with no app profile was not refused")
    } catch let error as AppError {
      guard case .actionRefused(let detail) = error else {
        Issue.record("expected actionRefused, got \(error)")
        return
      }
      #expect(detail.contains("app profiles"), "got \(detail)")
    }
    #expect(!requests(host).contains { $0.httpMethod == "POST" })
  }

  // MARK: - Redirect

  // Prowlarr refuses a Usenet indexer with `redirect` off when its definition
  // supports redirect, on a create and on `/indexer/test` alike. Newznab is
  // such a definition, and its schema arrives with `redirect` already on.

  @Test func aNewznabIndexerIsSavedWithRedirectOn() async throws {
    let host = "pl-save-redirect.invalid"
    try stubAddFlow(host: host, profiles: Self.twoProfiles, schema: Self.newznabSchema)
    let repository = makeRepository(host: host)
    let schema = try #require(try await repository.schemas().first)

    try await repository.save(IndexerDraft(schema: schema))

    let post = try #require(requests(host).last)
    #expect(post.url?.path() == "/api/v1/indexer")
    let sent = String(decoding: post.recordedBody ?? Data(), as: UTF8.self)
    #expect(sent.contains("\"redirect\":true"), "got \(sent)")
  }

  @Test func aNewznabDraftIsTestedWithRedirectOn() async throws {
    let host = "pl-test-redirect.invalid"
    try stubAddFlow(host: host, profiles: Self.twoProfiles, schema: Self.newznabSchema)
    let repository = makeRepository(host: host)
    let schema = try #require(try await repository.schemas().first)

    _ = try await repository.test(IndexerDraft(schema: schema))

    let post = try #require(requests(host).last)
    #expect(post.url?.path() == "/api/v1/indexer/test")
    let sent = String(decoding: post.recordedBody ?? Data(), as: UTF8.self)
    #expect(sent.contains("\"redirect\":true"), "got \(sent)")
  }

  @Test func aSchemaWithoutRedirectSendsNoRedirectKey() async throws {
    let host = "pl-save-noredirect.invalid"
    try stubAddFlow(host: host, profiles: Self.twoProfiles)
    let repository = makeRepository(host: host)
    let schema = try #require(try await repository.schemas().first)

    try await repository.save(IndexerDraft(schema: schema))

    let sent = String(decoding: requests(host).last?.recordedBody ?? Data(), as: UTF8.self)
    #expect(!sent.contains("redirect"), "got \(sent)")
  }

  private static let newznabSchema = """
    [{"definitionName":"Newznab","implementation":"Newznab","configContract":"NewznabSettings",
    "protocol":"usenet","privacy":"private","enable":true,"redirect":true,"supportsRedirect":true,
    "indexerUrls":[],"fields":[]}]
    """

  private static let twoProfiles = #"[{"id":9,"name":"Zed"},{"id":7,"name":"Alpha"}]"#

  /// The add flow's endpoints, each answered by its own path: the schema list,
  /// the app profiles, a create, and a draft test. The schema defaults to the
  /// Cardigann fixture.
  private func stubAddFlow(host: String, profiles: String, schema: String? = nil) throws {
    let schemaBody = try schema.map { Data($0.utf8) } ?? fixture("indexer-schema.json")
    ServiceStubURLProtocol.stub(host: host) { request in
      switch request.url?.path() ?? "" {
      case "/api/v1/appprofile":
        return .reply(.init(status: 200, body: Data(profiles.utf8)))
      case "/api/v1/indexer/test":
        return .reply(.init(status: 200, body: Data()))
      case "/api/v1/indexer":
        return .reply(.init(status: 200, body: Data(#"{"id":9,"name":"New"}"#.utf8)))
      default:
        return .reply(.init(status: 200, body: schemaBody))
      }
    }
  }
}
