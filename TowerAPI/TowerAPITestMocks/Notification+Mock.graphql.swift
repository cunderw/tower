// @generated
// This file was automatically generated and should not be edited.

import ApolloTestSupport
@testable import TowerAPI

nonisolated public final class Notification: MockObject {
  public static let objectType: ApolloAPI.Object = TowerAPI.Objects.Notification
  public static let _mockFields = MockFields()
  public typealias MockValueCollectionType = Array<Mock<Notification>>

  public struct MockFields: Sendable {
    @Field<String>("description") public var description
    @Field<TowerAPI.PrefixedID>("id") public var id
    @Field<GraphQLEnum<TowerAPI.NotificationImportance>>("importance") public var importance
    @Field<String>("link") public var link
    @Field<String>("subject") public var subject
    @Field<String>("timestamp") public var timestamp
    @Field<String>("title") public var title
    @Field<GraphQLEnum<TowerAPI.NotificationType>>("type") public var type
  }
}

public extension Mock where O == Notification {
  convenience init(
    description: String = "",
    id: TowerAPI.PrefixedID = .defaultMockValue,
    importance: GraphQLEnum<TowerAPI.NotificationImportance> = .case(.alert),
    link: String? = nil,
    subject: String = "",
    timestamp: String? = nil,
    title: String = "",
    type: GraphQLEnum<TowerAPI.NotificationType> = .case(.unread)
  ) {
    self.init()
    _setScalar(description, for: \.description)
    _setScalar(id, for: \.id)
    _setScalar(importance, for: \.importance)
    _setScalar(link, for: \.link)
    _setScalar(subject, for: \.subject)
    _setScalar(timestamp, for: \.timestamp)
    _setScalar(title, for: \.title)
    _setScalar(type, for: \.type)
  }
}
