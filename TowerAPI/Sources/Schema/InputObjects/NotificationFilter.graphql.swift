// @generated
// This file was automatically generated and should not be edited.

@_spi(Internal) @_spi(Unsafe) import ApolloAPI

nonisolated public struct NotificationFilter: InputObject {
  @_spi(Unsafe) public private(set) var __data: InputDict

  @_spi(Unsafe) public init(_ data: InputDict) {
    __data = data
  }

  public init(
    importance: GraphQLNullable<GraphQLEnum<NotificationImportance>> = nil,
    type: GraphQLEnum<NotificationType>,
    offset: Int32,
    limit: Int32
  ) {
    __data = InputDict([
      "importance": importance,
      "type": type,
      "offset": offset,
      "limit": limit
    ])
  }

  public var importance: GraphQLNullable<GraphQLEnum<NotificationImportance>> {
    get { __data["importance"] }
    set { __data["importance"] = newValue }
  }

  public var type: GraphQLEnum<NotificationType> {
    get { __data["type"] }
    set { __data["type"] = newValue }
  }

  public var offset: Int32 {
    get { __data["offset"] }
    set { __data["offset"] = newValue }
  }

  public var limit: Int32 {
    get { __data["limit"] }
    set { __data["limit"] = newValue }
  }
}
