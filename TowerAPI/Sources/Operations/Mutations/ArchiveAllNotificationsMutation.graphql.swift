// @generated
// This file was automatically generated and should not be edited.

@_exported import ApolloAPI
@_spi(Execution) @_spi(Unsafe) import ApolloAPI

nonisolated public struct ArchiveAllNotificationsMutation: GraphQLMutation {
  public static let operationName: String = "ArchiveAllNotifications"
  public static let operationDocument: ApolloAPI.OperationDocument = .init(
    definition: .init(
      #"mutation ArchiveAllNotifications { archiveAll { __typename unread { __typename info warning alert total } archive { __typename info warning alert total } } }"#
    ))

  public init() {}

  nonisolated public struct Data: TowerAPI.SelectionSet {
    @_spi(Unsafe) public let __data: DataDict
    @_spi(Unsafe) public init(_dataDict: DataDict) { __data = _dataDict }

    @_spi(Execution) public static var __parentType: any ApolloAPI.ParentType { TowerAPI.Objects.Mutation }
    @_spi(Execution) public static var __selections: [ApolloAPI.Selection] { [
      .field("archiveAll", ArchiveAll.self),
    ] }
    @_spi(Execution) public static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
      ArchiveAllNotificationsMutation.Data.self
    ] }

    public var archiveAll: ArchiveAll { __data["archiveAll"] }

    /// ArchiveAll
    ///
    /// Parent Type: `NotificationOverview`
    nonisolated public struct ArchiveAll: TowerAPI.SelectionSet {
      @_spi(Unsafe) public let __data: DataDict
      @_spi(Unsafe) public init(_dataDict: DataDict) { __data = _dataDict }

      @_spi(Execution) public static var __parentType: any ApolloAPI.ParentType { TowerAPI.Objects.NotificationOverview }
      @_spi(Execution) public static var __selections: [ApolloAPI.Selection] { [
        .field("__typename", String.self),
        .field("unread", Unread.self),
        .field("archive", Archive.self),
      ] }
      @_spi(Execution) public static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
        ArchiveAllNotificationsMutation.Data.ArchiveAll.self
      ] }

      public var unread: Unread { __data["unread"] }
      public var archive: Archive { __data["archive"] }

      /// ArchiveAll.Unread
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
          ArchiveAllNotificationsMutation.Data.ArchiveAll.Unread.self
        ] }

        public var info: Int { __data["info"] }
        public var warning: Int { __data["warning"] }
        public var alert: Int { __data["alert"] }
        public var total: Int { __data["total"] }
      }

      /// ArchiveAll.Archive
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
          ArchiveAllNotificationsMutation.Data.ArchiveAll.Archive.self
        ] }

        public var info: Int { __data["info"] }
        public var warning: Int { __data["warning"] }
        public var alert: Int { __data["alert"] }
        public var total: Int { __data["total"] }
      }
    }
  }
}
