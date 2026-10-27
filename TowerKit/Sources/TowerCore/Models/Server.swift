import Foundation

public struct Server: Identifiable, Equatable, Sendable, Codable {
  public let id: UUID
  public var name: String
  public var url: URL
  public var apiKey: String

  public init(id: UUID = UUID(), name: String, url: URL, apiKey: String) {
    self.id = id
    self.name = name
    self.url = url
    self.apiKey = apiKey
  }

  /// The GraphQL endpoint, tolerating a trailing slash on the stored URL.
  public var graphQLEndpoint: URL {
    url.appending(path: "graphql")
  }
}
