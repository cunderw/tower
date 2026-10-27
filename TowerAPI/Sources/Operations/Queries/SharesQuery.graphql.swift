// @generated
// This file was automatically generated and should not be edited.

@_exported import ApolloAPI
@_spi(Execution) @_spi(Unsafe) import ApolloAPI

nonisolated public struct SharesQuery: GraphQLQuery {
  public static let operationName: String = "Shares"
  public static let operationDocument: ApolloAPI.OperationDocument = .init(
    definition: .init(
      #"query Shares { shares { __typename id name nameOrig comment include exclude cache allocator splitLevel floor cow used free } }"#
    ))

  public init() {}

  nonisolated public struct Data: TowerAPI.SelectionSet {
    @_spi(Unsafe) public let __data: DataDict
    @_spi(Unsafe) public init(_dataDict: DataDict) { __data = _dataDict }

    @_spi(Execution) public static var __parentType: any ApolloAPI.ParentType { TowerAPI.Objects.Query }
    @_spi(Execution) public static var __selections: [ApolloAPI.Selection] { [
      .field("shares", [Share].self),
    ] }
    @_spi(Execution) public static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
      SharesQuery.Data.self
    ] }

    /// #### Required Permissions:
    ///
    /// - Action: **READ_ANY**
    /// - Resource: **SHARE**
    public var shares: [Share] { __data["shares"] }

    /// Share
    ///
    /// Parent Type: `Share`
    nonisolated public struct Share: TowerAPI.SelectionSet {
      @_spi(Unsafe) public let __data: DataDict
      @_spi(Unsafe) public init(_dataDict: DataDict) { __data = _dataDict }

      @_spi(Execution) public static var __parentType: any ApolloAPI.ParentType { TowerAPI.Objects.Share }
      @_spi(Execution) public static var __selections: [ApolloAPI.Selection] { [
        .field("__typename", String.self),
        .field("id", TowerAPI.PrefixedID.self),
        .field("name", String?.self),
        .field("nameOrig", String?.self),
        .field("comment", String?.self),
        .field("include", [String]?.self),
        .field("exclude", [String]?.self),
        .field("cache", Bool?.self),
        .field("allocator", String?.self),
        .field("splitLevel", String?.self),
        .field("floor", String?.self),
        .field("cow", String?.self),
        .field("used", TowerAPI.BigInt?.self),
        .field("free", TowerAPI.BigInt?.self),
      ] }
      @_spi(Execution) public static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
        SharesQuery.Data.Share.self
      ] }

      public var id: TowerAPI.PrefixedID { __data["id"] }
      /// Display name
      public var name: String? { __data["name"] }
      /// Original name
      public var nameOrig: String? { __data["nameOrig"] }
      /// User comment
      public var comment: String? { __data["comment"] }
      /// Disks that are included in this share
      public var include: [String]? { __data["include"] }
      /// Disks that are excluded from this share
      public var exclude: [String]? { __data["exclude"] }
      /// Is this share cached
      public var cache: Bool? { __data["cache"] }
      /// Allocator
      public var allocator: String? { __data["allocator"] }
      /// Split level
      public var splitLevel: String? { __data["splitLevel"] }
      /// Floor
      public var floor: String? { __data["floor"] }
      /// COW
      public var cow: String? { __data["cow"] }
      /// (KB) Used Size
      public var used: TowerAPI.BigInt? { __data["used"] }
      /// (KB) Free space
      public var free: TowerAPI.BigInt? { __data["free"] }
    }
  }
}
