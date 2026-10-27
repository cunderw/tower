import Foundation
import Testing
import TowerCore

@testable import TowerData

/// `LiveNZBGetRepository` end to end: committed RPC-envelope fixtures
/// answered through the real `ServiceHTTPClient` and a stubbed `URLProtocol`,
/// so the envelope, the method name, the positional parameters, the decoding,
/// and the mapping are all under test together.
///
/// The parameters matter more here than for a REST service: JSON-RPC positions
/// are unnamed, so a parameter in the wrong slot is accepted by the encoder and
/// rejected — or worse, misread — by the server.
private func fixture(_ name: String) throws -> Data {
  let url = try #require(
    Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures/NZBGet"),
    "missing fixture \(name)")
  return try Data(contentsOf: url)
}

private func instance(_ host: String) -> ServiceInstance {
  ServiceInstance(
    kind: .nzbget, name: "NZBGet", baseURL: URL(string: "http://\(host)")!,
    credentials: .usernamePassword(username: "nzbget", password: "hunter2"))
}

private func makeRepository(host: String) -> LiveNZBGetRepository {
  LiveNZBGetRepository(
    instance: instance(host), sessionConfiguration: ServiceStubURLProtocol.configuration())
}

/// Routes by RPC method name, which is in the *body* rather than the path —
/// every call goes to the same `/jsonrpc` endpoint.
private func stub(host: String, _ answer: @escaping @Sendable (String) -> Data) {
  ServiceStubURLProtocol.stub(host: host) { request in
    let body = String(decoding: request.recordedBody ?? Data(), as: UTF8.self)
    let method = ["listgroups", "history", "status", "version", "editqueue", "pausedownload",
      "resumedownload", "rate"]
      .first { body.contains("\"method\":\"\($0)\"") } ?? ""
    return .reply(.init(status: 200, body: answer(method)))
  }
}

private func requests(_ host: String) -> [URLRequest] {
  ServiceStubURLProtocol.requests(host: host)
}

private func bodies(_ host: String) -> [String] {
  requests(host).map { String(decoding: $0.recordedBody ?? Data(), as: UTF8.self) }
}

// MARK: - The envelope

@Suite struct NZBGetEnvelopeTests {
  @Test func everyCallIsOnePostToJsonrpcWithAPositionalParamsArray() async throws {
    let host = "nzb-envelope.invalid"
    let groups = try fixture("listgroups.json")
    let status = try fixture("status.json")
    stub(host: host) { $0 == "status" ? status : groups }

    _ = try await makeRepository(host: host).queue()

    let request = try #require(requests(host).first)
    #expect(request.httpMethod == "POST")
    #expect(request.url?.path().hasSuffix("/jsonrpc") == true)
    let body = try #require(bodies(host).first)
    #expect(body.contains("\"method\":\"listgroups\""))
    // Positional, always: NZBGet rejects a named-parameter object with a parse
    // error that names nothing useful.
    #expect(body.contains("\"params\":[0]"))
    #expect(body.contains("\"version\":\"1.1\""))
  }

  @Test func credentialsGoInTheAuthorizationHeaderNotTheBodyOrURL() async throws {
    let host = "nzb-auth.invalid"
    stub(host: host) { _ in try! fixture("status.json") }

    _ = try? await makeRepository(host: host).status()

    let request = try #require(requests(host).first)
    #expect(request.value(forHTTPHeaderField: "Authorization")?.hasPrefix("Basic ") == true)
    #expect(request.url?.query() == nil, "credentials or params reached the query string")
    #expect(bodies(host).allSatisfy { !$0.contains("hunter2") }, "the password reached a body")
  }

  // MARK: - Error responses

  @Test func anErrorObjectIsAFailureEvenThoughTheStatusIs200() async throws {
    // NZBGet reports failure with an `error` object *alongside* HTTP 200. A
    // client that trusted the status code would read every failure as a
    // success with a missing result.
    let host = "nzb-error.invalid"
    let error = try fixture("error.json")
    stub(host: host) { _ in error }

    await #expect(throws: AppError.self) {
      _ = try await makeRepository(host: host).queue()
    }
  }

  @Test func theServicesOwnMessageSurvivesIntoTheError() async throws {
    let host = "nzb-error-msg.invalid"
    let error = try fixture("error.json")
    stub(host: host) { _ in error }

    do {
      _ = try await makeRepository(host: host).history()
      Issue.record("expected a failure")
    } catch let error as AppError {
      #expect(error.message.contains("Method not found"), "got \(error.message)")
    }
  }

  @Test func aRejectedPasswordIsUnauthorizedRatherThanAGenericServerError() async throws {
    // Some builds report it in the envelope rather than as a 401, and a
    // generic error sends the user hunting through the wrong screen.
    let host = "nzb-denied.invalid"
    let denied = try fixture("error-unauthorized.json")
    stub(host: host) { _ in denied }

    await #expect(throws: AppError.unauthorized) {
      _ = try await makeRepository(host: host).queue()
    }
  }

  @Test func aResponseWithNeitherResultNorErrorSaysSo() async throws {
    // Better than returning a silently empty queue, which reads as "nothing is
    // downloading".
    let host = "nzb-empty-envelope.invalid"
    stub(host: host) { _ in Data(#"{"version":"1.1"}"#.utf8) }

    await #expect(throws: AppError.self) {
      _ = try await makeRepository(host: host).queue()
    }
  }

  @Test func aCommandAnsweringFalseIsARefusalNotASuccess() async throws {
    // Every NZBGet mutation answers with a bare boolean, and `false` means the
    // service declined.
    let host = "nzb-refused.invalid"
    stub(host: host) { _ in Data(#"{"version":"1.1","result":false}"#.utf8) }

    await #expect(throws: AppError.self) {
      try await makeRepository(host: host).pause(ids: [41])
    }
  }

  @Test func aCommandAnsweringTrueSucceedsQuietly() async throws {
    let host = "nzb-accepted.invalid"
    stub(host: host) { _ in Data(#"{"version":"1.1","result":true}"#.utf8) }

    try await makeRepository(host: host).pause(ids: [41])
  }
}

// MARK: - Mapping

@Suite struct NZBGetMappingTests {
  @Test func theQueueRecombinesTheSplit32BitSizeFields() async throws {
    // NZBGet splits every byte count into Lo/Hi halves. Reading only Lo is
    // invisible below 4 GB and wrong by exactly 4 GB above it — which is the
    // range this app's users live in.
    let host = "nzb-queue.invalid"
    let groups = try fixture("listgroups.json")
    let status = try fixture("status.json")
    stub(host: host) { $0 == "status" ? status : groups }

    let queue = try await makeRepository(host: host).queue()

    #expect(queue.count == 3)
    let downloading = queue[0]
    // Hi = 1, Lo = 3221225472 → 4294967296 + 3221225472
    #expect(downloading.sizeBytes == 7_516_192_768)
    #expect(downloading.remainingBytes == 2_147_483_648)
    #expect(downloading.status == .downloading)
    #expect(downloading.category == "movies")
    #expect(downloading.priority == .high)
    #expect(downloading.activeDownloads == 4)
    // Health is per mille on the wire; a fraction here.
    #expect(downloading.health == 1.0)
    #expect(abs(downloading.progress - 0.714) < 0.01)
  }

  @Test func postProcessingIsDistinguishedFromDownloading() async throws {
    // A group unpacking has no download speed, and showing it as stalled rather
    // than busy is the misreading this separation prevents.
    let host = "nzb-pp.invalid"
    let groups = try fixture("listgroups.json")
    let status = try fixture("status.json")
    stub(host: host) { $0 == "status" ? status : groups }

    let queue = try await makeRepository(host: host).queue()

    let unpacking = try #require(queue.first { $0.id == 43 })
    #expect(unpacking.status == .unpacking)
    #expect(unpacking.status.isPostProcessing)
    #expect(!unpacking.status.isPaused)
    #expect(unpacking.health == 0.872)
    #expect(unpacking.priority == .low)
  }

  @Test func anUnrecognisedStatusDegradesTheRowRatherThanTheScreen() async throws {
    let host = "nzb-newstatus.invalid"
    let body = Data(
      #"{"version":"1.1","result":[{"NZBID":1,"NZBName":"X","Status":"TELEPORTING"}]}"#.utf8)
    stub(host: host) { _ in body }

    let queue = try await makeRepository(host: host).queue()

    #expect(queue.count == 1)
    #expect(queue[0].status == .unknown)
    #expect(queue[0].name == "X")
  }

  @Test func etaIsDerivedCumulativelyBecauseNZBGetDownloadsInOrder() async throws {
    // NZBGet reports one server-wide rate because it works the queue in order.
    // Dividing that rate between rows — what a naive per-row calculation does —
    // would tell every row it is finishing at once.
    let host = "nzb-eta.invalid"
    let groups = try fixture("listgroups.json")
    let status = try fixture("status.json")
    stub(host: host) { $0 == "status" ? status : groups }

    let queue = try await makeRepository(host: host).queue()

    // 2147483648 remaining at 12582912 B/s ≈ 170.7s for the active group.
    let first = try #require(queue.first { $0.id == 41 }.flatMap(\.estimatedSecondsRemaining))
    #expect(abs(first - 170.7) < 1)
    // The paused group is not queued behind anything, and gets no estimate.
    #expect(queue.first { $0.id == 42 }?.estimatedSecondsRemaining == nil)
    // Neither does the one post-processing — its bytes have already arrived.
    #expect(queue.first { $0.id == 43 }?.estimatedSecondsRemaining == nil)
  }

  @Test func historyKeepsNZBGetsCompoundStatusAndSaysWhetherItWorked() async throws {
    // `SUCCESS/ALL` versus `FAILURE/PAR`: only the first segment says whether
    // it worked, and the whole string is kept because *which part* failed is
    // the useful bit.
    let host = "nzb-history.invalid"
    let history = try fixture("history.json")
    stub(host: host) { _ in history }

    let items = try await makeRepository(host: host).history()

    #expect(items.count == 2)
    // Newest first, whatever order the build sent.
    #expect(items[0].id == 31)
    #expect(!items[0].isSuccess)
    #expect(items[0].status == "FAILURE/PAR")
    #expect(items[1].isSuccess)
    #expect(items[1].downloadSeconds == 420)
    #expect(items[1].completedAt == Date(timeIntervalSince1970: 1_723_464_000))
  }

  @Test func statusMapsRatesSizesAndTheUnlimitedSentinel() async throws {
    let host = "nzb-status.invalid"
    let status = try fixture("status.json")
    stub(host: host) { method in
      method == "version" ? Data(#"{"version":"1.1","result":"21.1"}"#.utf8) : status
    }

    let result = try await makeRepository(host: host).status()

    #expect(result.downloadRateBytesPerSecond == 12_582_912)
    // Hi = 2, Lo = 0 → 8589934592
    #expect(result.downloadedBytes == 8_589_934_592)
    // Hi = 200, Lo = 1 GiB → 200 × 2^32 + 1073741824
    #expect(result.freeDiskSpaceBytes == 860_067_201_024)
    #expect(!result.isDownloadPaused)
    // 0 is NZBGet's "no limit"; rendering it as 0 B/s says the opposite.
    #expect(result.speedLimitBytesPerSecond == nil)
    #expect(result.uptime == 86_400)
    #expect(result.version == "21.1")
  }

  @Test func aBuildThatWontReportItsVersionStillReportsItsStatus() async throws {
    let host = "nzb-noversion.invalid"
    let status = try fixture("status.json")
    let error = try fixture("error.json")
    stub(host: host) { $0 == "version" ? error : status }

    let result = try await makeRepository(host: host).status()

    #expect(result.version == nil)
    #expect(result.downloadRateBytesPerSecond == 12_582_912, "the status was lost with the version")
  }
}

// MARK: - Actions

@Suite struct NZBGetActionTests {
  private func stubAccepting(host: String) {
    stub(host: host) { _ in Data(#"{"version":"1.1","result":true}"#.utf8) }
  }

  @Test func everyQueueActionSendsEditqueueWithItsCommandAndFourPositionalParams() async throws {
    // `offset` is meaningless for these commands but cannot be omitted — it is
    // positional, and dropping it shifts the id array into the text slot.
    let host = "nzb-edit.invalid"
    stubAccepting(host: host)
    let repository = makeRepository(host: host)

    try await repository.pause(ids: [41, 42])
    #expect(bodies(host).last?.contains(#""params":["GroupPause",0,"",[41,42]]"#) == true,
      "got \(bodies(host).last ?? "")")

    try await repository.resume(ids: [41])
    #expect(bodies(host).last?.contains(#""GroupResume",0,"",[41]"#) == true)

    try await repository.delete(ids: [41])
    #expect(bodies(host).last?.contains(#""GroupFinalDelete",0,"",[41]"#) == true)
  }

  @Test func priorityRidesInTheTextParameterAsAString() async throws {
    // One of the few places NZBGet takes a number that way.
    let host = "nzb-priority.invalid"
    stubAccepting(host: host)

    try await makeRepository(host: host).setPriority(.veryHigh, ids: [41])

    #expect(bodies(host).last?.contains(#""GroupSetPriority",0,"100",[41]"#) == true,
      "got \(bodies(host).last ?? "")")
  }

  @Test func historyRetryAndDeleteUseTheirOwnCommands() async throws {
    let host = "nzb-hist-actions.invalid"
    stubAccepting(host: host)
    let repository = makeRepository(host: host)

    try await repository.retryHistory(ids: [30])
    #expect(bodies(host).last?.contains("HistoryRedownload") == true)

    try await repository.deleteHistory(ids: [30])
    #expect(bodies(host).last?.contains("HistoryFinalDelete") == true)
  }

  @Test func anEmptyIDListSendsNothingAtAll() async throws {
    let host = "nzb-empty-ids.invalid"
    stubAccepting(host: host)

    try await makeRepository(host: host).pause(ids: [])

    #expect(requests(host).isEmpty, "an empty selection reached the service")
  }

  @Test func globalPauseIsNZBGetsOwnSwitchNotALoopOverTheQueue() async throws {
    let host = "nzb-global.invalid"
    stubAccepting(host: host)
    let repository = makeRepository(host: host)

    try await repository.pauseAll()
    #expect(bodies(host).last?.contains("\"method\":\"pausedownload\"") == true)

    try await repository.resumeAll()
    #expect(bodies(host).last?.contains("\"method\":\"resumedownload\"") == true)
  }

  @Test func theSpeedLimitIsSentInKilobytesBecauseThatIsWhatRateTakes() async throws {
    // Passing bytes would cap a user at a thousandth of what they asked for.
    let host = "nzb-rate.invalid"
    stubAccepting(host: host)
    let repository = makeRepository(host: host)

    try await repository.setSpeedLimit(bytesPerSecond: 5_242_880)
    #expect(bodies(host).last?.contains(#""params":[5120]"#) == true,
      "got \(bodies(host).last ?? "")")

    // A positive limit below 1 KB/s still limits; truncating to 0 would
    // remove the cap.
    try await repository.setSpeedLimit(bytesPerSecond: 512)
    #expect(bodies(host).last?.contains(#""params":[1]"#) == true,
      "got \(bodies(host).last ?? "")")

    // 0 is how NZBGet is told "no limit".
    try await repository.setSpeedLimit(bytesPerSecond: nil)
    #expect(bodies(host).last?.contains(#""params":[0]"#) == true)
  }
}

// MARK: - Layering

@Suite struct NZBGetLayeringTests {
  /// "Nothing above `TowerData` knows this is JSON-RPC".
  ///
  /// Both of these types are `TowerCore`'s, and neither the protocol's methods
  /// nor its return types name a transport. The envelope types are `internal`
  /// to `TowerData`, so a `TowerCore`-only consumer could not spell them even
  /// if it wanted to. This test documents that.
  @Test func theRepositorySurfaceIsPlainDomainTypes() {
    let group = NZBGroup(
      id: 1, name: "n", status: .downloading, category: nil, sizeBytes: 10, remainingBytes: 5,
      downloadedBytes: 5, priority: .normal, health: 1, activeDownloads: 1)
    #expect(group.progress == 0.5)

    let status = NZBServerStatus(
      downloadRateBytesPerSecond: 1, remainingBytes: 2, downloadedBytes: 3,
      freeDiskSpaceBytes: 4, isDownloadPaused: false, speedLimitBytesPerSecond: nil,
      uptime: nil, postJobCount: 0, version: nil)
    #expect(status.speedLimitBytesPerSecond == nil)
  }

  @Test func priorityRoundTripsThroughItsRawValueIncludingUnnamedOnes() {
    for priority in NZBPriority.selectable {
      #expect(NZBPriority(rawValue: priority.rawValue) == priority)
    }
    // A value set elsewhere survives rather than being snapped to Normal.
    #expect(NZBPriority(rawValue: 37) == .custom(37))
    #expect(NZBPriority(rawValue: 37).rawValue == 37)
    #expect(!NZBPriority.selectable.contains(.custom(37)))
  }
}
