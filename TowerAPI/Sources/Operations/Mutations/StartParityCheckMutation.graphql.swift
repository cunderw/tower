// @generated
// This file was automatically generated and should not be edited.

@_exported import ApolloAPI
@_spi(Execution) @_spi(Unsafe) import ApolloAPI

nonisolated public struct StartParityCheckMutation: GraphQLMutation {
  public static let operationName: String = "StartParityCheck"
  public static let operationDocument: ApolloAPI.OperationDocument = .init(
    definition: .init(
      #"mutation StartParityCheck($correct: Boolean!) { parityCheck { __typename start(correct: $correct) } }"#
    ))

  public var correct: Bool

  public init(correct: Bool) {
    self.correct = correct
  }

  @_spi(Unsafe) public var __variables: Variables? { ["correct": correct] }

  nonisolated public struct Data: TowerAPI.SelectionSet {
    @_spi(Unsafe) public let __data: DataDict
    @_spi(Unsafe) public init(_dataDict: DataDict) { __data = _dataDict }

    @_spi(Execution) public static var __parentType: any ApolloAPI.ParentType { TowerAPI.Objects.Mutation }
    @_spi(Execution) public static var __selections: [ApolloAPI.Selection] { [
      .field("parityCheck", ParityCheck.self),
    ] }
    @_spi(Execution) public static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
      StartParityCheckMutation.Data.self
    ] }

    public var parityCheck: ParityCheck { __data["parityCheck"] }

    /// ParityCheck
    ///
    /// Parent Type: `ParityCheckMutations`
    nonisolated public struct ParityCheck: TowerAPI.SelectionSet {
      @_spi(Unsafe) public let __data: DataDict
      @_spi(Unsafe) public init(_dataDict: DataDict) { __data = _dataDict }

      @_spi(Execution) public static var __parentType: any ApolloAPI.ParentType { TowerAPI.Objects.ParityCheckMutations }
      @_spi(Execution) public static var __selections: [ApolloAPI.Selection] { [
        .field("__typename", String.self),
        .field("start", TowerAPI.JSON.self, arguments: ["correct": .variable("correct")]),
      ] }
      @_spi(Execution) public static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
        StartParityCheckMutation.Data.ParityCheck.self
      ] }

      /// #### Required Permissions:
      ///
      /// - Action: **UPDATE_ANY**
      /// - Resource: **ARRAY**
      ///
      /// #### Description:
      ///
      /// Start a parity check
      public var start: TowerAPI.JSON { __data["start"] }
    }
  }
}
