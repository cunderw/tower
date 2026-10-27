import Foundation

/// Turning a service's URL string into a URL something can actually open.
///
/// **`URL(string:)` is not that test.** It succeeds for a bare
/// `wiki.servarr.com/radarr/system`, producing a scheme-less *relative* URL —
/// perfectly valid as a value, and completely inert when handed to SwiftUI's
/// `Link` or `openURL`. The result is a link that renders in link blue, invites
/// a tap, and does nothing at all: no error, no navigation, no way for the user
/// to tell whether they missed it or the app is broken.
///
/// Every DTO here maps optional URL strings the same way, so the failure is not
/// specific to one service. Mapping through this instead means an address the
/// app cannot open becomes `nil` at the boundary, and the UI's existing
/// `if let` renders **no link** rather than a dead one — an absent affordance
/// is honest, a dead one is not.
///
/// Deliberately restricted to `http`/`https` rather than "has any scheme". The
/// values are web addresses published by web services, and accepting arbitrary
/// schemes from a remote server would let a compromised or misconfigured
/// service put a `tel:` or a custom-scheme URL behind a link that reads
/// "Read more".
enum OpenableURL {
  static func from(_ string: String?) -> URL? {
    guard let string, let url = URL(string: string.trimmingCharacters(in: .whitespacesAndNewlines))
    else { return nil }
    guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
      return nil
    }
    // A scheme with no host is still unopenable — `https:` on its own parses.
    guard url.host()?.isEmpty == false else { return nil }
    return url
  }
}
