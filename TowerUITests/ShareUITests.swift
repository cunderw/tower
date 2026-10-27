import XCTest

/// The Shares tab, driven end to end against `FakeShareRepository`.
///
/// Shares are read-only, so there are no action flows to cover — this file is
/// about what the screens *say*, which for shares is the whole risk: Unraid
/// reports the pool's usage on every share in that pool, not the share's own.
@MainActor
final class ShareUITests: XCTestCase {
  override func setUp() {
    super.setUp()
    continueAfterFailure = false
  }

  private func launchOnShares(state: String? = nil) -> XCUIApplication {
    let app = XCUIApplication()
    app.launchArguments = ["--uitest-seed-dashboard"]
    if let state { app.launchEnvironment["UITEST_SHARES_STATE"] = state }
    app.launch()
    app.buttons["Shares"].firstMatch.tap()
    return app
  }

  private func row(_ id: String, in app: XCUIApplication) -> XCUIElement {
    app.descendants(matching: .any).matching(identifier: "shares.row.\(id)").firstMatch
  }

  // MARK: - List

  func testListRendersEverySeededShare() {
    let app = launchOnShares()

    for id in ["appdata", "bare", "documents", "domains", "renamed"] {
      XCTAssertTrue(
        row("uitest-share-\(id)", in: app).waitForExistence(timeout: 10),
        "shares.row.uitest-share-\(id) never appeared"
      )
    }
  }

  func testARowReadsAsOneMergedLabelIncludingItsComment() {
    // Asserted on the merged label rather than a child count: a combined element
    // still exposes its children to XCUITest queries. The
    // label is what VoiceOver reads, and one swipe has to carry both lines.
    let app = launchOnShares()
    let documents = row("uitest-share-documents", in: app)

    XCTAssertTrue(documents.waitForExistence(timeout: 10))
    XCTAssertEqual(documents.label, "documents, scanned paperwork")
  }

  func testNoRowShowsAnySizeFigure() {
    // Pool figures never appear on a share row, asserted where it would
    // actually break: the pool figures are 421.89 GB / 602.11 GB for the seeded
    // shares, and none of them may appear on a row. A list showing them looks
    // entirely plausible and is wrong about every row.
    let app = launchOnShares()
    XCTAssertTrue(row("uitest-share-appdata", in: app).waitForExistence(timeout: 10))

    for id in ["appdata", "bare", "documents", "domains", "renamed"] {
      let label = row("uitest-share-\(id)", in: app).label
      XCTAssertFalse(label.contains("GB"), "a share row showed a size figure: \(label)")
      XCTAssertFalse(label.contains("TB"), "a share row showed a size figure: \(label)")
    }
  }

  func testSearchMatchesACommentNotOnlyAName() {
    // For several real shares the comment is the only distinguishing text they
    // have, so searching it is the difference between findable and not.
    let app = launchOnShares()
    // Reveals the field first on iPad — see `XCTestCase+Search.swift`.
    let field = searchField(prompt: "Search shares", in: app, timeout: 10)
    XCTAssertTrue(field.waitForExistence(timeout: 10), "the search field never appeared")

    type("scanned paperwork", into: field)

    XCTAssertTrue(row("uitest-share-documents", in: app).waitForExistence(timeout: 10))
    XCTAssertFalse(
      row("uitest-share-appdata", in: app).exists,
      "search didn't filter out shares matching neither name nor comment"
    )
  }

  func testEmptyStateSaysTheServerHasNoShares() {
    let app = launchOnShares(state: "empty")

    XCTAssertTrue(
      app.descendants(matching: .any).matching(identifier: "shares.empty")
        .firstMatch.waitForExistence(timeout: 10),
      "the no-shares state never appeared"
    )
  }

  // MARK: - Detail

  func testPoolSectionSaysWhoseFiguresTheseAreWithoutScrolling() {
    // The assertion that keeps the disclaimer visible. A `Section` footer on
    // an iPhone lands behind the tab bar while the figures sit
    // fully visible above it — `isHittable`, not `exists`, is what distinguishes
    // those two cases.
    let app = launchOnShares()
    XCTAssertTrue(row("uitest-share-domains", in: app).waitForExistence(timeout: 10))
    row("uitest-share-domains", in: app).tap()

    let header = app.descendants(matching: .any)
      .matching(identifier: "shareDetail.poolHeader").firstMatch
    XCTAssertTrue(header.waitForExistence(timeout: 10), "the Pool section had no qualifying header")
    XCTAssertTrue(header.isHittable, "the Pool qualifier isn't visible without scrolling")
    XCTAssertTrue(
      header.label.lowercased().contains("not this share"),
      "the Pool header didn't say the figures aren't the share's: \(header.label)"
    )

    XCTAssertTrue(
      app.descendants(matching: .any).matching(identifier: "shareDetail.poolUsed")
        .firstMatch.exists,
      "the Pool section rendered no figures at all"
    )
  }

  func testAShareWithNothingReportedShowsNoAllocationOrPoolSection() {
    // `bare` reports no allocator, floor, COW, or pool figures. Those sections
    // must disappear rather than render empty headers or a fabricated `0 B`.
    let app = launchOnShares()
    XCTAssertTrue(row("uitest-share-bare", in: app).waitForExistence(timeout: 10))
    row("uitest-share-bare", in: app).tap()

    // The Disks section is always present, so wait on that to know the screen
    // rendered before asserting on absences.
    XCTAssertTrue(
      app.descendants(matching: .any).matching(identifier: "shareDetail.allDisks")
        .firstMatch.waitForExistence(timeout: 10),
      "the share detail screen never rendered"
    )
    XCTAssertFalse(app.staticTexts["Allocation"].exists, "an empty Allocation section rendered")
    XCTAssertFalse(
      app.descendants(matching: .any).matching(identifier: "shareDetail.poolHeader").firstMatch.exists,
      "a Pool section rendered for a share with no pool figures"
    )
    XCTAssertFalse(
      app.descendants(matching: .any).matching(identifier: "shareDetail.poolUsed").firstMatch.exists,
      "pool figures rendered for a share that reported none"
    )
  }

  func testAllDisksIsStatedRatherThanLeftBlank() {
    // Two empty disk lists mean "all disks", which is a real answer — the usual
    // one — and has to be said in words.
    let app = launchOnShares()
    XCTAssertTrue(row("uitest-share-appdata", in: app).waitForExistence(timeout: 10))
    row("uitest-share-appdata", in: app).tap()

    let allDisks = app.descendants(matching: .any)
      .matching(identifier: "shareDetail.allDisks").firstMatch
    XCTAssertTrue(allDisks.waitForExistence(timeout: 10), "a share using every disk said nothing about disks")
  }

  func testNamedDisksReplaceTheAllDisksLine() {
    let app = launchOnShares()
    XCTAssertTrue(row("uitest-share-domains", in: app).waitForExistence(timeout: 10))
    row("uitest-share-domains", in: app).tap()

    XCTAssertTrue(app.staticTexts["Included"].waitForExistence(timeout: 10))
    XCTAssertFalse(
      app.descendants(matching: .any).matching(identifier: "shareDetail.allDisks").firstMatch.exists,
      "a share with named disks also claimed to use all of them"
    )
  }
}
