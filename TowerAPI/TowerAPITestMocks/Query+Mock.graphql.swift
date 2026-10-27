// @generated
// This file was automatically generated and should not be edited.

import ApolloTestSupport
@testable import TowerAPI

nonisolated public final class Query: MockObject {
  public static let objectType: ApolloAPI.Object = TowerAPI.Objects.Query
  public static let _mockFields = MockFields()
  public typealias MockValueCollectionType = Array<Mock<Query>>

  public struct MockFields: Sendable {
    @Field<UnraidArray>("array") public var array
    @Field<Docker>("docker") public var docker
    @Field<Info>("info") public var info
    @Field<LogFileContent>("logFile") public var logFile
    @Field<[LogFile]>("logFiles") public var logFiles
    @Field<Metrics>("metrics") public var metrics
    @Field<Notifications>("notifications") public var notifications
    @Field<[Share]>("shares") public var shares
    @Field<Vms>("vms") public var vms
  }
}

public extension Mock where O == Query {
  convenience init(
    array: Mock<UnraidArray> = Mock<UnraidArray>(),
    docker: Mock<Docker> = Mock<Docker>(),
    info: Mock<Info> = Mock<Info>(),
    logFile: Mock<LogFileContent> = Mock<LogFileContent>(),
    logFiles: [Mock<LogFile>] = [],
    metrics: Mock<Metrics> = Mock<Metrics>(),
    notifications: Mock<Notifications> = Mock<Notifications>(),
    shares: [Mock<Share>] = [],
    vms: Mock<Vms> = Mock<Vms>()
  ) {
    self.init()
    _setEntity(array, for: \.array)
    _setEntity(docker, for: \.docker)
    _setEntity(info, for: \.info)
    _setEntity(logFile, for: \.logFile)
    _setList(logFiles, for: \.logFiles)
    _setEntity(metrics, for: \.metrics)
    _setEntity(notifications, for: \.notifications)
    _setList(shares, for: \.shares)
    _setEntity(vms, for: \.vms)
  }
}
