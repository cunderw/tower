import Testing
import TowerCore

// Issue #25: which array action applies, and when a start needs a passphrase.

private func disk(_ id: String, fsType: String?) -> ArrayDisk {
  ArrayDisk(
    id: id, idx: nil, name: id, device: nil, status: "DISK_OK", temp: nil, size: nil,
    fsFree: nil, fsUsed: nil, fsSize: nil, fsType: fsType, rotational: nil,
    numReads: nil, numWrites: nil, numErrors: nil, type: nil
  )
}

private func array(
  state: String, disks: [ArrayDisk] = [], parities: [ArrayDisk] = [], caches: [ArrayDisk] = []
) -> ArrayStatus {
  ArrayStatus(state: state, capacity: nil, disks: disks, parities: parities, caches: caches, system: nil)
}

struct ArrayActionTests {
  @Test func aStoppedArrayOffersStartOnly() {
    let stopped = array(state: "STOPPED")
    #expect(stopped.canStart)
    #expect(!stopped.canStop)
    #expect(stopped.availableActions == [.start])
  }

  @Test func aStartedArrayOffersStopOnly() {
    let started = array(state: "STARTED")
    #expect(!started.canStart)
    #expect(started.canStop)
    #expect(started.availableActions == [.stop])
  }

  /// A start from one of these can begin a rebuild or a parity sync. That
  /// choice stays in the webGUI.
  @Test(arguments: [
    "NEW_ARRAY", "RECON_DISK", "DISABLE_DISK", "SWAP_DSBL", "INVALID_EXPANSION",
    "PARITY_NOT_BIGGEST", "TOO_MANY_MISSING_DISKS", "NEW_DISK_TOO_SMALL", "NO_DATA_DISKS",
  ])
  func anyOtherStateOffersNothing(state: String) {
    #expect(array(state: state).availableActions.isEmpty)
  }

  @Test func eachActionNamesTheStateItLeadsTo() {
    #expect(ArrayAction.start.targetState == "STARTED")
    #expect(ArrayAction.stop.targetState == "STOPPED")
  }

  @Test func anEncryptedDataOrCacheDiskMakesTheArrayEncrypted() {
    #expect(array(state: "STOPPED", disks: [disk("d1", fsType: "xfs"), disk("d2", fsType: "luks:xfs")]).isEncrypted)
    #expect(array(state: "STOPPED", caches: [disk("c1", fsType: "luks:btrfs")]).isEncrypted)
  }

  @Test func plainFilesystemsAndParityDisksDoNotMakeTheArrayEncrypted() {
    let plain = array(
      state: "STOPPED",
      disks: [disk("d1", fsType: "xfs"), disk("d2", fsType: nil)],
      // A parity disk has no filesystem. Even a value here must not count.
      parities: [disk("p1", fsType: "luks:xfs")],
      caches: [disk("c1", fsType: "btrfs")]
    )
    #expect(!plain.isEncrypted)
    // "luks" alone, or in the middle, is not the webGUI's test.
    #expect(!array(state: "STOPPED", disks: [disk("d1", fsType: "xfsluks:")]).isEncrypted)
  }
}

struct ArrayPassphraseTests {
  @Test(arguments: ["correct horse", "P@ss w0rd!~", " ", "a"])
  func printableASCIIIsValid(passphrase: String) {
    #expect(ArrayPassphrase.isValid(passphrase))
  }

  @Test(arguments: ["", "café", "pass🔑", "tab\there", "new\nline"])
  func emptyOrNonPrintableIsInvalid(passphrase: String) {
    #expect(!ArrayPassphrase.isValid(passphrase))
  }
}
