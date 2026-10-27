import Apollo
import Foundation
import TowerAPI
import TowerCore

/// Reads Unraid's user shares. Apollo's generated types never escape this
/// module — `LiveShareRepository` is the boundary where `SharesQuery.Data`
/// becomes `[Share]`.
///
/// Read-only: `Share` has no mutations in Unraid's schema, so unlike
/// `DockerRepositoryProtocol`/`VMRepositoryProtocol` this protocol is a single
/// method. It carries no action machinery "for symmetry", because a method
/// nothing can call is dead surface.
public protocol ShareRepositoryProtocol: Sendable {
  func shares() async throws -> [Share]
}

public struct LiveShareRepository: ShareRepositoryProtocol {
  private let provider: ApolloClientProvider

  public init(provider: ApolloClientProvider) {
    self.provider = provider
  }

  public func shares() async throws -> [Share] {
    let response = try await provider.client.fetch(
      query: SharesQuery(),
      cachePolicy: .networkOnly
    )
    if let errors = response.errors, !errors.isEmpty {
      throw AppError.from(graphQLErrors: errors)
    }
    guard let data = response.data else {
      throw AppError.decoding("Empty response for Shares.")
    }
    // Sorted by display name so list order is stable across refreshes; the
    // server does not guarantee `shares` order. Case-insensitive so a
    // capitalised share doesn't sort ahead of every lowercase one.
    return data.shares
      .map(Share.init(from:))
      .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
  }
}

extension Share {
  /// Maps Apollo's generated `SharesQuery.Data.Share` into the domain model.
  ///
  /// Deliberately **not** public: its parameter is an Apollo-generated type, and
  /// a public signature mentioning one would let callers build a domain model
  /// straight from hand-rolled GraphQL data, skipping the error and nil-data
  /// guards in `shares()` that are supposed to be the only way in.
  ///
  /// Three normalisations happen here, at the boundary, because they are facts
  /// about the wire rather than about shares:
  ///
  /// 1. **`""` becomes `nil`.** Unraid sends empty strings for absent
  ///    `comment`, `splitLevel`, `allocator`, and `cow`, and an empty string is
  ///    the absence of a value, not a value. The UI omits a `nil` row; it would
  ///    render a blank one for `""`.
  /// 2. **`nameOrig` equal to `name` becomes `nil`**, since a row repeating the
  ///    share's own name is noise. It is only interesting when a share has been
  ///    renamed.
  /// 3. **`floor` is parsed from a string to `Int64?`**, degrading to `nil`
  ///    rather than `0` — `0` is a real floor ("no minimum") and the two must
  ///    stay distinguishable.
  init(from share: SharesQuery.Data.Share) {
    let name = share.name.nonEmpty
    self.init(
      id: share.id,
      name: name,
      originalName: share.nameOrig.nonEmpty.flatMap { $0 == name ? nil : $0 },
      comment: share.comment.nonEmpty,
      // `include`/`exclude` are nullable lists; `nil` and `[]` both mean "no
      // disks named", which for these two fields is the same statement — unlike
      // `vms.domains`, where the distinction is the whole point. Unraid reports
      // `[]` for a share that names no disks.
      includedDisks: share.include ?? [],
      excludedDisks: share.exclude ?? [],
      isCached: share.cache,
      allocator: share.allocator.nonEmpty,
      splitLevel: share.splitLevel.nonEmpty,
      floorKilobytes: share.floor.nonEmpty.flatMap(Int64.init),
      copyOnWrite: share.cow.nonEmpty,
      poolUsedKilobytes: share.used,
      poolFreeKilobytes: share.free
    )
  }
}

extension String? {
  /// `nil` for both a nil string and an empty one — the wire sends `""` where
  /// it means "absent", and every consumer here wants those treated alike.
  /// Local to this file because it encodes an assumption about *this* API's
  /// habits, not a general Swift nicety.
  fileprivate var nonEmpty: String? {
    guard let self, !self.isEmpty else { return nil }
    return self
  }
}
