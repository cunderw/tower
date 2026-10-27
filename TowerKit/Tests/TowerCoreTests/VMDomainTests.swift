import Foundation
import Testing
@testable import TowerCore

@Test func vmStateMapsEveryKnownValue() {
  // All eight schema cases, not a representative sample: `VmState` is a
  // closed enum on the server, and a typo in any one raw string would
  // silently become `.unknown` — which renders as "Unknown" and would look
  // like the server's fault rather than ours.
  #expect(VMState(rawValue: "NOSTATE") == .nostate)
  #expect(VMState(rawValue: "RUNNING") == .running)
  #expect(VMState(rawValue: "IDLE") == .idle)
  #expect(VMState(rawValue: "PAUSED") == .paused)
  #expect(VMState(rawValue: "SHUTDOWN") == .shutdown)
  #expect(VMState(rawValue: "SHUTOFF") == .shutoff)
  #expect(VMState(rawValue: "CRASHED") == .crashed)
  #expect(VMState(rawValue: "PMSUSPENDED") == .pmSuspended)
}

@Test func vmStateMapsUnrecognizedToUnknown() {
  #expect(VMState(rawValue: "BLOCKED") == .unknown)
}

@Test func vmStateDisplayNamesAreHumanNotLibvirt() {
  // The three that deliberately don't echo libvirt's vocabulary — see
  // `VMState.displayName`'s doc comment.
  #expect(VMState.shutoff.displayName == "Stopped")
  #expect(VMState.pmSuspended.displayName == "Suspended")
  #expect(VMState.nostate.displayName == "Unknown")
  // …and the one that must stay distinct from `.shutoff`: a VM that is
  // shutting down is still on, and collapsing the two words would tell a user
  // it had already stopped.
  #expect(VMState.shutdown.displayName == "Shutting Down")
  #expect(VMState.shutdown.displayName != VMState.shutoff.displayName)
}

@Test func vmStateDisplayNameIsNeverEmpty() {
  let every: [VMState] = [
    .nostate, .running, .idle, .paused, .shutdown, .shutoff, .crashed, .pmSuspended, .unknown,
  ]
  #expect(every.allSatisfy { !$0.displayName.isEmpty })
}

@Test func runningAndIdleAreBothRunningActivity() {
  // libvirt's `IDLE` means the domain is up but not executing instructions —
  // a running VM, not a stopped one. Treating it as stopped would offer Start
  // on a VM that is already up.
  #expect(VMState.running.activity == .running)
  #expect(VMState.idle.activity == .running)
}

@Test func pausedAndSuspendedAreBothPausedActivity() {
  #expect(VMState.paused.activity == .paused)
  #expect(VMState.pmSuspended.activity == .paused)
}

@Test func shutoffAndCrashedAreBothStoppedActivity() {
  #expect(VMState.shutoff.activity == .stopped)
  #expect(VMState.crashed.activity == .stopped)
}

@Test func shutdownNostateAndUnknownAreIndeterminate() {
  // The bucket three independent booleans would have hidden. A VM mid-
  // shutdown is neither up nor off; `NOSTATE` and an unrecognized state are
  // states Tower cannot classify at all. None of the three may be treated as
  // "not running, so offer Start."
  #expect(VMState.shutdown.activity == .indeterminate)
  #expect(VMState.nostate.activity == .indeterminate)
  #expect(VMState.unknown.activity == .indeterminate)
}

@Test func displayNameUsesTheServerReportedName() {
  #expect(VMDomain(id: "hash:uuid", name: "Media Server", state: .running).displayName == "Media Server")
}

@Test func displayNameFallsBackToTheUUIDHalfOfTheID() {
  // Unraid ids are `<server-hash>:<uuid>`; the hash is identical for every
  // entity on the box, so it carries nothing a human can use.
  let domain = VMDomain(
    id: "0000000000000000000000000000000000000000000000000000000000000001:00000000-0000-4000-8000-000000000001",
    name: nil,
    state: .shutoff
  )
  #expect(domain.displayName == "00000000-0000-4000-8000-000000000001")
}

@Test func displayNameTreatsAnEmptyNameAsNoName() {
  // The repository maps `""` to `nil` at the boundary; this covers values
  // built by hand (fixtures, previews) that skip that path. An empty title
  // would leave an untappable-looking blank row.
  #expect(VMDomain(id: "hash:uuid", name: "", state: .running).displayName == "uuid")
}

@Test func displayNameFallsBackToTheWholeIDWhenThereIsNoPrefix() {
  #expect(VMDomain(id: "bare-id", name: nil, state: .running).displayName == "bare-id")
}

@Test func inventoryDistinguishesUnavailableFromEmpty() {
  // The whole reason `VMInventory` exists. `nil` means the VM manager isn't
  // reporting; `[]` means a healthy server with no VMs defined.
  // `ServiceCounts` keeps the same distinction on the dashboard.
  #expect(VMInventory(domains: nil).isUnavailable)
  #expect(!VMInventory(domains: []).isUnavailable)
  #expect(VMInventory(domains: nil) != VMInventory(domains: []))
}
