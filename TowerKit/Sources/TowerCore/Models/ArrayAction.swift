import Foundation

/// One `ArrayMutations.setState` request: start or stop the array (issue #25).
public enum ArrayAction: Hashable, Sendable, CaseIterable {
  case start, stop

  /// The verb as it appears on a button.
  public var title: String {
    switch self {
    case .start: "Start Array"
    case .stop: "Stop Array"
    }
  }

  /// The line the hero card shows while the action runs.
  public var progressTitle: String {
    switch self {
    case .start: "Starting the array…"
    case .stop: "Stopping the array…"
    }
  }

  /// A stable slug for accessibility identifiers, `array.action.stop`. Not
  /// derived from `title`, so a copy change cannot repoint a UI test.
  public var identifier: String {
    switch self {
    case .start: "start"
    case .stop: "stop"
    }
  }

  /// The `ArrayState` raw value the array reports when this action is done.
  public var targetState: String {
    switch self {
    case .start: "STARTED"
    case .stop: "STOPPED"
    }
  }
}

extension ArrayStatus {
  /// Whether Start applies. Only a plain `STOPPED` array: Unraid also reports
  /// states such as `RECON_DISK` and `NEW_ARRAY` while stopped, and a start
  /// from one of those can begin a disk rebuild or a new parity sync. That
  /// choice belongs in the webGUI, where Unraid explains it.
  public var canStart: Bool { state == "STOPPED" }

  /// Whether Stop applies.
  public var canStop: Bool { isStarted }

  /// The array actions that apply right now. At most one.
  public var availableActions: [ArrayAction] {
    if canStart { return [.start] }
    if canStop { return [.stop] }
    return []
  }

  /// Whether a start needs a passphrase. The webGUI's test: any data or cache
  /// disk whose filesystem type starts with `luks:` (`luks:xfs`, `luks:btrfs`).
  /// Parity disks carry no filesystem, so they never count.
  public var isEncrypted: Bool {
    (disks + caches).contains { $0.fsType?.hasPrefix("luks:") == true }
  }
}

public enum ArrayPassphrase {
  /// Whether the server can accept `passphrase`. Unraid base64-encodes the
  /// passphrase and accepts printable ASCII only (space to tilde), so an
  /// emoji or an accented letter can never unlock the array. Empty is not
  /// valid either.
  public static func isValid(_ passphrase: String) -> Bool {
    !passphrase.isEmpty && passphrase.unicodeScalars.allSatisfy { (0x20...0x7E).contains($0.value) }
  }
}
