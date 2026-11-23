// @generated
// This file was automatically generated and can be edited to
// implement advanced custom scalar functionality.
//
// Any changes to this file will not be overwritten by future
// code generation execution.

@_spi(Internal) @_spi(Execution) import ApolloAPI

/// The `JSON` scalar type represents JSON values as specified by [ECMA-404](http://www.ecma-international.org/publications/files/ECMA-ST/ECMA-404.pdf).
///
/// **Mapped, because the default throws.** Apollo generates `typealias JSON = String`,
/// and `String.init(_jsonValue:)` accepts only a string or a number. The four
/// `ParityCheckMutations` actions return `JSON!`, and the schema calls that payload "WIP,
/// response types and functionality will change". An object or array payload therefore
/// failed the whole mutation, and a parity check the server had started read as a failure
/// (issue #22). A custom scalar's initializer is the whole response's decode step, so this
/// one accepts any JSON value and never throws.
///
/// Tower reads nothing from the value. It keeps the raw value only so that
/// `_jsonValue` round-trips, as `JSONEncodable` requires.
public struct JSON: CustomScalarType, Hashable {
  /// The payload exactly as Apollo decoded it.
  public let value: ApolloAPI.JSONValue

  @_spi(Internal)
  public init(_jsonValue value: ApolloAPI.JSONValue) throws {
    self.value = value
  }

  @_spi(Internal)
  public var _jsonValue: ApolloAPI.JSONValue { value }

  public static func == (lhs: JSON, rhs: JSON) -> Bool {
    AnyHashable(lhs.value) == AnyHashable(rhs.value)
  }

  public func hash(into hasher: inout Hasher) {
    hasher.combine(AnyHashable(value))
  }
}
