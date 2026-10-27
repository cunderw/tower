// @generated
// This file was automatically generated and should not be edited.

import ApolloTestSupport
@testable import TowerAPI

nonisolated public final class InfoCpu: MockObject {
  public static let objectType: ApolloAPI.Object = TowerAPI.Objects.InfoCpu
  public static let _mockFields = MockFields()
  public typealias MockValueCollectionType = Array<Mock<InfoCpu>>

  public struct MockFields: Sendable {
    @Field<String>("brand") public var brand
    @Field<Int>("cores") public var cores
    @Field<Int>("threads") public var threads
  }
}

public extension Mock where O == InfoCpu {
  convenience init(
    brand: String? = nil,
    cores: Int? = nil,
    threads: Int? = nil
  ) {
    self.init()
    _setScalar(brand, for: \.brand)
    _setScalar(cores, for: \.cores)
    _setScalar(threads, for: \.threads)
  }
}
