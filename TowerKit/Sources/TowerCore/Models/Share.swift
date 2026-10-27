import Foundation

/// A user share as Unraid's `Share` reports it.
///
/// **The two byte figures here describe the pool, not the share.** That is why
/// they are named `poolUsedKilobytes`/`poolFreeKilobytes` rather than mapping
/// `used`/`free` straight through: the GraphQL names invite summing them as
/// per-share usage, which is wrong. What Unraid reports:
///
/// | Shares | Reported `used` | What it actually is |
/// |---|---|---|
/// | every share on the cache pool | one figure, identical for each | the cache pool |
/// | every share on the array | a second figure, identical for each | the array |
/// | a share on both | a third figure | spans both |
///
/// **No per-share usage figure exists anywhere in the API.** The whole schema
/// was searched: these are the only byte-valued fields on `Share`,
/// `Query.shares` is the only entry point, and nothing else reports per-share
/// consumption. So the Shares list shows no per-share usage rather than an
/// approximation — summing these across shares can produce a "used" figure
/// several times the array's size, and it looks entirely plausible.
///
/// `size` is not mapped at all: Unraid reports it as `0` for shares, and a zero
/// rendered as a total is worse than an absent one.
public struct Share: Identifiable, Equatable, Hashable, Sendable {
  public let id: String
  /// Nullable in the schema. See `displayName`.
  public let name: String?
  /// `nameOrig`, and only when it actually differs from `name` — the repository
  /// maps the equal case to `nil`, since a row repeating the name it sits under
  /// is noise.
  public let originalName: String?
  public let comment: String?
  /// Disks explicitly included in this share. **Empty means "all disks"**,
  /// which is a real answer rather than a missing one — Unraid reports `[]` for
  /// a share that names no disks. The wording is the UI's job; the model does not
  /// substitute a sentinel string for it.
  public let includedDisks: [String]
  /// Disks explicitly excluded. Empty means "none excluded".
  public let excludedDisks: [String]
  /// Usually `nil` — the schema declares `cache` as a nullable `Boolean` ("Is
  /// this share cached") and Unraid 7.3 simply doesn't populate it. `nil`
  /// means *not reported*, and must never render as "not cached".
  public let isCached: Bool?
  /// `"highwater"`, `"fillup"`, or `"mostfree"` as Unraid names them. Kept as
  /// the server's own string rather than an enum: it is display-only, and an
  /// enum would need an `.unknown` case to carry exactly the same string
  /// through anyway.
  public let allocator: String?
  /// Split level, e.g. `"1"`. `nil` when the share has none — the wire sends
  /// `""` and the repository maps that to `nil`.
  public let splitLevel: String?
  /// Minimum free space to keep on a disk, in **kilobytes**. Arrives as a
  /// *string* (`"500000000"`); an unparseable value degrades to `nil` rather
  /// than to `0`, since `0` is itself a meaningful floor ("no minimum") and the
  /// two must stay distinguishable.
  public let floorKilobytes: Int64?
  /// Copy-on-write setting, such as `"auto"` or `"no"`. Display-only,
  /// same reasoning as `allocator`.
  public let copyOnWrite: String?
  /// **The pool's** used space, not the share's. See this type's doc comment.
  public let poolUsedKilobytes: Int64?
  /// **The pool's** free space, not the share's.
  public let poolFreeKilobytes: Int64?

  public init(
    id: String, name: String?, originalName: String?, comment: String?,
    includedDisks: [String], excludedDisks: [String], isCached: Bool?,
    allocator: String?, splitLevel: String?, floorKilobytes: Int64?, copyOnWrite: String?,
    poolUsedKilobytes: Int64?, poolFreeKilobytes: Int64?
  ) {
    self.id = id
    self.name = name
    self.originalName = originalName
    self.comment = comment
    self.includedDisks = includedDisks
    self.excludedDisks = excludedDisks
    self.isCached = isCached
    self.allocator = allocator
    self.splitLevel = splitLevel
    self.floorKilobytes = floorKilobytes
    self.copyOnWrite = copyOnWrite
    self.poolUsedKilobytes = poolUsedKilobytes
    self.poolFreeKilobytes = poolFreeKilobytes
  }

  /// `name` when the server reported one, otherwise the share-name half of
  /// `id`. Unraid's ids are `<server-hash>:<share-name>`; the hash is identical
  /// for every entity on the box and carries nothing for a human. Same fallback
  /// shape as `VMDomain.displayName`, for the same reason: a row with an empty
  /// title is not an acceptable rendering of a share that exists.
  public var displayName: String {
    if let name, !name.isEmpty { return name }
    let suffix = id.split(separator: ":").last.map(String.init) ?? ""
    return suffix.isEmpty ? id : suffix
  }

  /// Whether this share leaves disk selection entirely to Unraid — no includes,
  /// no excludes. True for most shares on a real server, which is why the list
  /// and detail screens need a word for it rather than an empty section.
  public var usesAllDisks: Bool {
    includedDisks.isEmpty && excludedDisks.isEmpty
  }
}
