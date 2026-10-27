// @generated
// This file was automatically generated and can be edited to
// implement advanced custom scalar functionality.
//
// Any changes to this file will not be overwritten by future
// code generation execution.

@_spi(Internal) @_spi(Execution) import ApolloAPI
import Foundation

/// The `BigInt` scalar type represents non-fractional signed whole numeric values.
///
/// Unraid transmits `BigInt` values on the wire as JSON **numbers**, not strings, and real
/// values (e.g. share/disk byte counts) exceed `Int32.max` by roughly 40x
/// (observed up to ~87,095,480,189). The Apollo-generated default of `typealias BigInt = String`
/// would throw a `JSONDecodingError` decoding these fields, so this is mapped to `Int64` instead,
/// with `CustomScalarType` conformance added below since `Int64` has no such conformance in
/// `ApolloAPI` out of the box (only `Int`, `Int32`, `Float`, `Double`, `Bool`, and `String` do).
public typealias BigInt = Int64

/// `@retroactive` conformance of `Int64` to `CustomScalarType`.
///
/// This exists solely because `ApolloAPI` 2.3.0 ships `CustomScalarType`-enabling
/// conformances (`JSONDecodable`/`JSONEncodable`/`OutputTypeConvertible`) for `String`,
/// `Int`, `Int32`, `Float`, `Double`, and `Bool` — but not `Int64`. If a future Apollo
/// release adds a native `Int64` conformance, this extension becomes a **duplicate
/// conformance** and the build breaks.
///
/// `TowerAPI/Package.swift` pins apollo-ios at `exact: "2.3.0"`, and `TowerKit/Package.swift`
/// requires `.upToNextMinor(from: "2.3.0")`, so a minor release that adds that conformance
/// cannot arrive on an incidental `swift package update`. Taking Apollo 2.4+ is a deliberate
/// edit. Whoever makes it: delete this extension (keep the `typealias BigInt = Int64` above)
/// and re-run the `TowerKit` tests — Apollo's native conformance should satisfy
/// `sharesCarriesTheRealBigIntPoolFiguresOffTheWire` in `ShareRepositoryStubTests.swift`
/// as-is.
///
/// A wrapper struct instead of the conformance would touch 50 generated field
/// declarations that use `BigInt`, and every mock fixture would need `BigInt(1)` instead
/// of `1`.
extension Int64: @retroactive CustomScalarType {
  @_spi(Internal)
  @inlinable public init(_jsonValue value: ApolloAPI.JSONValue) throws {
    guard let number = value as? NSNumber else {
      throw JSONDecodingError.couldNotConvert(value: value, to: Int64.self)
    }
    self = number.int64Value
  }

  @_spi(Internal)
  @inlinable public var _jsonValue: ApolloAPI.JSONValue {
    return self
  }
}
