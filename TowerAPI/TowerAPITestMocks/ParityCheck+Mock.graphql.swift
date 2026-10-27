// @generated
// This file was automatically generated and should not be edited.

import ApolloTestSupport
@testable import TowerAPI

nonisolated public final class ParityCheck: MockObject {
  public static let objectType: ApolloAPI.Object = TowerAPI.Objects.ParityCheck
  public static let _mockFields = MockFields()
  public typealias MockValueCollectionType = Array<Mock<ParityCheck>>

  public struct MockFields: Sendable {
    @Field<Bool>("correcting") public var correcting
    @Field<TowerAPI.DateTime>("date") public var date
    @Field<Int>("duration") public var duration
    @Field<Int>("errors") public var errors
    @Field<Int>("progress") public var progress
    @Field<String>("speed") public var speed
    @Field<GraphQLEnum<TowerAPI.ParityCheckStatus>>("status") public var status
  }
}

public extension Mock where O == ParityCheck {
  convenience init(
    correcting: Bool? = nil,
    date: TowerAPI.DateTime? = nil,
    duration: Int? = nil,
    errors: Int? = nil,
    progress: Int? = nil,
    speed: String? = nil,
    status: GraphQLEnum<TowerAPI.ParityCheckStatus> = .case(.neverRun)
  ) {
    self.init()
    _setScalar(correcting, for: \.correcting)
    _setScalar(date, for: \.date)
    _setScalar(duration, for: \.duration)
    _setScalar(errors, for: \.errors)
    _setScalar(progress, for: \.progress)
    _setScalar(speed, for: \.speed)
    _setScalar(status, for: \.status)
  }
}
