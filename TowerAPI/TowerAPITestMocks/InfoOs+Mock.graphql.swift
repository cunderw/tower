// @generated
// This file was automatically generated and should not be edited.

import ApolloTestSupport
@testable import TowerAPI

nonisolated public final class InfoOs: MockObject {
  public static let objectType: ApolloAPI.Object = TowerAPI.Objects.InfoOs
  public static let _mockFields = MockFields()
  public typealias MockValueCollectionType = Array<Mock<InfoOs>>

  public struct MockFields: Sendable {
    @Field<String>("distro") public var distro
    @Field<String>("platform") public var platform
    @Field<String>("release") public var release
    @Field<String>("uptime") public var uptime
  }
}

public extension Mock where O == InfoOs {
  convenience init(
    distro: String? = nil,
    platform: String? = nil,
    release: String? = nil,
    uptime: String? = nil
  ) {
    self.init()
    _setScalar(distro, for: \.distro)
    _setScalar(platform, for: \.platform)
    _setScalar(release, for: \.release)
    _setScalar(uptime, for: \.uptime)
  }
}
