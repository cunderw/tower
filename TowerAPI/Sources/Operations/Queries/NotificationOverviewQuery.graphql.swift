// @generated
// This file was automatically generated and should not be edited.

@_exported import ApolloAPI
@_spi(Execution) @_spi(Unsafe) import ApolloAPI

nonisolated public struct NotificationOverviewQuery: GraphQLQuery {
  public static let operationName: String = "NotificationOverview"
  public static let operationDocument: ApolloAPI.OperationDocument = .init(
    definition: .init(
      #"query NotificationOverview { notifications { __typename id overview { __typename unread { __typename info warning alert total } archive { __typename info warning alert total } } } }"#
    ))

  public init() {}

  nonisolated public struct Data: TowerAPI.SelectionSet {
    @_spi(Unsafe) public let __data: DataDict
    @_spi(Unsafe) public init(_dataDict: DataDict) { __data = _dataDict }

    @_spi(Execution) public static var __parentType: any ApolloAPI.ParentType { TowerAPI.Objects.Query }
    @_spi(Execution) public static var __selections: [ApolloAPI.Selection] { [
      .field("notifications", Notifications.self),
    ] }
    @_spi(Execution) public static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
      NotificationOverviewQuery.Data.self
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
        .field("overview", Overview.self),
      ] }
      @_spi(Execution) public static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
        NotificationOverviewQuery.Data.Notifications.self
      ] }

      public var id: TowerAPI.PrefixedID { __data["id"] }
      /// A cached overview of the notifications in the system & their severity.
      public var overview: Overview { __data["overview"] }

      /// Notifications.Overview
      ///
      /// Parent Type: `NotificationOverview`
      nonisolated public struct Overview: TowerAPI.SelectionSet {
        @_spi(Unsafe) public let __data: DataDict
        @_spi(Unsafe) public init(_dataDict: DataDict) { __data = _dataDict }

        @_spi(Execution) public static var __parentType: any ApolloAPI.ParentType { TowerAPI.Objects.NotificationOverview }
        @_spi(Execution) public static var __selections: [ApolloAPI.Selection] { [
          .field("__typename", String.self),
          .field("unread", Unread.self),
          .field("archive", Archive.self),
        ] }
        @_spi(Execution) public static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
          NotificationOverviewQuery.Data.Notifications.Overview.self
        ] }

        public var unread: Unread { __data["unread"] }
        public var archive: Archive { __data["archive"] }

        /// Notifications.Overview.Unread
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
            NotificationOverviewQuery.Data.Notifications.Overview.Unread.self
          ] }

          public var info: Int { __data["info"] }
          public var warning: Int { __data["warning"] }
          public var alert: Int { __data["alert"] }
          public var total: Int { __data["total"] }
        }

        /// Notifications.Overview.Archive
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
            NotificationOverviewQuery.Data.Notifications.Overview.Archive.self
          ] }

          public var info: Int { __data["info"] }
          public var warning: Int { __data["warning"] }
          public var alert: Int { __data["alert"] }
          public var total: Int { __data["total"] }
        }
      }
    }
  }
}
