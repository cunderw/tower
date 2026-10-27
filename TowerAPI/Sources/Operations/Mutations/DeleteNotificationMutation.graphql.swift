// @generated
// This file was automatically generated and should not be edited.

@_exported import ApolloAPI
@_spi(Execution) @_spi(Unsafe) import ApolloAPI

nonisolated public struct DeleteNotificationMutation: GraphQLMutation {
  public static let operationName: String = "DeleteNotification"
  public static let operationDocument: ApolloAPI.OperationDocument = .init(
    definition: .init(
      #"mutation DeleteNotification($id: PrefixedID!, $type: NotificationType!) { deleteNotification(id: $id, type: $type) { __typename unread { __typename info warning alert total } archive { __typename info warning alert total } } }"#
    ))

  public var id: PrefixedID
  public var type: GraphQLEnum<NotificationType>

  public init(
    id: PrefixedID,
    type: GraphQLEnum<NotificationType>
  ) {
    self.id = id
    self.type = type
  }

  @_spi(Unsafe) public var __variables: Variables? { [
    "id": id,
    "type": type
  ] }

  nonisolated public struct Data: TowerAPI.SelectionSet {
    @_spi(Unsafe) public let __data: DataDict
    @_spi(Unsafe) public init(_dataDict: DataDict) { __data = _dataDict }

    @_spi(Execution) public static var __parentType: any ApolloAPI.ParentType { TowerAPI.Objects.Mutation }
    @_spi(Execution) public static var __selections: [ApolloAPI.Selection] { [
      .field("deleteNotification", DeleteNotification.self, arguments: [
        "id": .variable("id"),
        "type": .variable("type")
      ]),
    ] }
    @_spi(Execution) public static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
      DeleteNotificationMutation.Data.self
    ] }

    public var deleteNotification: DeleteNotification { __data["deleteNotification"] }

    /// DeleteNotification
    ///
    /// Parent Type: `NotificationOverview`
    nonisolated public struct DeleteNotification: TowerAPI.SelectionSet {
      @_spi(Unsafe) public let __data: DataDict
      @_spi(Unsafe) public init(_dataDict: DataDict) { __data = _dataDict }

      @_spi(Execution) public static var __parentType: any ApolloAPI.ParentType { TowerAPI.Objects.NotificationOverview }
      @_spi(Execution) public static var __selections: [ApolloAPI.Selection] { [
        .field("__typename", String.self),
        .field("unread", Unread.self),
        .field("archive", Archive.self),
      ] }
      @_spi(Execution) public static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
        DeleteNotificationMutation.Data.DeleteNotification.self
      ] }

      public var unread: Unread { __data["unread"] }
      public var archive: Archive { __data["archive"] }

      /// DeleteNotification.Unread
      ///
      /// Parent Type: `NotificationCounts`
      nonisolated public struct Unread: TowerAPI.SelectionSet {
        @_spi(Unsafe) public let __data: DataDict
        @_spi(Unsafe) public init(_dataDict: DataDict) { __data = _dataDict }

        @_spi(Execution) public static var __parentType: any ApolloAPI.ParentType { TowerAPI.Objects.NotificationCounts }
        @_spi(Execution) public static var __selections: [ApolloAPI.Selection] { [
          .field("__typename", String.self),
          .field("info", Int.self),
          .field("warning", Int.self),
          .field("alert", Int.self),
          .field("total", Int.self),
        ] }
        @_spi(Execution) public static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
          DeleteNotificationMutation.Data.DeleteNotification.Unread.self
        ] }

        public var info: Int { __data["info"] }
        public var warning: Int { __data["warning"] }
        public var alert: Int { __data["alert"] }
        public var total: Int { __data["total"] }
      }

      /// DeleteNotification.Archive
      ///
      /// Parent Type: `NotificationCounts`
      nonisolated public struct Archive: TowerAPI.SelectionSet {
        @_spi(Unsafe) public let __data: DataDict
        @_spi(Unsafe) public init(_dataDict: DataDict) { __data = _dataDict }

        @_spi(Execution) public static var __parentType: any ApolloAPI.ParentType { TowerAPI.Objects.NotificationCounts }
        @_spi(Execution) public static var __selections: [ApolloAPI.Selection] { [
          .field("__typename", String.self),
          .field("info", Int.self),
          .field("warning", Int.self),
          .field("alert", Int.self),
          .field("total", Int.self),
        ] }
        @_spi(Execution) public static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
          DeleteNotificationMutation.Data.DeleteNotification.Archive.self
        ] }

        public var info: Int { __data["info"] }
        public var warning: Int { __data["warning"] }
        public var alert: Int { __data["alert"] }
        public var total: Int { __data["total"] }
      }
    }
  }
}
