// @generated
// This file was automatically generated and should not be edited.

import ApolloTestSupport
@testable import TowerAPI

nonisolated public final class Mutation: MockObject {
  public static let objectType: ApolloAPI.Object = TowerAPI.Objects.Mutation
  public static let _mockFields = MockFields()
  public typealias MockValueCollectionType = Array<Mock<Mutation>>

  public struct MockFields: Sendable {
    @Field<NotificationOverview>("archiveAll") public var archiveAll
    @Field<Notification>("archiveNotification") public var archiveNotification
    @Field<ArrayMutations>("array") public var array
    @Field<NotificationOverview>("deleteNotification") public var deleteNotification
    @Field<DockerMutations>("docker") public var docker
    @Field<ParityCheckMutations>("parityCheck") public var parityCheck
    @Field<Notification>("unreadNotification") public var unreadNotification
    @Field<VmMutations>("vm") public var vm
  }
}

public extension Mock where O == Mutation {
  convenience init(
    archiveAll: Mock<NotificationOverview> = Mock<NotificationOverview>(),
    archiveNotification: Mock<Notification> = Mock<Notification>(),
    array: Mock<ArrayMutations> = Mock<ArrayMutations>(),
    deleteNotification: Mock<NotificationOverview> = Mock<NotificationOverview>(),
    docker: Mock<DockerMutations> = Mock<DockerMutations>(),
    parityCheck: Mock<ParityCheckMutations> = Mock<ParityCheckMutations>(),
    unreadNotification: Mock<Notification> = Mock<Notification>(),
    vm: Mock<VmMutations> = Mock<VmMutations>()
  ) {
    self.init()
    _setEntity(archiveAll, for: \.archiveAll)
    _setEntity(archiveNotification, for: \.archiveNotification)
    _setEntity(array, for: \.array)
    _setEntity(deleteNotification, for: \.deleteNotification)
    _setEntity(docker, for: \.docker)
    _setEntity(parityCheck, for: \.parityCheck)
    _setEntity(unreadNotification, for: \.unreadNotification)
    _setEntity(vm, for: \.vm)
  }
}
