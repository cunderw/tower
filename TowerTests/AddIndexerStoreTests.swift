import Foundation
import Testing
import TowerCore
import TowerData

@testable import Tower

/// The schema-driven add-indexer form — the payoff for the Prowlarr field
/// mapping, and the place a mistake produces an indexer that saves and then
/// never works.
@MainActor
@Suite
struct AddIndexerStoreTests {
  private func field(
    _ name: String, _ kind: FieldKind, _ value: FieldValue, order: Int = 0,
    options: [FieldOption] = [], hidden: Bool = false
  ) -> IndexerField {
    IndexerField(
      name: name, label: name.capitalized, kind: kind, helpText: nil, value: value,
      options: options, isAdvanced: false, isHidden: hidden, order: order)
  }

  /// A definition with one of every supported kind, plus a hidden field and an
  /// unrenderable one.
  private func schema(
    name: String = "ExamplePrivate", includeUnsupported: Bool = false
  ) -> IndexerSchema {
    var fields = [
      field("username", .textbox, .text(""), order: 0),
      field("password", .password, .text(""), order: 1),
      field(
        "sort", .select, .option(0), order: 2,
        options: [
          FieldOption(value: 0, name: "created", hint: nil),
          FieldOption(value: 1, name: "size", hint: nil),
        ]),
      field("retentionDays", .number, .number(1440), order: 3),
      field("englishOnly", .checkbox, .boolean(false), order: 4),
      field("internalToken", .textbox, .text("x"), order: 5, hidden: true),
    ]
    if includeUnsupported {
      fields.append(field("weirdThing", .unknown, .empty, order: 6))
    }
    return IndexerSchema(
      definitionName: name, implementation: "Cardigann",
      configContract: "CardigannSettings", description: "An example.", language: "en-US",
      privacy: .privateIndexer, downloadProtocol: .usenet,
      indexerURLs: ["https://private.example.invalid/"], fields: fields)
  }

  private func makeStore(
    _ schemas: [IndexerSchema]
  ) async -> (AddIndexerStore, StubProwlarrRepository, ProwlarrIndexersStore) {
    let repository = StubProwlarrRepository(indexers: [], stats: [])
    repository.schemaList = schemas
    let list = ProwlarrIndexersStore(repository: repository)
    await list.load()
    let store = AddIndexerStore(repository: repository, indexersStore: list)
    await store.load()
    return (store, repository, list)
  }

  // MARK: - Picking a definition

  @Test func definitionsAreListedAndSearchable() async {
    let (store, _, _) = await makeStore([schema(name: "Alpha"), schema(name: "Beta")])

    #expect(store.state.value?.count == 2)
    store.searchText = "bet"
    #expect(store.filteredSchemas.map(\.definitionName) == ["Beta"])
  }

  @Test func choosingADefinitionBuildsADraftAtItsDefaults() async {
    let (store, _, _) = await makeStore([schema()])

    store.choose(store.state.value![0])

    let draft = try! #require(store.draft)
    #expect(draft.name == "ExamplePrivate")
    #expect(draft.isEnabled)
    // Hidden fields are not part of the form.
    #expect(!draft.fields.contains { $0.name == "internalToken" })
    #expect(draft.fields.first { $0.name == "retentionDays" }?.value == .number(1440))
  }

  // MARK: - Every supported kind renders and submits

  @Test func everySupportedFieldKindIsRenderableAndSubmitsItsEditedValue() async {
    let (store, repository, _) = await makeStore([schema()])
    store.choose(store.state.value![0])

    // All five supported kinds are offered to the renderer.
    #expect(
      Set(store.renderableFields.map(\.kind))
        == [.textbox, .password, .select, .number, .checkbox])
    #expect(store.unsupportedFields.isEmpty)

    // Edit one of each and submit.
    let byName = Dictionary(
      store.renderableFields.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })
    store.setValue(.text("alex"), for: byName["username"]!)
    store.setValue(.text("hunter2"), for: byName["password"]!)
    store.setValue(.option(1), for: byName["sort"]!)
    store.setValue(.number(2880), for: byName["retentionDays"]!)
    store.setValue(.boolean(true), for: byName["englishOnly"]!)

    #expect(await store.save())

    let saved = try! #require(repository.saved.last)
    let values = Dictionary(
      saved.fields.map { ($0.name, $0.value) }, uniquingKeysWith: { first, _ in first })
    #expect(values["username"] == .text("alex"))
    #expect(values["password"] == .text("hunter2"))
    // A select stays an option, not a number — the round trip the field
    // mapping guards.
    #expect(values["sort"] == .option(1))
    #expect(values["retentionDays"] == .number(2880))
    #expect(values["englishOnly"] == .boolean(true))
  }

  // MARK: - Unsupported fields

  @Test func anUnsupportedFieldIsReportedRatherThanSilentlyDropped() async {
    // Silently omitting a required field saves an indexer that never works,
    // with nothing on screen explaining why. This is the main risk of a
    // schema-driven form.
    let (store, _, _) = await makeStore([schema(includeUnsupported: true)])
    store.choose(store.state.value![0])

    #expect(store.hasUnsupportedFields)
    #expect(store.unsupportedFields.map(\.name) == ["weirdThing"])
    // And it is kept out of the renderable set rather than drawn as a broken
    // control.
    #expect(!store.renderableFields.contains { $0.name == "weirdThing" })
  }

  @Test func anUnsupportedFieldStillSavesWithItsOriginalValue() async {
    // The fallback is "save here, finish in the web UI" — which only works if
    // the value Prowlarr sent is sent back untouched.
    let (store, repository, _) = await makeStore([schema(includeUnsupported: true)])
    store.choose(store.state.value![0])

    #expect(await store.save())

    let saved = try! #require(repository.saved.last)
    #expect(saved.fields.contains { $0.name == "weirdThing" }, "the field was dropped")
  }

  @Test func aDefinitionWithNoUnsupportedFieldsSaysNothingAboutThem() async {
    let (store, _, _) = await makeStore([schema()])
    store.choose(store.state.value![0])

    #expect(!store.hasUnsupportedFields)
  }

  // MARK: - Test before save

  @Test func testReportsTheIndexersActualResult() async {
    let (store, repository, _) = await makeStore([schema()])
    store.choose(store.state.value![0])

    await store.test()
    #expect(store.testResult?.isSuccess == true)

    repository.testPasses = false
    await store.test()
    #expect(store.testResult?.isSuccess == false)
    #expect(store.testResult?.messages.first == "Invalid credentials")
  }

  @Test func aServiceThatWontAnswerTheTestIsAFailureNotSilence() async {
    let (store, repository, _) = await makeStore([schema()])
    store.choose(store.state.value![0])
    repository.failActions = true

    await store.test()

    #expect(store.testResult?.isSuccess == false)
    #expect(store.testResult?.messages.isEmpty == false)
  }

  @Test func editingAFieldInvalidatesTheLastTestResult() async {
    // Reporting "passed" next to a credential the user just changed is a lie.
    let (store, _, _) = await makeStore([schema()])
    store.choose(store.state.value![0])
    await store.test()
    #expect(store.testResult != nil)

    store.setValue(.text("changed"), for: store.renderableFields[0])

    #expect(store.testResult == nil, "a stale test result survived an edit")
  }

  // MARK: - The saved indexer appears

  @Test func savingPutsTheIndexerInTheListBehindTheSheet() async {
    let (store, _, list) = await makeStore([schema()])
    store.choose(store.state.value![0])
    #expect(list.state.value?.isEmpty == true)

    #expect(await store.save())

    #expect(list.state.value?.count == 1, "the saved indexer never reached the list")
    #expect(list.state.value?.first?.name == "ExamplePrivate")
    #expect(store.draft == nil, "the draft survived a successful save")
  }

  @Test func aRejectedSaveKeepsTheFormAndEverythingTypedIntoIt() async {
    // A rejected save is usually one wrong field, not a reason to fill the
    // whole form in again.
    let (store, repository, _) = await makeStore([schema()])
    store.choose(store.state.value![0])
    store.setValue(.text("alex"), for: store.renderableFields[0])
    repository.failActions = true

    #expect(await store.save() == false)

    #expect(store.saveError != nil)
    let draft = try! #require(store.draft)
    #expect(draft.fields.first { $0.name == "username" }?.value == .text("alex"))
  }

  @Test func anUnnamedIndexerCannotBeSaved() async {
    let (store, _, _) = await makeStore([schema()])
    store.choose(store.state.value![0])

    store.setName("   ")

    #expect(!store.canSave)
  }

  // MARK: - Editing

  @Test func editingMergesSavedValuesOverTheSchemasDefaults() async {
    // A field the schema gained since the indexer was created still appears —
    // with its default rather than missing entirely.
    let (store, _, _) = await makeStore([schema()])
    let existing = ProwlarrIndexer(
      id: 7, name: "My Indexer", definitionName: "ExamplePrivate",
      implementation: "Cardigann", isEnabled: false, downloadProtocol: .usenet,
      privacy: .privateIndexer, priority: 10, supportsRSS: true, supportsSearch: true,
      fields: [field("username", .textbox, .text("saved-user"))], tagIDs: [])

    store.edit(existing, schema: store.state.value![0])

    let draft = try! #require(store.draft)
    #expect(draft.id == 7)
    #expect(draft.name == "My Indexer")
    #expect(!draft.isEnabled)
    #expect(draft.priority == 10)
    // The saved value won.
    #expect(draft.fields.first { $0.name == "username" }?.value == .text("saved-user"))
    // The field the saved indexer didn't have is present at its default.
    #expect(draft.fields.first { $0.name == "retentionDays" }?.value == .number(1440))
  }

  @Test func savingAnEditUpdatesTheRowRatherThanAddingOne() async {
    let repository = StubProwlarrRepository(
      indexers: [
        ProwlarrIndexer(
          id: 7, name: "My Indexer", definitionName: "ExamplePrivate",
          implementation: "Cardigann", isEnabled: true, downloadProtocol: .usenet,
          privacy: .privateIndexer, priority: 25, supportsRSS: true, supportsSearch: true,
          fields: [], tagIDs: [])
      ], stats: [])
    repository.schemaList = [schema()]
    let list = ProwlarrIndexersStore(repository: repository)
    await list.load()
    let store = AddIndexerStore(repository: repository, indexersStore: list)
    await store.load()

    store.edit(list.state.value![0], schema: store.state.value![0])
    store.setName("Renamed")
    #expect(await store.save())

    #expect(list.state.value?.count == 1, "an edit added a duplicate row")
    #expect(list.state.value?.first?.name == "Renamed")
  }
}
