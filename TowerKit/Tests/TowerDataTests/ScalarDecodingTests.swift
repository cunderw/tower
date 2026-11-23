@_spi(Internal) import Apollo
import Foundation
import Testing
@_spi(Internal) import ApolloAPI
import TowerAPI

@Test func bigIntDecodesAJSONNumberBeyondInt32() throws {
  // Unraid sends BigInt unquoted, and an array-sized figure passes Int32.max.
  let decoded = try BigInt(_jsonValue: NSNumber(value: 72_000_000_000 as Int64))
  #expect(decoded == 72_000_000_000)
  #expect(decoded > Int64(Int32.max))
}

@Test func bigIntRejectsANonNumericJSONValue() {
  #expect(throws: (any Error).self) {
    _ = try BigInt(_jsonValue: "not a number")
  }
}

// `ParityCheckMutations` returns `JSON!` from all four actions (issue #22),
// and the schema calls the payload "WIP". Apollo's default `JSON = String`
// accepts only a string or a number, so an object payload threw and a parity
// action that succeeded on the server read as a failure.

/// One payload as Apollo receives it: `JSONSerialization` output, where an
/// object is an `NSDictionary` and a Bool is an `NSNumber`, converted the way
/// Apollo converts a response body.
private func wireValue(_ json: String) throws -> JSONValue {
  let object: JSONObject = try JSONSerializationFormat.deserialize(data: Data(#"{"v": \#(json)}"#.utf8))
  return try #require(object["v"])
}

@Test func jsonDecodesAnObjectPayload() throws {
  _ = try JSON(_jsonValue: try wireValue(#"{"ok": true, "message": "started"}"#))
}

@Test func jsonDecodesABoolPayload() throws {
  _ = try JSON(_jsonValue: try wireValue("true"))
}

@Test func jsonDecodesAStringPayload() throws {
  _ = try JSON(_jsonValue: try wireValue(#""ok""#))
}

@Test func jsonDecodesAnArrayPayload() throws {
  _ = try JSON(_jsonValue: try wireValue(#"[{"ok": true}]"#))
}
