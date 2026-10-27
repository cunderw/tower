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
