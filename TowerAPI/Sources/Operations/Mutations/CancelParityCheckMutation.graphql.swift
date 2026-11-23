// @generated
// This file was automatically generated and should not be edited.

@_exported import ApolloAPI
@_spi(Execution) @_spi(Unsafe) import ApolloAPI

nonisolated public struct CancelParityCheckMutation: GraphQLMutation {
  public static let operationName: String = "CancelParityCheck"
  public static let operationDocument: ApolloAPI.OperationDocument = .init(
    definition: .init(
      #"mutation CancelParityCheck { parityCheck { __typename cancel } }"#
    ))

  public init() {}

  nonisolated public struct Data: TowerAPI.SelectionSet {
    @_spi(Unsafe) public let __data: DataDict
    @_spi(Unsafe) public init(_dataDict: DataDict) { __data = _dataDict }

    @_spi(Execution) public static var __parentType: any ApolloAPI.ParentType { TowerAPI.Objects.Mutation }
    @_spi(Execution) public static var __selections: [ApolloAPI.Selection] { [
      .field("parityCheck", ParityCheck.self),
    ] }
    @_spi(Execution) public static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
      CancelParityCheckMutation.Data.self
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
        .field("cancel", TowerAPI.JSON.self),
      ] }
      @_spi(Execution) public static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
        CancelParityCheckMutation.Data.ParityCheck.self
      ] }

      /// #### Required Permissions:
      ///
      /// - Action: **UPDATE_ANY**
      /// - Resource: **ARRAY**
      ///
      /// #### Description:
      ///
      /// Cancel a parity check
      public var cancel: TowerAPI.JSON { __data["cancel"] }
    }
  }
}
