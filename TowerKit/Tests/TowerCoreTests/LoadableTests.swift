import Testing
@testable import TowerCore

@Test func actionFailedKeepsTheData() {
  let state = Loadable<Int>.actionFailed(42, .unauthorized)
  #expect(state.value == 42)
  #expect(state.error == .unauthorized)
}

@Test func failedHasNoValue() {
  let state = Loadable<Int>.failed(.serverUnreachable)
  #expect(state.value == nil)
  #expect(state.error == .serverUnreachable)
}

@Test func loadedHasNoError() {
  let state = Loadable<Int>.loaded(7)
  #expect(state.value == 7)
  #expect(state.error == nil)
}
