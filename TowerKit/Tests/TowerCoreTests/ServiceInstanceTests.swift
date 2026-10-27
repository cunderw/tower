import Foundation
import Testing
@testable import TowerCore

@Test func everyServiceKindHasADisplayNameAndCategory() {
  // Guards the switch statements: a kind added later without a
  // display name or category would fail to compile, but one added with an empty
  // string would not.
  for kind in ServiceKind.allCases {
    #expect(!kind.displayName.isEmpty)
    #expect(ServiceCategory.allCases.contains(kind.category))
  }
}

@Test func serviceKindsCoverTheEightServices() {
  #expect(ServiceKind.allCases.count == 8)
  #expect(Set(ServiceKind.allCases.map(\.rawValue)) == [
    "bazarr", "lidarr", "overseerr", "prowlarr", "radarr",
    "sonarr", "nzbget", "tautulli",
  ])
}

@Test func apiKeyCredentialsEncodeToATaggedShape() throws {
  // The encoded shape is the on-disk (keychain) format, so it is pinned by a
  // literal rather than only round-tripped: a synthesized-Codable change that
  // silently altered the keys would strand every stored record.
  let data = try JSONEncoder().encode(ServiceCredentials.apiKey("abc"))
  let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: String])
  #expect(json == ["type": "apiKey", "key": "abc"])
}

@Test func usernamePasswordCredentialsEncodeToATaggedShape() throws {
  let data = try JSONEncoder().encode(
    ServiceCredentials.usernamePassword(username: "admin", password: "s3cret"))
  let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: String])
  #expect(json == ["type": "usernamePassword", "username": "admin", "password": "s3cret"])
}

@Test func credentialsRoundTrip() throws {
  for credentials: ServiceCredentials in [
    .apiKey("abc"),
    .usernamePassword(username: "admin", password: "s3cret"),
  ] {
    let data = try JSONEncoder().encode(credentials)
    #expect(try JSONDecoder().decode(ServiceCredentials.self, from: data) == credentials)
  }
}

@Test func decodingAnUnknownCredentialTypeThrows() {
  let data = Data(#"{"type":"oauth","token":"x"}"#.utf8)
  #expect(throws: DecodingError.self) {
    try JSONDecoder().decode(ServiceCredentials.self, from: data)
  }
}

@Test func instanceRoundTrips() throws {
  let instance = ServiceInstance(
    kind: .radarr,
    name: "Radarr 4K",
    baseURL: URL(string: "http://192.0.2.10:7878")!,
    credentials: .apiKey("abc"),
    customHeaders: ["CF-Access-Client-Id": "id"],
    isEnabled: false,
    sortOrder: 3
  )
  let data = try JSONEncoder().encode(instance)
  #expect(try JSONDecoder().decode(ServiceInstance.self, from: data) == instance)
}

@Test func decodingToleratesAMissingHeadersAndEnabledFlag() throws {
  // Both fields were introduced with defaults; a record written by an older
  // build (or hand-edited) must still load rather than stranding the user's
  // whole service list on one absent key.
  let json = """
    {"id":"7E0C9B8A-0000-0000-0000-000000000001","kind":"sonarr","name":"Sonarr",
     "baseURL":"http:\\/\\/192.0.2.10:8989","credentials":{"type":"apiKey","key":"k"},
     "sortOrder":0}
    """
  let instance = try JSONDecoder().decode(ServiceInstance.self, from: Data(json.utf8))
  #expect(instance.customHeaders.isEmpty)
  #expect(instance.isEnabled)
}

@Test func twoInstancesOfTheSameKindAreDistinct() {
  let url = URL(string: "http://192.0.2.10:7878")!
  let hd = ServiceInstance(kind: .radarr, name: "Radarr", baseURL: url, credentials: .apiKey("a"))
  let uhd = ServiceInstance(kind: .radarr, name: "Radarr 4K", baseURL: url, credentials: .apiKey("b"))
  #expect(hd.id != uhd.id)
  #expect(hd != uhd)
}
