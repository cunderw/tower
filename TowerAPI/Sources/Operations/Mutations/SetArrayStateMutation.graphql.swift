// @generated
// This file was automatically generated and should not be edited.

@_exported import ApolloAPI
@_spi(Execution) @_spi(Unsafe) import ApolloAPI

nonisolated public struct SetArrayStateMutation: GraphQLMutation {
  public static let operationName: String = "SetArrayState"
  public static let operationDocument: ApolloAPI.OperationDocument = .init(
    definition: .init(
      #"mutation SetArrayState($input: ArrayStateInput!) { array { __typename setState(input: $input) { __typename id state } } }"#
    ))

  public var input: ArrayStateInput

  public init(input: ArrayStateInput) {
    self.input = input
  }

  @_spi(Unsafe) public var __variables: Variables? { ["input": input] }

  nonisolated public struct Data: TowerAPI.SelectionSet {
    @_spi(Unsafe) public let __data: DataDict
    @_spi(Unsafe) public init(_dataDict: DataDict) { __data = _dataDict }

    @_spi(Execution) public static var __parentType: any ApolloAPI.ParentType { TowerAPI.Objects.Mutation }
    @_spi(Execution) public static var __selections: [ApolloAPI.Selection] { [
      .field("array", Array.self),
    ] }
    @_spi(Execution) public static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
      SetArrayStateMutation.Data.self
    ] }

    public var array: Array { __data["array"] }

    /// Array
    ///
    /// Parent Type: `ArrayMutations`
    nonisolated public struct Array: TowerAPI.SelectionSet {
      @_spi(Unsafe) public let __data: DataDict
      @_spi(Unsafe) public init(_dataDict: DataDict) { __data = _dataDict }

      @_spi(Execution) public static var __parentType: any ApolloAPI.ParentType { TowerAPI.Objects.ArrayMutations }
      @_spi(Execution) public static var __selections: [ApolloAPI.Selection] { [
        .field("__typename", String.self),
        .field("setState", SetState.self, arguments: ["input": .variable("input")]),
      ] }
      @_spi(Execution) public static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
        SetArrayStateMutation.Data.Array.self
      ] }

      /// #### Required Permissions:
      ///
      /// - Action: **UPDATE_ANY**
      /// - Resource: **ARRAY**
      ///
      /// #### Description:
      ///
      /// Set array state
      public var setState: SetState { __data["setState"] }

      /// Array.SetState
      ///
      /// Parent Type: `UnraidArray`
      nonisolated public struct SetState: TowerAPI.SelectionSet {
        @_spi(Unsafe) public let __data: DataDict
        @_spi(Unsafe) public init(_dataDict: DataDict) { __data = _dataDict }

        @_spi(Execution) public static var __parentType: any ApolloAPI.ParentType { TowerAPI.Objects.UnraidArray }
        @_spi(Execution) public static var __selections: [ApolloAPI.Selection] { [
          .field("__typename", String.self),
          .field("id", TowerAPI.PrefixedID.self),
          .field("state", GraphQLEnum<TowerAPI.ArrayState>.self),
        ] }
        @_spi(Execution) public static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
          SetArrayStateMutation.Data.Array.SetState.self
        ] }

        public var id: TowerAPI.PrefixedID { __data["id"] }
        /// Current array state
        public var state: GraphQLEnum<TowerAPI.ArrayState> { __data["state"] }
      }
    }
  }
}
