// @generated
// This file was automatically generated and should not be edited.

import ApolloTestSupport
@testable import TowerAPI

nonisolated public final class VmMutations: MockObject {
  public static let objectType: ApolloAPI.Object = TowerAPI.Objects.VmMutations
  public static let _mockFields = MockFields()
  public typealias MockValueCollectionType = Array<Mock<VmMutations>>

  public struct MockFields: Sendable {
    @Field<Bool>("forceStop") public var forceStop
    @Field<Bool>("pause") public var pause
    @Field<Bool>("reboot") public var reboot
    @Field<Bool>("reset") public var reset
    @Field<Bool>("resume") public var resume
    @Field<Bool>("start") public var start
    @Field<Bool>("stop") public var stop
  }
}

public extension Mock where O == VmMutations {
  convenience init(
    forceStop: Bool = false,
    pause: Bool = false,
    reboot: Bool = false,
    reset: Bool = false,
    resume: Bool = false,
    start: Bool = false,
    stop: Bool = false
  ) {
    self.init()
    _setScalar(forceStop, for: \.forceStop)
    _setScalar(pause, for: \.pause)
    _setScalar(reboot, for: \.reboot)
    _setScalar(reset, for: \.reset)
    _setScalar(resume, for: \.resume)
    _setScalar(start, for: \.start)
    _setScalar(stop, for: \.stop)
  }
}
