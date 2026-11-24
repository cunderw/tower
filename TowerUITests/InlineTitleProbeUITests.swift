import UIKit
import XCTest

/// Scratch probe for issue #50. Records the detail column's title state and never fails.
@MainActor
final class InlineTitleProbeUITests: XCTestCase {
  func testProbe() {
    let app = XCUIApplication()
    app.launchArguments = ["--uitest-reset-credentials"]
    var inline = 0, total = 0
    let screens = [("Docker", "code-server"), ("VMs", "Debian Desktop"), ("Shares", "appdata")]
    for launch in 0..<4 {
      app.launch()
      XCTAssertTrue(app.buttons["connect.demo"].waitForExistence(timeout: 15))
      app.buttons["connect.demo"].tap()
      _ = app.descendants(matching: .any).matching(identifier: "services.docker")
        .firstMatch.waitForExistence(timeout: 15)
      for (tab, row) in screens {
        app.buttons[tab].firstMatch.tap()
        guard app.staticTexts[row].waitForExistence(timeout: 15) else { continue }
        app.staticTexts[row].tap()
        Thread.sleep(forTimeInterval: 1.5)
        let s = measure(app)
        total += 1
        if s.hasPrefix("INLINE") { inline += 1 }
        print("[probe] L\(launch) \(tab) \(s)")
        let rows = app.cells.allElementsBoundByIndex.filter { $0.frame.maxX <= 330 && $0.frame.minY > 150 }
          .sorted { $0.frame.minY < $1.frame.minY }
        if rows.count > 1 {
          rows[1].tap(); Thread.sleep(forTimeInterval: 1.5)
          print("[probe] L\(launch) \(tab) reselect-other \(measure(app))")
          app.staticTexts[row].firstMatch.tap(); Thread.sleep(forTimeInterval: 1.5)
          print("[probe] L\(launch) \(tab) reselect-first \(measure(app))")
        }
      }
      app.terminate()
    }
    print("[probe] SUMMARY inline=\(inline) total=\(total)")
  }

  func testPlaceholderBar() {
    let app = XCUIApplication()
    app.launchArguments = ["--uitest-reset-credentials"]
    app.launch()
    XCTAssertTrue(app.buttons["connect.demo"].waitForExistence(timeout: 15))
    app.buttons["connect.demo"].tap()
    app.buttons["Docker"].firstMatch.tap()
    XCTAssertTrue(app.staticTexts["code-server"].waitForExistence(timeout: 15))
    Thread.sleep(forTimeInterval: 1)
    for b in app.navigationBars.allElementsBoundByIndex {
      print("[probe] placeholder bar id=\(b.identifier) frame=\(b.frame)")
    }
    app.staticTexts["code-server"].tap()
    Thread.sleep(forTimeInterval: 1.5)
    for b in app.navigationBars.allElementsBoundByIndex {
      print("[probe] detail bar id=\(b.identifier) frame=\(b.frame)")
    }
  }

  private func measure(_ app: XCUIApplication) -> String {
    let bars = app.navigationBars.allElementsBoundByIndex.filter { $0.frame.width > 900 }
    guard let bar = bars.first else { return "NOBAR" }
    let h = bar.frame.height
    let cells = app.cells.allElementsBoundByIndex.map { $0.frame }
      .filter { $0.minX > 330 }.map { Int($0.minY) }.sorted().prefix(2)
    return "\(h < 80 ? "INLINE" : "LARGE") bar=\(bar.frame) id=\(bar.identifier) detailCellsY=\(Array(cells))"
  }
}
