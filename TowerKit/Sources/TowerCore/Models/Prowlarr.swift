import Foundation

// Prowlarr's domain types. Plain `TowerCore`, like every other service.
//
// The interesting one here is `IndexerField`: Prowlarr describes each
// indexer's configuration as a **schema** — a list of typed fields the client
// is expected to render a form from — so the add-indexer screen is generated
// rather than hand-written per indexer. That is the whole reason a value type
// for "some JSON scalar" has to exist in the domain.

/// A configuration value, as Prowlarr sends and accepts it.
///
/// Prowlarr's `Field.value` is untyped on the wire: a text field's value is a
/// string, a checkbox's is a bool, a select's is a number. Modelling it as a
/// small closed enum keeps the form generic without leaking `Any` — which
/// would be neither `Sendable` nor `Equatable`, and both matter for a value a
/// SwiftUI form binds to.
public enum FieldValue: Sendable, Hashable {
  case text(String)
  case number(Double)
  case boolean(Bool)
  /// A select's chosen option, by its numeric value.
  case option(Int)
  case list([String])
  case empty

  public var stringValue: String {
    switch self {
    case .text(let value): value
    case .number(let value): value == value.rounded() ? String(Int(value)) : String(value)
    case .boolean(let value): value ? "true" : "false"
    case .option(let value): String(value)
    case .list(let values): values.joined(separator: ",")
    case .empty: ""
    }
  }

  public var boolValue: Bool {
    switch self {
    case .boolean(let value): value
    case .number(let value): value != 0
    case .text(let value): value.lowercased() == "true"
    default: false
    }
  }

  public var intValue: Int? {
    switch self {
    case .option(let value): value
    case .number(let value): Int(value)
    case .text(let value): Int(value)
    default: nil
    }
  }
}

/// How a field should be rendered. Prowlarr's own `type` strings, mapped so a
/// form can switch on a case rather than a string.
public enum FieldKind: String, Sendable, Hashable {
  case textbox
  case password
  case number
  case checkbox
  case select
  case tag
  case textArea = "textbox_large"
  case unknown

  public init(apiValue: String?) {
    switch (apiValue ?? "").lowercased() {
    case "textbox": self = .textbox
    case "password": self = .password
    case "number": self = .number
    case "checkbox": self = .checkbox
    case "select", "indexerselect", "downloadclientselect": self = .select
    case "tag", "tagselect": self = .tag
    case "textarea", "textbox_large": self = .textArea
    default: self = .unknown
    }
  }

  /// Whether the value should be obscured on screen and never logged.
  public var isSecret: Bool { self == .password }
}

public struct FieldOption: Sendable, Hashable, Identifiable {
  public let value: Int
  public let name: String
  public let hint: String?

  public var id: Int { value }

  public init(value: Int, name: String, hint: String?) {
    self.value = value
    self.name = name
    self.hint = hint
  }
}

/// One configuration field of an indexer.
public struct IndexerField: Sendable, Hashable, Identifiable {
  public let name: String
  public let label: String
  public let kind: FieldKind
  public let helpText: String?
  public var value: FieldValue
  public let options: [FieldOption]
  /// Prowlarr's "advanced" flag — fields its own UI hides behind a toggle.
  public let isAdvanced: Bool
  public let isHidden: Bool
  public let order: Int

  public var id: String { name }

  public init(
    name: String, label: String, kind: FieldKind, helpText: String?, value: FieldValue,
    options: [FieldOption], isAdvanced: Bool, isHidden: Bool, order: Int
  ) {
    self.name = name
    self.label = label
    self.kind = kind
    self.helpText = helpText
    self.value = value
    self.options = options
    self.isAdvanced = isAdvanced
    self.isHidden = isHidden
    self.order = order
  }
}

public enum IndexerPrivacy: String, Sendable, Hashable {
  case publicIndexer = "public"
  case semiPrivate = "semiPrivate"
  case privateIndexer = "private"
  case unknown

  public init(apiValue: String?) {
    self = IndexerPrivacy(rawValue: apiValue ?? "") ?? .unknown
  }

  public var displayName: String {
    switch self {
    case .publicIndexer: "Public"
    case .semiPrivate: "Semi-private"
    case .privateIndexer: "Private"
    case .unknown: "Unknown"
    }
  }
}

/// A configured indexer.
public struct ProwlarrIndexer: Sendable, Hashable, Identifiable {
  public let id: Int
  public let name: String
  /// The definition this was created from — "ExampleIndexer". Needed to
  /// re-fetch its schema when editing.
  public let definitionName: String?
  public let implementation: String?
  public let isEnabled: Bool
  public let downloadProtocol: ArrDownloadProtocol
  public let privacy: IndexerPrivacy
  public let priority: Int
  public let supportsRSS: Bool
  public let supportsSearch: Bool
  public let fields: [IndexerField]
  public let tagIDs: [Int]
  /// Prowlarr's per-indexer status: non-nil when it is currently failing, with
  /// the reason and when it will be retried.
  public var failureMessage: String?
  public var disabledUntil: Date?

  /// Whether Prowlarr has taken this indexer out of rotation after failures —
  /// distinct from the user disabling it, and the thing the list has to
  /// surface.
  public var isFailing: Bool { failureMessage != nil || disabledUntil != nil }

  public init(
    id: Int, name: String, definitionName: String?, implementation: String?, isEnabled: Bool,
    downloadProtocol: ArrDownloadProtocol, privacy: IndexerPrivacy, priority: Int,
    supportsRSS: Bool, supportsSearch: Bool, fields: [IndexerField], tagIDs: [Int],
    failureMessage: String? = nil, disabledUntil: Date? = nil
  ) {
    self.id = id
    self.name = name
    self.definitionName = definitionName
    self.implementation = implementation
    self.isEnabled = isEnabled
    self.downloadProtocol = downloadProtocol
    self.privacy = privacy
    self.priority = priority
    self.supportsRSS = supportsRSS
    self.supportsSearch = supportsSearch
    self.fields = fields
    self.tagIDs = tagIDs
    self.failureMessage = failureMessage
    self.disabledUntil = disabledUntil
  }
}

/// A definition from `/indexer/schema` — the template the add-indexer form is
/// generated from.
public struct IndexerSchema: Sendable, Hashable, Identifiable {
  public let definitionName: String
  public let implementation: String
  public let configContract: String
  public let description: String?
  public let language: String?
  public let privacy: IndexerPrivacy
  public let downloadProtocol: ArrDownloadProtocol
  public let indexerURLs: [String]
  public let fields: [IndexerField]
  /// Whether the definition arrives with redirect on. Prowlarr refuses a
  /// Usenet indexer with redirect off when its definition supports redirect,
  /// so a draft built from this schema has to send it back on.
  public let redirect: Bool

  public var id: String { definitionName }

  public init(
    definitionName: String, implementation: String, configContract: String, description: String?,
    language: String?, privacy: IndexerPrivacy, downloadProtocol: ArrDownloadProtocol,
    indexerURLs: [String], fields: [IndexerField], redirect: Bool = false
  ) {
    self.definitionName = definitionName
    self.implementation = implementation
    self.configContract = configContract
    self.description = description
    self.language = language
    self.privacy = privacy
    self.downloadProtocol = downloadProtocol
    self.indexerURLs = indexerURLs
    self.fields = fields
    self.redirect = redirect
  }
}

/// What the add/edit form submits.
public struct IndexerDraft: Sendable, Hashable {
  /// `nil` for a new indexer; the existing id when editing.
  public var id: Int?
  public var name: String
  public var isEnabled: Bool
  public var priority: Int
  public var fields: [IndexerField]
  public let schema: IndexerSchema

  public init(
    id: Int? = nil, name: String, isEnabled: Bool = true, priority: Int = 25,
    fields: [IndexerField], schema: IndexerSchema
  ) {
    self.id = id
    self.name = name
    self.isEnabled = isEnabled
    self.priority = priority
    self.fields = fields
    self.schema = schema
  }

  /// A draft prefilled from a schema — every field at its default.
  public init(schema: IndexerSchema) {
    self.init(
      name: schema.definitionName,
      fields: schema.fields.filter { !$0.isHidden },
      schema: schema)
  }
}

/// The result of testing an indexer.
public struct IndexerTestResult: Sendable, Hashable {
  public let isSuccess: Bool
  /// Prowlarr's own words. A test failure explains itself better than any
  /// rewording here could — usually a wrong cookie or a dead URL.
  public let messages: [String]

  public init(isSuccess: Bool, messages: [String]) {
    self.isSuccess = isSuccess
    self.messages = messages
  }
}

/// Per-indexer counters from `/indexerstats`.
public struct IndexerStats: Sendable, Hashable, Identifiable {
  public let indexerID: Int
  public let indexerName: String
  public let averageResponseTimeMilliseconds: Int
  public let queries: Int
  public let grabs: Int
  public let failedQueries: Int
  public let failedGrabs: Int

  public var id: Int { indexerID }

  /// 0…1. Nil when nothing has been asked of it yet — a brand-new indexer is
  /// not "0% successful".
  public var successRate: Double? {
    guard queries > 0 else { return nil }
    return Double(queries - failedQueries) / Double(queries)
  }

  public init(
    indexerID: Int, indexerName: String, averageResponseTimeMilliseconds: Int, queries: Int,
    grabs: Int, failedQueries: Int, failedGrabs: Int
  ) {
    self.indexerID = indexerID
    self.indexerName = indexerName
    self.averageResponseTimeMilliseconds = averageResponseTimeMilliseconds
    self.queries = queries
    self.grabs = grabs
    self.failedQueries = failedQueries
    self.failedGrabs = failedGrabs
  }
}

/// One row of Prowlarr's history.
public struct ProwlarrHistoryRecord: Sendable, Hashable, Identifiable {
  public let id: Int
  public let indexerID: Int?
  public let date: Date?
  public let isSuccessful: Bool
  public let eventType: String
  /// Prowlarr puts these in a loose `data` bag whose keys vary by event type;
  /// the query and its source (the release title when there is no source) are
  /// the two worth showing, so they are lifted out.
  public let query: String?
  public let source: String?

  public init(
    id: Int, indexerID: Int?, date: Date?, isSuccessful: Bool, eventType: String,
    query: String?, source: String?
  ) {
    self.id = id
    self.indexerID = indexerID
    self.date = date
    self.isSuccessful = isSuccessful
    self.eventType = eventType
    self.query = query
    self.source = source
  }
}
