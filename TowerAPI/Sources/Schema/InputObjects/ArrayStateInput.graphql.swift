// @generated
// This file was automatically generated and should not be edited.

@_spi(Internal) @_spi(Unsafe) import ApolloAPI

nonisolated public struct ArrayStateInput: InputObject {
  @_spi(Unsafe) public private(set) var __data: InputDict

  @_spi(Unsafe) public init(_ data: InputDict) {
    __data = data
  }

  public init(
    desiredState: GraphQLEnum<ArrayStateInputState>,
    decryptionPassword: GraphQLNullable<String> = nil,
    decryptionKeyfile: GraphQLNullable<String> = nil
  ) {
    __data = InputDict([
      "desiredState": desiredState,
      "decryptionPassword": decryptionPassword,
      "decryptionKeyfile": decryptionKeyfile
    ])
  }

  /// Array state
  public var desiredState: GraphQLEnum<ArrayStateInputState> {
    get { __data["desiredState"] }
    set { __data["desiredState"] = newValue }
  }

  /// Optional password used to unlock encrypted array disks when starting the array
  public var decryptionPassword: GraphQLNullable<String> {
    get { __data["decryptionPassword"] }
    set { __data["decryptionPassword"] = newValue }
  }

  /// Optional keyfile contents used to unlock encrypted array disks when starting
  /// the array. Accepts a data URL or raw base64 payload.
  public var decryptionKeyfile: GraphQLNullable<String> {
    get { __data["decryptionKeyfile"] }
    set { __data["decryptionKeyfile"] = newValue }
  }
}
