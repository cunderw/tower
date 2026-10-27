// @generated
// This file was automatically generated and should not be edited.

@_exported import ApolloAPI
@_spi(Execution) @_spi(Unsafe) import ApolloAPI

nonisolated public struct ArchiveNotificationMutation: GraphQLMutation {
  public static let operationName: String = "ArchiveNotification"
  public static let operationDocument: ApolloAPI.OperationDocument = .init(
    definition: .init(
      #"mutation ArchiveNotification($id: PrefixedID!) { archiveNotification(id: $id) { __typename id type } }"#
    ))

  public var id: PrefixedID

  public init(id: PrefixedID) {
    self.id = id
  }

  @_spi(Unsafe) public var __variables: Variables? { ["id": id] }

  nonisolated public struct Data: TowerAPI.SelectionSet {
    @_spi(Unsafe) public let __data: DataDict
    @_spi(Unsafe) public init(_dataDict: DataDict) { __data = _dataDict }

    @_spi(Execution) public static var __parentType: any ApolloAPI.ParentType { TowerAPI.Objects.Mutation }
    @_spi(Execution) public static var __selections: [ApolloAPI.Selection] { [
      .field("archiveNotification", ArchiveNotification.self, arguments: ["id": .variable("id")]),
    ] }
    @_spi(Execution) public static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
      ArchiveNotificationMutation.Data.self
    ] }

    /// Marks a notification as archived.
    public var archiveNotification: ArchiveNotification { __data["archiveNotification"] }

    /// ArchiveNotification
    ///
    /// Parent Type: `Notification`
    nonisolated public struct ArchiveNotification: TowerAPI.SelectionSet {
      @_spi(Unsafe) public let __data: DataDict
      @_spi(Unsafe) public init(_dataDict: DataDict) { __data = _dataDict }

      @_spi(Execution) public static var __parentType: any ApolloAPI.ParentType { TowerAPI.Objects.Notification }
      @_spi(Execution) public static var __selections: [ApolloAPI.Selection] { [
        .field("__typename", String.self),
        .field("id", TowerAPI.PrefixedID.self),
        .field("type", GraphQLEnum<TowerAPI.NotificationType>.self),
      ] }
      @_spi(Execution) public static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
        ArchiveNotificationMutation.Data.ArchiveNotification.self
      ] }

      public var id: TowerAPI.PrefixedID { __data["id"] }
      public var type: GraphQLEnum<TowerAPI.NotificationType> { __data["type"] }
    }
  }
}
