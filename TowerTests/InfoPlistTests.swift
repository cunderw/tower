import Foundation
import Testing

/// What the shipped bundle declares, read from the **built app** rather than from
/// `Tower/Info.plist`.
///
/// `GENERATE_INFOPLIST_FILE = YES` merges every `INFOPLIST_KEY_*` build setting
/// into the plist Apple actually receives, so the source file shows only half of
/// what ships. A `plutil -p` of the source file reports the local network
/// purpose string missing when it is set as a build setting. These tests run in
/// the app-hosted test target, so `Bundle.main` is `Tower.app` and there is no
/// source file to read by accident.

@Test func theBundleDeclaresALocalNetworkPurposeString() throws {
  // The regression guard: this is set in two build configurations that must move
  // together, and nothing else would notice if one were dropped.
  let value = Bundle.main.object(forInfoDictionaryKey: "NSLocalNetworkUsageDescription")
  let string = try #require(
    value as? String,
    """
    no NSLocalNetworkUsageDescription in the built bundle — iOS will ask for local \
    network access with no reason attached
    """)
  #expect(!string.isEmpty)
}

@Test func theLocalNetworkPurposeStringSaysWhatTheAccessIsFor() throws {
  // Guideline 5.1.1: a purpose string "must clearly and completely describe why
  // the app needs access … and in most cases provide an example of how the data
  // will be used". Naming the destination is not naming the reason, so require
  // the string to mention something the access actually enables.
  let string = try #require(
    Bundle.main.object(forInfoDictionaryKey: "NSLocalNetworkUsageDescription") as? String)
  let lowercased = string.lowercased()

  #expect(lowercased.contains("unraid"), "the string never names what it connects to")

  let capabilities = ["status", "health", "container", "machine", "download", "manage", "monitor"]
  #expect(
    capabilities.contains { lowercased.contains($0) },
    """
    the string says what Tower connects to but not what the access lets the user do, \
    which is the half Guideline 5.1.1 asks for: \(string)
    """)
}
