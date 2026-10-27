// @generated
// This file was automatically generated and should not be edited.

@_exported import ApolloAPI
@_spi(Execution) @_spi(Unsafe) import ApolloAPI

nonisolated public struct NotificationListQuery: GraphQLQuery {
  public static let operationName: String = "NotificationList"
  public static let operationDocument: ApolloAPI.OperationDocument = .init(
    definition: .init(
      #"query NotificationList($filter: NotificationFilter!) { notifications { __typename id list(filter: $filter) { __typename id title subject description importance link type timestamp } } }"#
    ))

  public var filter: NotificationFilter

  public init(filter: NotificationFilter) {
    self.filter = filter
  }

  @_spi(Unsafe) public var __variables: Variables? { ["filter": filter] }

  nonisolated public struct Data: TowerAPI.SelectionSet {
    @_spi(Unsafe) public let __data: DataDict
    @_spi(Unsafe) public init(_dataDict: DataDict) { __data = _dataDict }

    @_spi(Execution) public static var __parentType: any ApolloAPI.ParentType { TowerAPI.Objects.Query }
    @_spi(Execution) public static var __selections: [ApolloAPI.Selection] { [
      .field("notifications", Notifications.self),
    ] }
    @_spi(Execution) public static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
      NotificationListQuery.Data.self
    ] }

    /// #### Required Permissions:
    ///
    /// - Action: **READ_ANY**
    /// - Resource: **NOTIFICATIONS**
    ///
    /// #### Description:
    ///
    /// Get all notifications
    public var notifications: Notifications { __data["notifications"] }

    /// Notifications
    ///
    /// Parent Type: `Notifications`
    nonisolated public struct Notifications: TowerAPI.SelectionSet {
      @_spi(Unsafe) public let __data: DataDict
      @_spi(Unsafe) public init(_dataDict: DataDict) { __data = _dataDict }

      @_spi(Execution) public static var __parentType: any ApolloAPI.ParentType { TowerAPI.Objects.Notifications }
      @_spi(Execution) public static var __selections: [ApolloAPI.Selection] { [
        .field("__typename", String.self),
        .field("id", TowerAPI.PrefixedID.self),
        .field("list", [List].self, arguments: ["filter": .variable("filter")]),
      ] }
      @_spi(Execution) public static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
        NotificationListQuery.Data.Notifications.self
      ] }

      public var id: TowerAPI.PrefixedID { __data["id"] }
      public var list: [List] { __data["list"] }

      /// Notifications.List
      ///
      /// Parent Type: `Notification`
      nonisolated public struct List: TowerAPI.SelectionSet {
        @_spi(Unsafe) public let __data: DataDict
        @_spi(Unsafe) public init(_dataDict: DataDict) { __data = _dataDict }

        @_spi(Execution) public static var __parentType: any ApolloAPI.ParentType { TowerAPI.Objects.Notification }
        @_spi(Execution) public static var __selections: [ApolloAPI.Selection] { [
          .field("__typename", String.self),
          .field("id", TowerAPI.PrefixedID.self),
          .field("title", String.self),
          .field("subject", String.self),
          .field("description", String.self),
          .field("importance", GraphQLEnum<TowerAPI.NotificationImportance>.self),
          .field("link", String?.self),
          .field("type", GraphQLEnum<TowerAPI.NotificationType>.self),
          .field("timestamp", String?.self),
        ] }
        @_spi(Execution) public static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
          NotificationListQuery.Data.Notifications.List.self
        ] }

        public var id: TowerAPI.PrefixedID { __data["id"] }
        /// Also known as 'event'
        public var title: String { __data["title"] }
        public var subject: String { __data["subject"] }
        public var description: String { __data["description"] }
        public var importance: GraphQLEnum<TowerAPI.NotificationImportance> { __data["importance"] }
        public var link: String? { __data["link"] }
        public var type: GraphQLEnum<TowerAPI.NotificationType> { __data["type"] }
        /// ISO Timestamp for when the notification occurred
        public var timestamp: String? { __data["timestamp"] }
      }
    }
  }
}
