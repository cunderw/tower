import Foundation

/// Matching an *arr queue item to the download client that is actually fetching
/// it — the cross-service payoff of having both families in one app.
///
/// **Where the ambiguity lives.** An *arr names its download client with a
/// label the *user* chose inside that *arr ("NZBGet", "nzb-4k",
/// "Main downloader"), and Tower knows a separate list of instances with names
/// the user chose *here*. There is no shared identifier between the two, so
/// matching is a heuristic and this type exists to make it one explicit,
/// testable rule rather than a condition buried in a view.
///
/// The rule, in order:
/// 1. The item must carry a `downloadID`. Without one there is nothing to point
///    at, even if the client is obvious.
/// 2. The protocol picks the kind: usenet → NZBGet. No other protocol links.
/// 3. Among configured instances of that kind, a **name match wins** — that is
///    the user having named them the same thing in both places, which is the
///    common case and the only positive evidence available.
/// 4. Failing that, a **single** configured instance of the kind is taken as
///    the answer, because there is nothing else it could be.
/// 5. More than one candidate and no name match is **no link**. A link to the
///    wrong client's download is worse than no link: it would show the user
///    someone else's download and invite them to delete it.
public struct DownloadClientLink: Sendable, Hashable, Identifiable {
  public let instance: ServiceInstance
  /// The client's own id, normalised to lower case so a comparison with the
  /// client's own value does not depend on how either side cased it.
  public let downloadID: String

  public var id: String { "\(instance.id)-\(downloadID)" }

  public init(instance: ServiceInstance, downloadID: String) {
    self.instance = instance
    self.downloadID = downloadID
  }

  /// The matched client for a queue item, or `nil` when no link should be
  /// offered.
  ///
  /// - Parameter instances: every service Tower has configured. Filtering to
  ///   the download clients happens here rather than at the call site, so the
  ///   rule stays in one place.
  public static func match(
    downloadProtocol: ArrDownloadProtocol,
    downloadClient: String?,
    downloadID: String?,
    in instances: [ServiceInstance]
  ) -> DownloadClientLink? {
    guard let downloadID = downloadID?.trimmingCharacters(in: .whitespacesAndNewlines),
      !downloadID.isEmpty
    else { return nil }

    guard let kind = clientKind(for: downloadProtocol) else { return nil }
    let candidates = instances.filter { $0.kind == kind }
    guard !candidates.isEmpty else { return nil }

    let matched: ServiceInstance?
    if let name = downloadClient?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty,
      let byName = candidates.first(where: { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame })
    {
      matched = byName
    } else if candidates.count == 1 {
      matched = candidates[0]
    } else {
      // Ambiguous. Pointing at the wrong client would show someone else's
      // download and invite them to delete it.
      matched = nil
    }

    guard let instance = matched else { return nil }
    return DownloadClientLink(instance: instance, downloadID: downloadID.lowercased())
  }

  /// Which client kind handles a protocol. Only usenet has one in Tower, and
  /// an unknown protocol deliberately matches nothing rather than guessing.
  private static func clientKind(for downloadProtocol: ArrDownloadProtocol) -> ServiceKind? {
    downloadProtocol.isUsenet ? .nzbget : nil
  }
}
