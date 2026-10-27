import Testing
import TowerCore
@testable import Tower

@Test func appTargetLinksTowerCore() {
  #expect(TowerCore.moduleName == "TowerCore")
}
