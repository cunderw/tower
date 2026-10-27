import Foundation
import Observation
import TowerCore
import TowerData

/// The add-indexer flow: pick a definition, fill in the form Prowlarr
/// describes, test it, save it.
///
/// **The form is generated, not written.** Prowlarr knows hundreds of
/// indexers, each with its own fields; hardcoding forms would be a
/// never-finished job. The renderer switches on `FieldKind`, and a kind it
/// cannot render is reported rather than dropped — silently omitting a
/// required field produces an indexer that saves and then never works, which
/// is worse than saying "configure this one in the web UI".
@MainActor
@Observable
final class AddIndexerStore: LoadingStore, Identifiable {
  let id = UUID()

  /// The definition list.
  var state: Loadable<[IndexerSchema]> = .idle
  let loads = LoadTracker()

  var searchText: String = ""

  /// The definition being configured, once one is picked.
  private(set) var draft: IndexerDraft?
  private(set) var isSaving = false
  private(set) var isTesting = false
  private(set) var testResult: IndexerTestResult?
  private(set) var saveError: AppError?

  private let repository: any ProwlarrRepositoryProtocol
  /// Told about the saved indexer so it appears in the list behind the sheet.
  private let indexersStore: ProwlarrIndexersStore?

  init(
    repository: any ProwlarrRepositoryProtocol,
    indexersStore: ProwlarrIndexersStore? = nil
  ) {
    self.repository = repository
    self.indexersStore = indexersStore
  }

  func load() async {
    await load { [self] in try await repository.schemas() }
  }

  var filteredSchemas: [IndexerSchema] {
    guard let schemas = state.value else { return [] }
    let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !query.isEmpty else { return schemas }
    return schemas.filter {
      $0.definitionName.localizedCaseInsensitiveContains(query)
        || $0.description?.localizedCaseInsensitiveContains(query) == true
    }
  }

  // MARK: - The draft

  func choose(_ schema: IndexerSchema) {
    draft = IndexerDraft(schema: schema)
    testResult = nil
    saveError = nil
  }

  /// Opens an existing indexer for editing. Its saved values are merged over
  /// the schema's defaults, so a field the schema gained since it was created
  /// still appears — with its default rather than missing entirely. No screen
  /// opens an existing indexer yet; only the tests call this.
  func edit(_ indexer: ProwlarrIndexer, schema: IndexerSchema) {
    let saved = Dictionary(
      indexer.fields.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })
    let merged = schema.fields
      .filter { !$0.isHidden }
      .map { field -> IndexerField in
        guard let savedField = saved[field.name] else { return field }
        var field = field
        field.value = savedField.value
        return field
      }
    draft = IndexerDraft(
      id: indexer.id, name: indexer.name, isEnabled: indexer.isEnabled,
      priority: indexer.priority, fields: merged, schema: schema)
    testResult = nil
    saveError = nil
  }

  func cancelDraft() {
    draft = nil
    testResult = nil
    saveError = nil
  }

  func setName(_ name: String) {
    draft?.name = name
  }

  func setEnabled(_ isEnabled: Bool) {
    draft?.isEnabled = isEnabled
  }

  func setValue(_ value: FieldValue, for field: IndexerField) {
    guard var draft else { return }
    draft.fields = draft.fields.map { existing in
      guard existing.name == field.name else { return existing }
      var updated = existing
      updated.value = value
      return updated
    }
    // A changed field invalidates the last test — reporting "passed" next to
    // a credential the user just edited is a lie.
    testResult = nil
    self.draft = draft
  }

  /// The fields the renderer can draw.
  var renderableFields: [IndexerField] {
    (draft?.fields ?? []).filter { $0.kind != .unknown }
  }

  /// The fields it cannot, which the sheet reports rather than dropping.
  ///
  /// **Silently omitting these is the failure mode this exists to prevent.**
  /// A required field left out of the payload saves an indexer that never
  /// works, and the user has no way to tell why.
  var unsupportedFields: [IndexerField] {
    (draft?.fields ?? []).filter { $0.kind == .unknown }
  }

  var hasUnsupportedFields: Bool { !unsupportedFields.isEmpty }

  var canSave: Bool {
    guard let draft, !isSaving, !isTesting else { return false }
    return !draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  // MARK: - Test and save

  /// Tests the draft as configured, without saving it.
  func test() async {
    guard let draft, !isTesting else { return }
    isTesting = true
    defer { isTesting = false }
    testResult = (try? await repository.test(draft))
      ?? IndexerTestResult(
        isSuccess: false, messages: ["\(repository.instance.name) didn't answer the test."])
  }

  /// Saves and hands the result to the list. Returns true when the sheet
  /// should close.
  func save() async -> Bool {
    guard let draft, canSave else { return false }
    isSaving = true
    saveError = nil
    defer { isSaving = false }

    do {
      let saved = try await repository.save(draft)
      // The indexer has to *appear in the list* at once, so the list is told
      // rather than left to a refresh that may not happen.
      indexersStore?.upsert(saved)
      self.draft = nil
      return true
    } catch {
      // The sheet stays open carrying everything typed: a rejected save is
      // usually one wrong field, not a reason to fill the form in again.
      saveError = AppError.wrapping(error)
      return false
    }
  }
}
