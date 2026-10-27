import XCTest

/// Overseerr and Prowlarr smoke paths through **demo mode** — the same
/// approach as `ArrDemoSmokeUITests` and `DownloadClientDemoUITests`, and for
/// the same reason: these screens have no DEBUG seeded fake, so demo mode is
/// the only way to reach them, and it is the path an App Store reviewer takes.
@MainActor
final class OverseerrProwlarrDemoUITests: XCTestCase {
  /// `DemoServices` numbers instances by `DemoServices.idSuffix`'s name list:
  /// Overseerr is 6, Prowlarr 7.
  private let overseerr = "D0000000-0000-0000-0000-000000000006"
  private let prowlarr = "D0000000-0000-0000-0000-000000000007"

  override func setUp() {
    super.setUp()
    continueAfterFailure = false
  }

  private func launchIntoDemo() -> XCUIApplication {
    let app = XCUIApplication()
    app.launchArguments = ["--uitest-reset-credentials"]
    app.launch()
    let demo = app.buttons["connect.demo"]
    XCTAssertTrue(demo.waitForExistence(timeout: 15), "the connect screen offered no demo")
    demo.tap()
    return app
  }

  private func openService(_ id: String, in app: XCUIApplication) {
    // Back to the tab bar first: with the iPad sidebar showing, "Services"
    // matches the collapsible section header as well as the tab, and tapping
    // the header collapses the rows this then looks for.
    useTabBarLayout(in: app)
    app.buttons["Services"].firstMatch.tap()
    let row = app.descendants(matching: .any).matching(identifier: "services.row.\(id)").firstMatch
    XCTAssertTrue(scrollTo(row, in: app), "the demo hub never offered \(id)")
    row.tap()
  }

  private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
    app.descendants(matching: .any).matching(identifier: identifier).firstMatch
  }

  private func anyRow(prefix: String, in app: XCUIApplication) -> XCUIElement {
    app.descendants(matching: .any)
      .matching(NSPredicate(format: "identifier BEGINSWITH %@", prefix)).firstMatch
  }

  @discardableResult
  private func reveal(_ element: XCUIElement, in app: XCUIApplication) -> Bool {
    scrollTo(element, in: app, attempts: 12)
  }

  /// Waits for something to *go away*. Each UI-test class here keeps its own
  /// copy rather than sharing one, which is the existing convention in this
  /// suite (`RadarrLibraryUITests`, `DockerUITests`, `NotificationUITests`).
  private func waitForNonExistence(of element: XCUIElement, timeout: TimeInterval = 15) -> Bool {
    let gone = XCTNSPredicateExpectation(
      predicate: NSPredicate(format: "exists == false"), object: element)
    return XCTWaiter().wait(for: [gone], timeout: timeout) == .completed
  }

  // MARK: - Overseerr: approve a request

  func testApprovingARequestTakesItOutOfPending() {
    let app = launchIntoDemo()
    openService(overseerr, in: app)

    let row = anyRow(prefix: "overseerr.row.", in: app)
    XCTAssertTrue(row.waitForExistence(timeout: 20), "the demo requests list never loaded")
    // Capture which row, so its disappearance can be asserted rather than
    // "some row went away".
    let identifier = row.identifier
    row.tap()

    // Addressed by its own control rather than a container identifier: one on
    // the enclosing Group overwrites the identifier of the "gone" state.
    let approve = element("overseerr.detail.approve", in: app)
    XCTAssertTrue(reveal(approve, in: app), "no approve button on a pending request")
    approve.tap()

    // The detail says the request is handled, because the pending list no
    // longer contains it.
    XCTAssertTrue(
      element("overseerr.detail.gone", in: app).waitForExistence(timeout: 20),
      "the request stayed pending after approval")

    tapBack(in: app)
    XCTAssertTrue(
      waitForNonExistence(of: element(identifier, in: app)),
      "the approved request is still in the pending list")
  }

  func testDecliningAsksFirst() {
    let app = launchIntoDemo()
    openService(overseerr, in: app)
    let row = anyRow(prefix: "overseerr.row.", in: app)
    XCTAssertTrue(row.waitForExistence(timeout: 20))
    row.tap()

    let decline = element("overseerr.detail.decline", in: app)
    XCTAssertTrue(reveal(decline, in: app), "no decline button")
    decline.tap()

    // A confirmation, not an immediate decline — telling someone no is the
    // half that can't be undone by repeating it.
    XCTAssertTrue(
      element("overseerr.detail.confirmDecline", in: app).waitForExistence(timeout: 10),
      "declining didn't ask first")
  }

  // MARK: - Overseerr: issues

  func testCommentingOnAnIssueAppearsInTheThread() {
    let app = launchIntoDemo()
    openService(overseerr, in: app)
    XCTAssertTrue(anyRow(prefix: "overseerr.row.", in: app).waitForExistence(timeout: 20))

    app.buttons["Issues"].firstMatch.tap()
    let issue = anyRow(prefix: "overseerr.issue.row.", in: app)
    XCTAssertTrue(issue.waitForExistence(timeout: 20), "the demo has no open issue")
    issue.tap()

    XCTAssertTrue(element("overseerr.issue.detail", in: app).waitForExistence(timeout: 20))
    let field = element("overseerr.issue.commentField", in: app)
    XCTAssertTrue(reveal(field, in: app), "no comment field")
    field.tap()
    field.typeText("Checked again from Tower.")

    let post = element("overseerr.issue.postComment", in: app)
    XCTAssertTrue(reveal(post, in: app))
    post.tap()

    let posted = app.staticTexts
      .containing(NSPredicate(format: "label CONTAINS 'Checked again from Tower.'"))
      .firstMatch
    XCTAssertTrue(
      posted.waitForExistence(timeout: 20), "the comment never reached the thread")
  }

  // MARK: - Prowlarr: the indexer list

  func testTheIndexerListShowsAFailingIndexerAndTestsOne() {
    let app = launchIntoDemo()
    openService(prowlarr, in: app)

    XCTAssertTrue(
      element("prowlarr.failingCount", in: app).waitForExistence(timeout: 20),
      "the demo has no failing indexer to surface")

    // Test lives behind a leading swipe, so the row has to be swiped before the
    // button exists at all. Tapped only *if* it appeared, and asserted on the
    // row's resulting state — a leading swipe in a narrow iPad column travels
    // far enough to commit the action instead of parking the row open
    // (CLAUDE.md, "A `swipeRight()` in the split view's narrow list column
    // commits the action").
    let row = element("prowlarr.toggle.3", in: app)
    XCTAssertTrue(row.waitForExistence(timeout: 20), "the failing indexer's row never appeared")
    row.swipeRight()

    let test = element("prowlarr.test.3", in: app)
    if test.waitForExistence(timeout: 5), test.isHittable {
      test.tap()
    }
    // Either the tap landed or the swipe committed it; both end in a result on
    // the row, and the demo's failing indexer fails its test.
    XCTAssertTrue(
      element("prowlarr.testResult.3", in: app).waitForExistence(timeout: 25),
      "testing the failing indexer reported nothing")
  }

  func testTheStatsSectionRenders() {
    let app = launchIntoDemo()
    openService(prowlarr, in: app)
    XCTAssertTrue(anyRow(prefix: "prowlarr.toggle.", in: app).waitForExistence(timeout: 20))

    app.buttons["Stats"].firstMatch.tap()

    XCTAssertTrue(
      anyRow(prefix: "prowlarr.stats.", in: app).waitForExistence(timeout: 20),
      "the demo reported no indexer stats")
  }

  // MARK: - Prowlarr: add an indexer

  func testAddingAnIndexerPutsItInTheList() {
    let app = launchIntoDemo()
    openService(prowlarr, in: app)
    XCTAssertTrue(anyRow(prefix: "prowlarr.toggle.", in: app).waitForExistence(timeout: 20))

    element("prowlarr.add", in: app).tap()

    // **`ExampleAwkward`, not `ExamplePublic`, and deliberately so.** The
    // definition list is sorted, and on iPad's centered form sheet a tap on
    // anything below the first row does not land — the row sits under the
    // keyboard the search field raised. `ExampleAwkward` sorts first, so this
    // exercises the same flow on both idioms rather than passing on iPhone and
    // needing a skip on iPad.
    //
    // It also happens to be the better subject: it carries a field the renderer
    // can't draw, so saving it proves the unsupported-field fallback really
    // does save rather than merely warn.
    let definition = element("prowlarr.add.definition.ExampleAwkward", in: app)
    XCTAssertTrue(reveal(definition, in: app), "the demo offered no definitions")
    definition.tap()

    // Asserted on the fallback section, which is the one part of the generated
    // form whose identifier reaches the tree on both idioms. The Name field and
    // the generated field rows are `LabeledContent`, which merges its label and
    // its control, and the toolbar's Save does not surface under its
    // identifier inside the iPad form sheet.
    XCTAssertTrue(
      reveal(element("prowlarr.add.unsupported", in: app), in: app),
      "the configuration form never opened")

    // Save by identifier, falling back to its label for the same reason.
    var save = element("prowlarr.add.save", in: app)
    if !save.waitForExistence(timeout: 5) {
      save = app.buttons["Save"].firstMatch
    }
    XCTAssertTrue(save.waitForExistence(timeout: 15), "no Save in the add sheet")
    save.tap()

    let added = app.staticTexts
      .containing(NSPredicate(format: "label CONTAINS 'ExampleAwkward'")).firstMatch
    XCTAssertTrue(
      reveal(added, in: app), "the saved indexer never reached the list")
  }

  func testAnUnrenderableFieldShowsTheFallbackRatherThanABrokenForm() {
    // A field the renderer can't draw is the main risk of a schema-driven
    // form, and the reason the fallback exists.
    let app = launchIntoDemo()
    openService(prowlarr, in: app)
    XCTAssertTrue(anyRow(prefix: "prowlarr.toggle.", in: app).waitForExistence(timeout: 20))

    element("prowlarr.add", in: app).tap()
    let definition = element("prowlarr.add.definition.ExampleAwkward", in: app)
    XCTAssertTrue(reveal(definition, in: app), "no awkward definition in the demo")
    definition.tap()

    let fallback = element("prowlarr.add.unsupported", in: app)
    XCTAssertTrue(
      reveal(fallback, in: app), "an unrenderable field produced no fallback state")
  }
}
