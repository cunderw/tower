import Foundation
import TowerCore

// Prowlarr's wire types. `internal`, like every other service's DTOs.
//
// The hard part is `Field.value`, which is **untyped JSON**: a string for a
// text field, a bool for a checkbox, a number for a select, sometimes an array
// of strings. It has to survive a round trip — Prowlarr's PUT rebuilds the
// indexer from the body, so a value Tower decoded as the wrong type and
// re-encoded would quietly rewrite the user's configuration.

/// Decodes and re-encodes a `Field.value` without losing its type.
struct AnyFieldValue: Codable, Sendable, Hashable {
  let value: FieldValue

  init(_ value: FieldValue) { self.value = value }

  init(from decoder: any Decoder) throws {
    let container = try decoder.singleValueContainer()
    if container.decodeNil() {
      value = .empty
    } else if let bool = try? container.decode(Bool.self) {
      // **Before Double.** JSON `true` decodes as `1` through some number
      // paths, and a checkbox that round-trips as the number 1 stops being a
      // checkbox.
      value = .boolean(bool)
    } else if let number = try? container.decode(Double.self) {
      value = .number(number)
    } else if let string = try? container.decode(String.self) {
      value = .text(string)
    } else if let list = try? container.decode([String].self) {
      value = .list(list)
    } else if let numbers = try? container.decode([Int].self) {
      value = .list(numbers.map(String.init))
    } else {
      // An object or something else Tower doesn't model. Preserved as empty
      // rather than throwing: one unrecognised field must not make the whole
      // indexer undecodable.
      value = .empty
    }
  }

  func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    switch value {
    case .text(let text): try container.encode(text)
    case .number(let number):
      // Whole numbers go back as integers: Prowlarr rejects `"port": 9117.0`
      // on some contracts.
      if number == number.rounded() { try container.encode(Int(number)) } else {
        try container.encode(number)
      }
    case .boolean(let flag): try container.encode(flag)
    case .option(let option): try container.encode(option)
    case .list(let list): try container.encode(list)
    case .empty: try container.encodeNil()
    }
  }
}

struct FieldDTO: Codable, Sendable {
  let name: String?
  let label: String?
  let helpText: String?
  let value: AnyFieldValue?
  let type: String?
  let advanced: Bool?
  let hidden: String?
  let order: Int?
  let selectOptions: [SelectOptionDTO]?

  struct SelectOptionDTO: Codable, Sendable {
    let value: Int?
    let name: String?
    let hint: String?
  }

  var domain: IndexerField {
    let kind = FieldKind(apiValue: type)
    return IndexerField(
      name: name ?? "",
      label: label ?? name ?? "",
      kind: kind,
      helpText: helpText.flatMap { $0.isEmpty ? nil : $0 },
      // A select's value arrives as a number and must become `.option`, not
      // `.number` — otherwise the picker has nothing to match against.
      value: normalised(value?.value ?? .empty, for: kind),
      options: (selectOptions ?? []).compactMap { option in
        guard let value = option.value else { return nil }
        return FieldOption(value: value, name: option.name ?? "", hint: option.hint)
      },
      isAdvanced: advanced ?? false,
      // `hidden` is a *string* on the wire ("hidden", "hiddenIfNotSet", ""),
      // not a bool — one of Prowlarr's odder shapes.
      isHidden: (hidden ?? "").lowercased() == "hidden",
      order: order ?? 0)
  }

  private func normalised(_ value: FieldValue, for kind: FieldKind) -> FieldValue {
    switch (kind, value) {
    case (.select, .number(let number)): .option(Int(number))
    case (.checkbox, .number(let number)): .boolean(number != 0)
    default: value
    }
  }

  init(from field: IndexerField) {
    self.name = field.name
    self.label = field.label
    self.helpText = field.helpText
    self.value = AnyFieldValue(field.value)
    self.type = field.kind == .unknown ? nil : field.kind.rawValue
    self.advanced = field.isAdvanced
    self.hidden = field.isHidden ? "hidden" : nil
    self.order = field.order
    self.selectOptions = field.options.map {
      SelectOptionDTO(value: $0.value, name: $0.name, hint: $0.hint)
    }
  }
}

// MARK: - Indexers

/// `IndexerResource`, decoded *and* re-encoded.
///
/// Prowlarr's PUT rebuilds the indexer from the body, and its validator
/// requires a positive `appProfileId` on a create, every PUT and `/indexer/test`.
/// `unknownFields` carries `appProfileId` and the other fields Tower doesn't
/// model (`redirect`, `downloadClientId`, `added`, ...) so an enable toggle or
/// a test sends the indexer back whole.
struct IndexerDTO: Codable, Sendable {
  let id: Int?
  let name: String?
  let definitionName: String?
  let implementation: String?
  let configContract: String?
  let description: String?
  let language: String?
  /// `var` so a PUT body can be built by copying what was read and
  /// changing one field — see `settingEnabled`.
  var enable: Bool?
  let priority: Int?
  let supportsRss: Bool?
  let supportsSearch: Bool?
  let `protocol`: String?
  let privacy: String?
  let indexerUrls: [String]?
  let fields: [FieldDTO]?
  let tags: [Int]?

  /// Everything Prowlarr sent that this type doesn't model, kept so a PUT or
  /// a test can hand it back untouched.
  let unknownFields: [String: AnyJSON]

  enum CodingKeys: String, CodingKey, CaseIterable {
    case id, name, definitionName, implementation, configContract, description, language
    case enable, priority, supportsRss, supportsSearch, `protocol`, privacy, indexerUrls
    case fields, tags
  }

  /// A key chosen at run time, for writing `unknownFields` into the same
  /// object as the modelled keys.
  private struct DynamicKey: CodingKey {
    let stringValue: String
    var intValue: Int? { nil }
    init(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { nil }
  }

  init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decodeIfPresent(Int.self, forKey: .id)
    name = try container.decodeIfPresent(String.self, forKey: .name)
    definitionName = try container.decodeIfPresent(String.self, forKey: .definitionName)
    implementation = try container.decodeIfPresent(String.self, forKey: .implementation)
    configContract = try container.decodeIfPresent(String.self, forKey: .configContract)
    description = try container.decodeIfPresent(String.self, forKey: .description)
    language = try container.decodeIfPresent(String.self, forKey: .language)
    enable = try container.decodeIfPresent(Bool.self, forKey: .enable)
    priority = try container.decodeIfPresent(Int.self, forKey: .priority)
    supportsRss = try container.decodeIfPresent(Bool.self, forKey: .supportsRss)
    supportsSearch = try container.decodeIfPresent(Bool.self, forKey: .supportsSearch)
    `protocol` = try container.decodeIfPresent(String.self, forKey: .protocol)
    privacy = try container.decodeIfPresent(String.self, forKey: .privacy)
    indexerUrls = try container.decodeIfPresent([String].self, forKey: .indexerUrls)
    fields = try container.decodeIfPresent([FieldDTO].self, forKey: .fields)
    tags = try container.decodeIfPresent([Int].self, forKey: .tags)

    let everything = try decoder.singleValueContainer().decode([String: AnyJSON].self)
    let known = Set(CodingKeys.allCases.map(\.rawValue))
    unknownFields = everything.filter { !known.contains($0.key) }
  }

  func encode(to encoder: any Encoder) throws {
    // What Prowlarr sent first, then the modelled keys. A nil modelled key is
    // left out rather than sent as null.
    var extra = encoder.container(keyedBy: DynamicKey.self)
    for (key, value) in unknownFields {
      try extra.encode(value, forKey: DynamicKey(stringValue: key))
    }
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encodeIfPresent(id, forKey: .id)
    try container.encodeIfPresent(name, forKey: .name)
    try container.encodeIfPresent(definitionName, forKey: .definitionName)
    try container.encodeIfPresent(implementation, forKey: .implementation)
    try container.encodeIfPresent(configContract, forKey: .configContract)
    try container.encodeIfPresent(description, forKey: .description)
    try container.encodeIfPresent(language, forKey: .language)
    try container.encodeIfPresent(enable, forKey: .enable)
    try container.encodeIfPresent(priority, forKey: .priority)
    try container.encodeIfPresent(supportsRss, forKey: .supportsRss)
    try container.encodeIfPresent(supportsSearch, forKey: .supportsSearch)
    try container.encodeIfPresent(`protocol`, forKey: .protocol)
    try container.encodeIfPresent(privacy, forKey: .privacy)
    try container.encodeIfPresent(indexerUrls, forKey: .indexerUrls)
    try container.encodeIfPresent(fields, forKey: .fields)
    try container.encodeIfPresent(tags, forKey: .tags)
  }

  var domain: ProwlarrIndexer {
    ProwlarrIndexer(
      id: id ?? 0,
      name: name ?? definitionName ?? "Indexer",
      definitionName: definitionName,
      implementation: implementation,
      enable: enable,
      protocolValue: `protocol`,
      privacyValue: privacy,
      priority: priority,
      supportsRss: supportsRss,
      supportsSearch: supportsSearch,
      fields: fields,
      tags: tags)
  }

  var schema: IndexerSchema {
    IndexerSchema(
      definitionName: definitionName ?? name ?? "",
      implementation: implementation ?? "",
      configContract: configContract ?? "",
      description: description.flatMap { $0.isEmpty ? nil : $0 },
      language: language.flatMap { $0.isEmpty ? nil : $0 },
      privacy: IndexerPrivacy(apiValue: privacy),
      downloadProtocol: ArrDownloadProtocol(apiValue: `protocol`),
      indexerURLs: indexerUrls ?? [],
      fields: (fields ?? []).map(\.domain).sorted { $0.order < $1.order },
      redirect: unknownFields["redirect"] == .bool(true))
  }

  /// The body for a create or update. Prowlarr's PUT **rebuilds the indexer
  /// from the body**, so everything the schema carried has to go back —
  /// dropping `configContract` or `implementation` is rejected, and dropping a
  /// field silently clears it.
  ///
  /// The schema carries no `appProfileId`, and Prowlarr's validator requires a
  /// positive one, so the caller resolves it and it rides in `unknownFields`.
  /// An update passes nil, because a draft does not carry the indexer's own
  /// profile and the first one by name would move the indexer to it. Prowlarr's
  /// shared validator rejects that PUT, but no screen sends one: editing a draft
  /// is reached only from tests.
  ///
  /// `redirect` rides there too when the schema had it on, because Prowlarr
  /// refuses a Usenet indexer whose definition supports redirect and whose body
  /// leaves it off.
  init(draft: IndexerDraft, appProfileID: Int?) {
    self.id = draft.id
    self.name = draft.name
    self.definitionName = draft.schema.definitionName
    self.implementation = draft.schema.implementation
    self.configContract = draft.schema.configContract
    self.description = draft.schema.description
    self.language = draft.schema.language
    self.enable = draft.isEnabled
    self.priority = draft.priority
    self.supportsRss = nil
    self.supportsSearch = nil
    self.protocol = draft.schema.downloadProtocol.apiValue
    self.privacy = draft.schema.privacy == .unknown ? nil : draft.schema.privacy.rawValue
    self.indexerUrls = draft.schema.indexerURLs
    self.fields = draft.fields.map(FieldDTO.init(from:))
    self.tags = []
    var extra: [String: AnyJSON] = appProfileID.map { ["appProfileId": .int($0)] } ?? [:]
    if draft.schema.redirect { extra["redirect"] = .bool(true) }
    self.unknownFields = extra
  }
}

extension ProwlarrIndexer {
  /// The DTO-side initialiser, kept here so the mapping's defaults live next to
  /// the wire type rather than in the domain.
  fileprivate init(
    id: Int, name: String, definitionName: String?, implementation: String?, enable: Bool?,
    protocolValue: String?, privacyValue: String?, priority: Int?, supportsRss: Bool?,
    supportsSearch: Bool?, fields: [FieldDTO]?, tags: [Int]?
  ) {
    self.init(
      id: id, name: name, definitionName: definitionName, implementation: implementation,
      isEnabled: enable ?? false,
      downloadProtocol: ArrDownloadProtocol(apiValue: protocolValue),
      privacy: IndexerPrivacy(apiValue: privacyValue),
      priority: priority ?? 25,
      supportsRSS: supportsRss ?? false,
      supportsSearch: supportsSearch ?? false,
      fields: (fields ?? []).map(\.domain).sorted { $0.order < $1.order },
      tagIDs: tags ?? [])
  }
}

/// `AppProfileResource`, reduced to what picking a default needs.
struct AppProfileDTO: Decodable, Sendable {
  let id: Int?
  let name: String?
}

/// `/indexerstatus` — which indexers Prowlarr has taken out of rotation.
struct IndexerStatusDTO: Decodable, Sendable {
  let indexerId: Int?
  let mostRecentFailure: Date?
  let disabledTill: Date?
  let initialFailure: Date?
}

// MARK: - Test

struct ValidationFailureDTO: Decodable, Sendable {
  let errorMessage: String?
  let propertyName: String?
}

// MARK: - Stats

struct IndexerStatsResourceDTO: Decodable, Sendable {
  let indexers: [IndexerStatisticsDTO]?

  struct IndexerStatisticsDTO: Decodable, Sendable {
    let indexerId: Int?
    let indexerName: String?
    let averageResponseTime: Int?
    let numberOfQueries: Int?
    let numberOfGrabs: Int?
    let numberOfFailedQueries: Int?
    let numberOfFailedGrabs: Int?

    var domain: IndexerStats {
      IndexerStats(
        indexerID: indexerId ?? 0,
        indexerName: indexerName ?? "Indexer",
        averageResponseTimeMilliseconds: averageResponseTime ?? 0,
        queries: numberOfQueries ?? 0,
        grabs: numberOfGrabs ?? 0,
        failedQueries: numberOfFailedQueries ?? 0,
        failedGrabs: numberOfFailedGrabs ?? 0)
    }
  }
}

// MARK: - History

struct ProwlarrHistoryPageDTO: Decodable, Sendable {
  let records: [ProwlarrHistoryDTO]?
}

struct ProwlarrHistoryDTO: Decodable, Sendable {
  let id: Int?
  let indexerId: Int?
  let date: Date?
  let successful: Bool?
  let eventType: String?
  /// A loose bag of strings whose keys vary by event type.
  let data: [String: String]?

  var domain: ProwlarrHistoryRecord {
    ProwlarrHistoryRecord(
      id: id ?? 0,
      indexerID: indexerId,
      date: date,
      isSuccessful: successful ?? true,
      eventType: eventType ?? "unknown",
      query: data?["query"],
      source: data?["source"] ?? data?["title"])
  }
}
