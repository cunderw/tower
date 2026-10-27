import Foundation
import Testing
@testable import TowerCore

@Test func shareDisplayNameUsesTheServerReportedName() {
  #expect(Share.stub(name: "appdata").displayName == "appdata")
}

@Test func shareDisplayNameFallsBackToTheShareNameHalfOfTheID() {
  // Unraid ids are `<server-hash>:<share-name>`; the hash is identical for
  // every entity on the box.
  let share = Share.stub(
    id: "0000000000000000000000000000000000000000000000000000000000000001:backups",
    name: nil
  )
  #expect(share.displayName == "backups")
}

@Test func shareDisplayNameTreatsAnEmptyNameAsNoName() {
  #expect(Share.stub(id: "hash:isos", name: "").displayName == "isos")
}

@Test func usesAllDisksWhenNeitherIncludeNorExcludeNamesAny() {
  // True for most shares on a real server, which is why the UI needs a word
  // for it rather than an empty section.
  #expect(Share.stub(includedDisks: [], excludedDisks: []).usesAllDisks)
}

@Test func doesNotUseAllDisksWhenEitherListNamesADisk() {
  #expect(!Share.stub(includedDisks: ["disk1"], excludedDisks: []).usesAllDisks)
  #expect(!Share.stub(includedDisks: [], excludedDisks: ["disk2"]).usesAllDisks)
}

@Test func poolFiguresAreIdenticalForSharesOnTheSamePoolAndThatIsExpected() {
  // Not a behaviour of this type so much as a fact about the API that the field
  // *names* make legible. Two shares on the cache pool report the same
  // bytes; with the fields called `used`/`free` that reads as a bug, and with
  // them called `poolUsedKilobytes` it reads as what it is.
  let appdata = Share.stub(name: "appdata", poolUsedKilobytes: 412_000_000, poolFreeKilobytes: 588_000_000)
  let downloads = Share.stub(name: "downloads", poolUsedKilobytes: 412_000_000, poolFreeKilobytes: 588_000_000)

  #expect(appdata.poolUsedKilobytes == downloads.poolUsedKilobytes)
  #expect(appdata.poolFreeKilobytes == downloads.poolFreeKilobytes)
  #expect(appdata != downloads)
}

@Test func aNilPoolFigureFormatsAsUnknownRatherThanZero() {
  // An absent reading must not render as a plausible number.
  #expect(Formatters.kilobytes(Share.stub(poolUsedKilobytes: nil).poolUsedKilobytes) == "—")
  #expect(Formatters.kilobytes(Share.stub(poolUsedKilobytes: 0).poolUsedKilobytes) == "Zero KB")
}

extension Share {
  fileprivate static func stub(
    id: String = "hash:share",
    name: String? = "share",
    originalName: String? = nil,
    comment: String? = nil,
    includedDisks: [String] = [],
    excludedDisks: [String] = [],
    isCached: Bool? = nil,
    allocator: String? = "highwater",
    splitLevel: String? = nil,
    floorKilobytes: Int64? = nil,
    copyOnWrite: String? = "auto",
    poolUsedKilobytes: Int64? = 1,
    poolFreeKilobytes: Int64? = 1
  ) -> Share {
    Share(
      id: id, name: name, originalName: originalName, comment: comment,
      includedDisks: includedDisks, excludedDisks: excludedDisks, isCached: isCached,
      allocator: allocator, splitLevel: splitLevel, floorKilobytes: floorKilobytes,
      copyOnWrite: copyOnWrite, poolUsedKilobytes: poolUsedKilobytes,
      poolFreeKilobytes: poolFreeKilobytes
    )
  }
}
