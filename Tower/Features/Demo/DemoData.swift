import Foundation
import TowerCore

/// The seeded dataset demo mode presents.
///
/// **Shaped like a real server, because that is the job.** It contains a
/// stopped container, one with an update available, a disk running warm, and an
/// unread warning notification. That is not decoration: an App Store reviewer
/// looking at a screen of uniformly healthy green rows learns nothing about
/// what the app is for. Every state the UI can render is present somewhere in
/// here.
///
/// Nothing in this file names a real server. The hostname is "Tower" (Unraid's
/// default), the address is a documentation-range IP, and no API key appears —
/// see `DemoData.server`.
enum DemoData {
  /// The `Server` demo mode runs against. Never contacted: every repository is a
  /// demo conformance.
  ///
  /// `192.0.2.x` is TEST-NET-1, reserved by RFC 5737 for documentation and
  /// guaranteed never to route — so a screenshot of Settings can't leak a real
  /// address, and a bug that somehow reached the network would fail immediately
  /// rather than reaching someone's actual machine. The API key is a visibly fake
  /// placeholder, since Settings shows its last four characters.
  static let server = Server(
    name: "Tower",
    url: URL(string: "http://192.0.2.10")!,
    apiKey: "demo-mode-no-key-0000"
  )

  // MARK: - Array

  /// A 36 TB array at 74% — full enough that the capacity ring reads as a real
  /// server under load, not so full that it looks broken.
  static let array = ArrayStatus(
    state: "STARTED",
    capacity: ArrayCapacity(free: 9_400_000_000, used: 26_600_000_000, total: 36_000_000_000),
    disks: [
      ArrayDisk(
        id: "demo-disk-1", idx: 1, name: "disk1", device: "sdb", status: "DISK_OK",
        temp: 34, size: 12_000_000_000, fsFree: 2_100_000_000, fsUsed: 9_900_000_000,
        fsSize: 12_000_000_000, fsType: "xfs", rotational: true, numReads: 128_552_310,
        numWrites: 4_221_009, numErrors: 0, type: "DATA"
      ),
      // The disk running warm: 51 °C crosses `UsageLevel`'s
      // warning threshold, so the temperature styling and its accessibility
      // wording are both reachable without anything being broken.
      ArrayDisk(
        id: "demo-disk-2", idx: 2, name: "disk2", device: "sdc", status: "DISK_OK",
        temp: 51, size: 12_000_000_000, fsFree: 900_000_000, fsUsed: 11_100_000_000,
        fsSize: 12_000_000_000, fsType: "xfs", rotational: true, numReads: 96_220_144,
        numWrites: 3_884_512, numErrors: 0, type: "DATA"
      ),
      ArrayDisk(
        id: "demo-disk-3", idx: 3, name: "disk3", device: "sdd", status: "DISK_OK",
        temp: 33, size: 12_000_000_000, fsFree: 6_400_000_000, fsUsed: 5_600_000_000,
        fsSize: 12_000_000_000, fsType: "xfs", rotational: true, numReads: 44_190_882,
        numWrites: 1_204_776, numErrors: 0, type: "DATA"
      ),
    ],
    parities: [
      // Parity disks genuinely have no filesystem, so the fs fields are nil here
      // — matching what the live mapping produces rather than inventing numbers.
      ArrayDisk(
        id: "demo-parity-1", idx: 0, name: "parity", device: "sde", status: "DISK_OK",
        temp: 37, size: 12_000_000_000, fsFree: nil, fsUsed: nil, fsSize: nil,
        fsType: nil, rotational: true, numReads: 98_112_004, numWrites: 12_500,
        numErrors: 0, type: "PARITY"
      ),
    ],
    caches: [
      ArrayDisk(
        id: "demo-cache-1", idx: 30, name: "cache", device: "nvme0n1", status: "DISK_OK",
        temp: 38, size: 1_000_000_000, fsFree: 588_000_000, fsUsed: 412_000_000,
        fsSize: 1_000_000_000, fsType: "btrfs", rotational: false, numReads: 55_002,
        numWrites: 1_204, numErrors: 0, type: "CACHE"
      ),
    ],
    system: SystemInfo(
      distro: "Unraid OS", release: "7.3.0", bootTimestamp: DemoData.bootTimestamp,
      cpuBrand: "Example 8-Core CPU", cpuCores: 8, cpuThreads: 16,
      cpuPercent: 14, memoryPercent: 61,
      memoryUsedBytes: 19_520_000_000, memoryTotalBytes: 32_000_000_000
    )
  )

  /// A parity check in progress: the one state that makes the hero card's
  /// progress bar reachable.
  static let parity = ParityStatus(
    state: .running,
    progressPercent: 63,
    errors: 0,
    speed: "150 MB/s",
    lastRunTimestamp: nil,
    durationSeconds: nil,
    correcting: true
  )

  /// 12 days before whenever the demo is opened, so uptime reads as a plausible
  /// duration rather than a fixed date that ages into nonsense.
  ///
  /// Formatted with the **same** `ISO8601FormatStyle` that
  /// `Formatters.parseTimestamp` parses with. A hand-assembled style (dashes,
  /// colons, fractional seconds, but no `T` and no zone) produces a string the
  /// parser rejects, and the dashboard renders "Uptime — Unknown" in the demo.
  static var bootTimestamp: String {
    Date(timeIntervalSinceNow: -12 * 24 * 60 * 60)
      .formatted(Date.ISO8601FormatStyle(includingFractionalSeconds: true))
  }

  // MARK: - Docker

  /// Eight containers: mostly running, one stopped, one with an update available,
  /// one paused. Real image names, because a reviewer who runs Unraid recognises
  /// them and a made-up one reads as filler.
  static let containers: [Container] = [
    container(name: "code-server", state: .running, status: "Up 11 days", port: 8_443, privatePort: 8_443),
    container(name: "emby", state: .running, status: "Up 11 days", port: 8_096),
    // The stopped container.
    container(name: "freshrss", state: .exited, status: "Exited (0) 3 hours ago"),
    container(name: "heimdall", state: .running, status: "Up 11 days", port: 8_090),
    container(name: "nextcloud", state: .paused, status: "Paused", port: 8_444),
    container(name: "plex", state: .running, status: "Up 11 days", port: 32_400),
    container(name: "sonarr", state: .running, status: "Up 6 days", port: 8_989),
    // The update-available container.
    container(name: "webtop", state: .running, status: "Up 6 days", port: 3_000, hasUpdate: true),
  ]

  private static func container(
    name: String, state: ContainerState, status: String,
    port: Int? = nil, privatePort: Int = 80, hasUpdate: Bool = false
  ) -> Container {
    Container(
      id: "demo-container-\(name)",
      names: ["/\(name)"],
      image: "linuxserver/\(name):latest",
      state: state,
      status: status,
      autoStart: state != .exited,
      // `nil` rather than `false` for the rest: the schema's nullable
      // `isUpdateAvailable` means "not determined", and a demo that claimed every
      // other container was definitively up to date would be modelling the API
      // wrongly.
      isUpdateAvailable: hasUpdate ? true : nil,
      isOrphaned: false,
      webUiURL: port.map { URL(string: "http://192.0.2.10:\($0)")! },
      iconURL: nil,
      projectURL: URL(string: "https://github.com/linuxserver/docker-\(name)"),
      supportURL: nil,
      registryURL: URL(string: "https://hub.docker.com/r/linuxserver/\(name)"),
      templatePath: "/boot/config/plugins/dockerMan/templates-user/\(name).xml",
      networkMode: "bridge",
      ports: port.map { [ContainerPort(ip: "0.0.0.0", privatePort: privatePort, publicPort: $0, type: "TCP")] } ?? []
    )
  }

  // MARK: - VMs

  /// One of each state a VM's action set branches on, so every branch of the
  /// detail screen is reachable from the demo.
  ///
  /// Ids follow Unraid's `<server-hash>:<uuid>` shape. The detail screen shows
  /// the UUID half, so each is an invented UUID that reads like a real one; the
  /// hash half is never shown and stays zero-filled.
  static let domains: [VMDomain] = [
    VMDomain(id: vmID("7c41e2d9-8b3a-4f06-9d52-1ae0c6b8f374"), name: "Debian Desktop", state: .running),
    VMDomain(id: vmID("e09b5a17-3c6d-4e81-b2f4-58d7a0c9e126"), name: "Ubuntu Server", state: .running),
    VMDomain(id: vmID("4fa8d361-0e2b-4c97-8a1d-c3b56e72f09a"), name: "Windows 11", state: .shutoff),
  ]

  private static func vmID(_ uuid: String) -> String {
    String(repeating: "0", count: 64) + ":" + uuid
  }

  // MARK: - Shares

  /// Both pools represented, with the pool figures differing between them: Unraid
  /// reports pool usage, not per-share usage, so shares on one pool report
  /// identical numbers, and the detail screen says whose they are.
  static let shares: [Share] = [
    share(name: "appdata", comment: nil, onCache: true, splitLevel: nil),
    share(name: "backups", comment: nil, onCache: false, splitLevel: nil),
    share(name: "documents", comment: "scanned paperwork", onCache: false, splitLevel: nil),
    share(name: "domains", comment: "saved VM instances", onCache: true, splitLevel: "1"),
    share(name: "downloads", comment: nil, onCache: true, splitLevel: nil),
    share(name: "isos", comment: "ISO images", onCache: false, splitLevel: nil),
    share(name: "media", comment: nil, onCache: false, splitLevel: nil),
    share(name: "system", comment: "system data", onCache: true, splitLevel: "1"),
  ]

  private static func share(
    name: String, comment: String?, onCache: Bool, splitLevel: String?
  ) -> Share {
    Share(
      id: "demo-share-\(name)",
      name: name,
      originalName: nil,
      comment: comment,
      includedDisks: [],
      excludedDisks: [],
      isCached: nil,
      allocator: "highwater",
      splitLevel: splitLevel,
      floorKilobytes: 0,
      copyOnWrite: splitLevel == nil ? "auto" : "no",
      // Identical within a pool, different between pools — exactly what the real
      // API reports, and what the detail screen's "the whole pool, not this share"
      // header exists to explain.
      poolUsedKilobytes: onCache ? 412_000_000 : 26_600_000_000,
      poolFreeKilobytes: onCache ? 588_000_000 : 9_400_000_000
    )
  }

  // MARK: - Notifications

  /// Including an unread warning, plus an alert and an
  /// archived info — so the bell has a badge, the sheet has both buckets
  /// populated, and every importance is represented.
  static var notifications: [ServerNotification] {
    [
      notification(
        id: "demo-notification-1", subject: "Disk temperature",
        description: "disk2 is running at 51 °C", importance: .warning,
        kind: .unread, minutesAgo: 25, link: "/Main"
      ),
      notification(
        id: "demo-notification-2", subject: "Update available",
        description: "A new version of webtop is available", importance: .info,
        kind: .unread, minutesAgo: 180, link: "/Docker"
      ),
      notification(
        id: "demo-notification-3", subject: "Parity check started",
        description: "A correcting parity check is running", importance: .info,
        kind: .unread, minutesAgo: 240, link: nil
      ),
      notification(
        id: "demo-notification-4", subject: "Array started",
        description: "The array has been started", importance: .info,
        kind: .archive, minutesAgo: 17_280, link: nil
      ),
      notification(
        id: "demo-notification-5", subject: "UPS on battery",
        description: "The UPS switched to battery power and has since recovered",
        importance: .alert, kind: .archive, minutesAgo: 20_160, link: "/Settings/UPSsettings"
      ),
    ]
  }

  private static func notification(
    id: String, subject: String, description: String,
    importance: NotificationImportance, kind: NotificationKind,
    minutesAgo: Int, link: String?
  ) -> ServerNotification {
    ServerNotification(
      id: id,
      title: importance == .info ? "Unraid Status" : "Unraid Server Alert",
      subject: subject,
      description: description,
      importance: importance,
      kind: kind,
      linkPath: link,
      // Relative to now, so "25 minutes ago" stays true whenever the demo is
      // opened rather than drifting into "3 years ago".
      timestamp: Date(timeIntervalSinceNow: -Double(minutesAgo) * 60)
    )
  }

  // MARK: - Logs

  static let logFiles: [LogFile] = [
    LogFile(name: "docker.log", path: "/var/log/docker.log", sizeBytes: 51_432,
            modifiedAt: Date(timeIntervalSinceNow: -600)),
    LogFile(name: "syslog", path: "/var/log/syslog", sizeBytes: 184_320,
            modifiedAt: Date(timeIntervalSinceNow: -60)),
    // An empty one, because most of a real box's log files are.
    LogFile(name: "wg-quick.log", path: "/var/log/wg-quick.log", sizeBytes: 0, modifiedAt: nil),
  ]

  /// Plausible syslog output rather than "line 1, line 2" — a screenshot of the
  /// log viewer is one of the App Store screenshots, and filler reads as filler.
  static func logContents(path: String, lines: Int) -> LogFileContents {
    guard path != "/var/log/wg-quick.log" else {
      return LogFileContents(path: path, lines: [], totalLines: 0, startLine: nil)
    }
    let total = 420
    let count = min(total, max(1, lines))
    let messages = [
      "kernel: mdcmd (37): check correct",
      "emhttpd: read SMART /dev/sdb",
      "root: mover: started",
      "kernel: XFS (md1p1): Ending clean mount",
      "avahi-daemon[3172]: Service \"Tower\" successfully established.",
      "nginx: 2026/07/30 09:14:02 [notice] signal process started",
      "root: mover: finished",
      "emhttpd: shcmd (1204): /usr/local/sbin/mount_image",
    ]
    let rendered = ((total - count + 1)...total).map { index in
      "Jul 30 09:\(String(format: "%02d", index % 60)):\(String(format: "%02d", (index * 7) % 60)) Tower \(messages[index % messages.count])"
    }
    return LogFileContents(
      path: path, lines: rendered, totalLines: total, startLine: total - count + 1
    )
  }
}
