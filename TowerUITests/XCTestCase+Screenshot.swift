import UIKit
import XCTest

extension XCTestCase {
  /// Writes the screen to a PNG on the host, so a state a test asserts can also
  /// be looked at.
  ///
  /// A file and not an `XCTAttachment`, for the reason `ScreenshotTourUITests`
  /// gives. The directory is the tour's: `TOWER_SCREENSHOT_DIR` (set it as
  /// `TEST_RUNNER_TOWER_SCREENSHOT_DIR` on the host), else
  /// `/tmp/tower-screenshots`. The name carries the device idiom, so an iPhone
  /// run and an iPad run of one test keep both files.
  @MainActor
  func saveScreenshot(named name: String) throws {
    let directory =
      ProcessInfo.processInfo.environment["TOWER_SCREENSHOT_DIR"] ?? "/tmp/tower-screenshots"
    try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
    let idiom = UIDevice.current.userInterfaceIdiom == .pad ? "ipad" : "iphone"
    let path = (directory as NSString).appendingPathComponent("\(name)-\(idiom).png")
    try XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: path))
    print("[screenshot] \(path)")
  }
}
