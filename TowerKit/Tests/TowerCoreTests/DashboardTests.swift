import Testing
import TowerCore

struct ParityStatusTests {
  @Test func mapsKnownStatusStrings() {
    #expect(ParityCheckState(rawValue: "RUNNING") == .running)
    #expect(ParityCheckState(rawValue: "NEVER_RUN") == .neverRun)
    #expect(ParityCheckState(rawValue: "COMPLETED") == .completed)
  }

  /// The server is free to add enum cases; an unknown one must degrade to
  /// `.unknown` rather than crash or silently read as "completed".
  @Test func mapsUnrecognizedStatusToUnknown() {
    #expect(ParityCheckState(rawValue: "SOMETHING_NEW") == .unknown)
  }

  /// `running`/`paused` arrive as null when no check is in flight — Unraid
  /// returns `{"status":"COMPLETED","running":null,"paused":null}`.
  /// A nil `running` must not read as active.
  @Test func isActiveOnlyWhileRunningOrPaused() {
    #expect(ParityStatus.fixture(state: .running).isActive)
    #expect(ParityStatus.fixture(state: .paused).isActive)
    #expect(!ParityStatus.fixture(state: .completed).isActive)
    #expect(!ParityStatus.fixture(state: .neverRun).isActive)
  }

  /// `progress` is an Int percentage on a 0-100 scale; the ring wants 0-1.
  @Test func progressFractionClampsToUnitRange() {
    #expect(ParityStatus.fixture(state: .running, progressPercent: 42).progressFraction == 0.42)
    #expect(ParityStatus.fixture(state: .running, progressPercent: 140).progressFraction == 1)
    #expect(ParityStatus.fixture(state: .running, progressPercent: -3).progressFraction == 0)
    #expect(ParityStatus.fixture(state: .running, progressPercent: nil).progressFraction == nil)
  }
}

struct ServiceCountsTests {
  @Test func summarizesRunningOverTotal() {
    let counts = ServiceCounts(
      containersRunning: 14, containersTotal: 16,
      vmsRunning: 2, vmsTotal: 3,
      sharesTotal: 9
    )
    #expect(counts.containersSummary == "14 of 16 running")
    #expect(counts.vmsSummary == "2 of 3 running")
    #expect(counts.sharesSummary == "9 shares")
  }

  @Test func singularizesOneShare() {
    let counts = ServiceCounts(
      containersRunning: 0, containersTotal: 0,
      vmsRunning: 0, vmsTotal: 0,
      sharesTotal: 1
    )
    #expect(counts.sharesSummary == "1 share")
  }

  /// A nil `vmsRunning`/`vmsTotal` means VM reporting is
  /// unavailable (libvirt stopped or errored), not "zero VMs configured" —
  /// `vmsSummary` must say so rather than printing "0 of 0 running", which
  /// is exactly what a healthy, VM-less server also reports.
  @Test func vmsSummaryReportsUnavailableWhenCountsAreNil() {
    let counts = ServiceCounts(
      containersRunning: 0, containersTotal: 0,
      vmsRunning: nil, vmsTotal: nil,
      sharesTotal: 0
    )
    #expect(counts.vmsSummary == "Unavailable")
  }

  /// Same distinction for Docker: nil counts mean the Docker service is off
  /// and its counts query failed, which must not read as "0 of 0 running".
  @Test func containersSummaryReportsUnavailableWhenCountsAreNil() {
    let counts = ServiceCounts(
      containersRunning: nil, containersTotal: nil,
      vmsRunning: 0, vmsTotal: 0,
      sharesTotal: 0
    )
    #expect(counts.containersSummary == "Unavailable")
  }

  @Test func containersSummaryReportsZeroCountsWhenGenuinelyZero() {
    let counts = ServiceCounts(
      containersRunning: 0, containersTotal: 0,
      vmsRunning: 0, vmsTotal: 0,
      sharesTotal: 0
    )
    #expect(counts.containersSummary == "0 of 0 running")
  }

  /// A healthy server with no VMs defined reports real zeros, which must
  /// still read as "0 of 0 running" — distinct from the nil case above.
  @Test func vmsSummaryReportsZeroCountsWhenGenuinelyZero() {
    let counts = ServiceCounts(
      containersRunning: 0, containersTotal: 0,
      vmsRunning: 0, vmsTotal: 0,
      sharesTotal: 0
    )
    #expect(counts.vmsSummary == "0 of 0 running")
  }
}

extension ParityStatus {
  static func fixture(
    state: ParityCheckState,
    progressPercent: Int? = nil,
    errors: Int? = nil
  ) -> ParityStatus {
    ParityStatus(
      state: state, progressPercent: progressPercent, errors: errors,
      speed: nil, lastRunTimestamp: nil, durationSeconds: nil, correcting: false
    )
  }
}

struct ParityActionTests {
  @Test func anIdleCheckOffersOnlyStartOnAStartedArrayWithParity() {
    for state in [ParityCheckState.neverRun, .completed, .cancelled, .failed] {
      #expect(
        ParityStatus.fixture(state: state).availableActions(arrayStarted: true, hasParityDisks: true) == [.start],
        "\(state)"
      )
    }
  }

  /// Unraid refuses a check on a stopped array, and an array with no parity
  /// disk has nothing to check. A Start button there only produces an error.
  @Test func startIsHiddenOnAStoppedArrayOrWithoutParityDisks() {
    let idle = ParityStatus.fixture(state: .completed)
    #expect(idle.availableActions(arrayStarted: false, hasParityDisks: true).isEmpty)
    #expect(idle.availableActions(arrayStarted: true, hasParityDisks: false).isEmpty)
  }

  @Test func aRunningCheckOffersPauseAndCancel() {
    #expect(
      ParityStatus.fixture(state: .running).availableActions(arrayStarted: true, hasParityDisks: true)
        == [.pause, .cancel]
    )
  }

  @Test func aPausedCheckOffersResumeAndCancel() {
    #expect(
      ParityStatus.fixture(state: .paused).availableActions(arrayStarted: true, hasParityDisks: true)
        == [.resume, .cancel]
    )
  }

  /// A state Tower cannot read gets no button that assumes one.
  @Test func anUnknownStateOffersNothing() {
    #expect(
      ParityStatus.fixture(state: .unknown).availableActions(arrayStarted: true, hasParityDisks: true).isEmpty
    )
  }

  /// The confirmation dialog has its own dismiss button. Two buttons both
  /// labelled "Cancel" that do opposite things is a trap.
  @Test func noActionIsTitledPlainCancel() {
    #expect(!ParityAction.allCases.map(\.title).contains("Cancel"))
  }
}

struct ParityCheckRecordTests {
  private func record(speed: String?) -> ParityCheckRecord {
    ParityCheckRecord(id: 0, date: nil, durationSeconds: nil, speed: speed, state: .completed, errors: nil)
  }

  @Test func speedTextKeepsARealReading() {
    #expect(record(speed: "133.1 MB/s").speedText == "133.1 MB/s")
  }

  /// Every one of these is on the live server's history.
  @Test func speedTextDropsTheServersNonReadings() {
    for speed in [nil, "", "0", "Unavailable", "nan B/s", "NaN MB/s"] {
      #expect(record(speed: speed).speedText == nil, "\(String(describing: speed))")
    }
  }
}
