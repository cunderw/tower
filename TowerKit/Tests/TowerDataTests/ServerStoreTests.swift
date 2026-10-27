import Foundation
import Testing
@testable import TowerData
import TowerCore

@Test func inMemoryStoreRoundTripsAServer() throws {
  let store = InMemoryServerStore()
  let server = Server(name: "Tower", url: URL(string: "http://192.0.2.10")!, apiKey: "abc")
  try store.save(server)
  #expect(try store.load() == server)
}

@Test func loadReturnsNilBeforeAnythingIsSaved() throws {
  #expect(try InMemoryServerStore().load() == nil)
}

@Test func clearRemovesTheServer() throws {
  let store = InMemoryServerStore()
  try store.save(Server(name: "Tower", url: URL(string: "http://192.0.2.10")!, apiKey: "abc"))
  try store.clear()
  #expect(try store.load() == nil)
}

@Test func savingTwiceOverwritesRatherThanDuplicating() throws {
  let store = InMemoryServerStore()
  let url = URL(string: "http://192.0.2.10")!
  try store.save(Server(name: "Tower", url: url, apiKey: "one"))
  let second = Server(name: "Tower", url: url, apiKey: "two")
  try store.save(second)
  // Compare the whole value (not just apiKey) so a bug that overwrites the
  // apiKey field while leaving stale id/name/url behind would still fail
  // this test.
  #expect(try store.load() == second)
}
