import Foundation
import TowerCore
import TowerData

/// Demo mode's Prowlarr.
private enum DemoProwlarrLatency {
  static let read = Duration.milliseconds(450)
  static let write = Duration.milliseconds(700)

  static func read() async { try? await Task.sleep(for: read) }
  static func write() async { try? await Task.sleep(for: write) }
}

@MainActor
final class DemoProwlarrServer {
  private(set) var indexers: [ProwlarrIndexer] = DemoProwlarrFixtures.indexers()
  private var nextID = 40

  func setEnabled(_ isEnabled: Bool, id: Int) {
    indexers = indexers.map { $0.id == id ? $0.settingEnabled(isEnabled) : $0 }
  }

  func remove(id: Int) { indexers.removeAll { $0.id == id } }

  func save(_ draft: IndexerDraft) -> ProwlarrIndexer {
    let id = draft.id ?? nextID
    if draft.id == nil { nextID += 1 }
    let saved = ProwlarrIndexer(
      id: id, name: draft.name, definitionName: draft.schema.definitionName,
      implementation: draft.schema.implementation, isEnabled: draft.isEnabled,
      downloadProtocol: draft.schema.downloadProtocol, privacy: draft.schema.privacy,
      priority: draft.priority, supportsRSS: true, supportsSearch: true,
      fields: draft.fields, tagIDs: [])
    if let index = indexers.firstIndex(where: { $0.id == id }) {
      indexers[index] = saved
    } else {
      indexers.append(saved)
      indexers.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
    return saved
  }
}

struct DemoProwlarrRepository: ProwlarrRepositoryProtocol {
  let instance: ServiceInstance
  let server: DemoProwlarrServer

  var arr: ArrClientCore {
    // Never used: the shared surface is answered below rather than delegated.
    ArrClientCore(client: ServiceHTTPClient(instance: instance), apiPath: "api/v1")
  }

  func indexers() async throws -> [ProwlarrIndexer] {
    await DemoProwlarrLatency.read()
    return await server.indexers
  }

  func setEnabled(_ isEnabled: Bool, indexerID: Int) async throws {
    await DemoProwlarrLatency.write()
    await server.setEnabled(isEnabled, id: indexerID)
  }

  func test(indexerID: Int) async throws -> IndexerTestResult {
    await DemoProwlarrLatency.write()
    // The failing indexer fails its test too, so the demo's two states agree.
    let indexer = await server.indexers.first { $0.id == indexerID }
    guard indexer?.isFailing != true else {
      return IndexerTestResult(
        isSuccess: false,
        messages: ["Unable to connect to indexer: the request timed out."])
    }
    return IndexerTestResult(isSuccess: true, messages: [])
  }

  func delete(indexerID: Int) async throws {
    await DemoProwlarrLatency.write()
    await server.remove(id: indexerID)
  }

  func schemas() async throws -> [IndexerSchema] {
    await DemoProwlarrLatency.read()
    return DemoProwlarrFixtures.schemas
  }

  @discardableResult
  func save(_ draft: IndexerDraft) async throws -> ProwlarrIndexer {
    await DemoProwlarrLatency.write()
    return await server.save(draft)
  }

  func test(_ draft: IndexerDraft) async throws -> IndexerTestResult {
    await DemoProwlarrLatency.write()
    // A definition needing credentials fails until they are filled in — which
    // is what makes test-before-save worth demonstrating.
    let credential = draft.fields.first { $0.kind == .password }
    if let credential, credential.value.stringValue.isEmpty {
      return IndexerTestResult(
        isSuccess: false, messages: ["Authentication failed: no password supplied."])
    }
    return IndexerTestResult(isSuccess: true, messages: [])
  }

  func stats() async throws -> [IndexerStats] {
    await DemoProwlarrLatency.read()
    return DemoProwlarrFixtures.stats
  }

  func history(indexerID: Int?) async throws -> [ProwlarrHistoryRecord] {
    await DemoProwlarrLatency.read()
    let all = DemoProwlarrFixtures.history()
    guard let indexerID else { return all }
    return all.filter { $0.indexerID == indexerID }
  }
}

// MARK: - Fixtures

/// The dataset demo mode's Prowlarr presents: healthy and failing indexers,
/// and definitions covering every supported field type.
enum DemoProwlarrFixtures {
  /// Invented names, in the alphabetical order Prowlarr's own list uses, so an
  /// indexer added in the demo sorts in among them.
  static func indexers() -> [ProwlarrIndexer] {
    [
      indexer(
        id: 1, name: "Brightwater Index", privacy: .publicIndexer, protocolValue: .usenet,
        enabled: true),
      indexer(
        id: 2, name: "Kestrel NZB", privacy: .privateIndexer, protocolValue: .usenet,
        enabled: true),
      // The failing one — the row this screen exists to surface.
      indexer(
        id: 3, name: "Lanternhub", privacy: .privateIndexer, protocolValue: .usenet,
        enabled: true, failing: true),
      indexer(
        id: 4, name: "Thistle Index", privacy: .publicIndexer, protocolValue: .usenet,
        enabled: false),
    ]
  }

  private static func indexer(
    id: Int, name: String, privacy: IndexerPrivacy, protocolValue: ArrDownloadProtocol,
    enabled: Bool, failing: Bool = false
  ) -> ProwlarrIndexer {
    ProwlarrIndexer(
      id: id, name: name, definitionName: name.replacingOccurrences(of: " ", with: ""),
      implementation: "Cardigann", isEnabled: enabled, downloadProtocol: protocolValue,
      privacy: privacy, priority: 25, supportsRSS: true, supportsSearch: true,
      fields: [
        IndexerField(
          name: "baseUrl", label: "Base URL", kind: .textbox, helpText: nil,
          value: .text("https://\(name.lowercased().replacingOccurrences(of: " ", with: "-")).example.invalid/"),
          options: [], isAdvanced: false, isHidden: false, order: 0)
      ],
      tagIDs: [],
      failureMessage: failing ? "Recent failures" : nil,
      disabledUntil: failing ? Date().addingTimeInterval(1_800) : nil)
  }

  /// One definition per supported field type, so the generated form can be
  /// walked end to end in the demo — including a field the renderer can't
  /// draw, so the form's fallback state is reachable.
  static let schemas: [IndexerSchema] = [
    IndexerSchema(
      definitionName: "ExamplePrivate", implementation: "Cardigann",
      configContract: "CardigannSettings",
      description: "A private usenet indexer. Searching it needs an account.",
      language: "en-US", privacy: .privateIndexer, downloadProtocol: .usenet,
      indexerURLs: ["https://private.example.invalid/"],
      fields: [
        field("username", "Username", .textbox, .text(""), order: 0),
        field("password", "Password", .password, .text(""), order: 1),
        field(
          "sort", "Sort requested from site", .select, .option(0), order: 2,
          options: [
            FieldOption(value: 0, name: "created", hint: "Newest first"),
            FieldOption(value: 1, name: "size", hint: nil),
          ]),
        field("retentionDays", "Retention (days)", .number, .number(1440), order: 3),
        field("englishOnly", "English only", .checkbox, .boolean(false), order: 4),
      ]),
    IndexerSchema(
      definitionName: "ExamplePublic", implementation: "Cardigann",
      configContract: "CardigannSettings",
      description: "A public indexer needing no credentials.",
      language: "en-US", privacy: .publicIndexer, downloadProtocol: .usenet,
      indexerURLs: ["https://public.example.invalid/"],
      fields: [
        field("minimumAge", "Minimum age (minutes)", .number, .number(1), order: 0)
      ]),
    IndexerSchema(
      definitionName: "ExampleAwkward", implementation: "Cardigann",
      configContract: "CardigannSettings",
      description: "Has a setting Tower can't render — the fallback state.",
      language: "en-US", privacy: .publicIndexer, downloadProtocol: .usenet,
      indexerURLs: ["https://awkward.example.invalid/"],
      fields: [
        field("baseUrl", "Base URL", .textbox, .text(""), order: 0),
        field("captchaConfig", "Captcha configuration", .unknown, .empty, order: 1),
      ]),
  ]

  private static func field(
    _ name: String, _ label: String, _ kind: FieldKind, _ value: FieldValue, order: Int,
    options: [FieldOption] = []
  ) -> IndexerField {
    IndexerField(
      name: name, label: label, kind: kind, helpText: nil, value: value, options: options,
      isAdvanced: false, isHidden: false, order: order)
  }

  static let stats: [IndexerStats] = [
    IndexerStats(
      indexerID: 1, indexerName: "Brightwater Index", averageResponseTimeMilliseconds: 412,
      queries: 1_284, grabs: 96, failedQueries: 11, failedGrabs: 2),
    IndexerStats(
      indexerID: 2, indexerName: "Kestrel NZB", averageResponseTimeMilliseconds: 268,
      queries: 903, grabs: 141, failedQueries: 3, failedGrabs: 0),
    IndexerStats(
      indexerID: 3, indexerName: "Lanternhub", averageResponseTimeMilliseconds: 4_902,
      queries: 210, grabs: 4, failedQueries: 132, failedGrabs: 9),
  ]

  static func history() -> [ProwlarrHistoryRecord] {
    [
      ProwlarrHistoryRecord(
        id: 1, indexerID: 1, date: Date().addingTimeInterval(-600), isSuccessful: true,
        eventType: "indexerQuery", query: "winter ledger", source: "Radarr"),
      ProwlarrHistoryRecord(
        id: 2, indexerID: 3, date: Date().addingTimeInterval(-1_800), isSuccessful: false,
        eventType: "indexerQuery", query: "northern lights s02", source: "Sonarr"),
      ProwlarrHistoryRecord(
        id: 3, indexerID: 2, date: Date().addingTimeInterval(-7_200), isSuccessful: true,
        eventType: "releaseGrabbed", query: nil, source: "Sonarr"),
    ]
  }
}
