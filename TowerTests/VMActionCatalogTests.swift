import Foundation
import Testing
import TowerCore
@testable import Tower

/// The action rules are the safety-critical part of the VMs tab: they decide
/// whether someone is offered a button that cuts power to a running machine.
/// They live in `VMActionCatalog` precisely so they can be tested here rather
/// than only observed through three SwiftUI surfaces.
@MainActor
struct VMActionCatalogTests {
  private let everyState: [VMState] = [
    .nostate, .running, .idle, .paused, .shutdown, .shutoff, .crashed, .pmSuspended, .unknown,
  ]

  // MARK: - Availability

  @Test func aRunningVMIsNeverOfferedStart() {
    // libvirt rejects `start` on a domain that is already up. Offering it would
    // be a button that always fails.
    for state in everyState where state.activity == .running {
      #expect(!VMActionCatalog.actions(for: state).contains(.start), "\(state) offered Start")
    }
  }

  @Test func aPausedVMIsOfferedResumeAndNeverStart() {
    // The same trap `ContainerRow.canStop` documents for paused containers: a
    // paused VM is *up*, so Resume is the action, not Start.
    for state in everyState where state.activity == .paused {
      let actions = VMActionCatalog.actions(for: state)
      #expect(actions.contains(.resume), "\(state) didn't offer Resume")
      #expect(!actions.contains(.start), "\(state) offered Start")
      #expect(actions.contains(.stop), "\(state) couldn't be stopped")
    }
  }

  @Test func aStoppedVMIsOfferedOnlyStart() {
    for state in everyState where state.activity == .stopped {
      #expect(VMActionCatalog.actions(for: state) == [.start], "\(state) offered more than Start")
    }
  }

  @Test func anIndeterminateStateIsOfferedOnlyForceStop() {
    // `SHUTDOWN` is mid-shutdown — still on, so Start would be rejected — and
    // `NOSTATE`/`.unknown` are states Tower cannot classify. Force Stop is the
    // only lever that makes sense for a VM stuck on its way down, and guessing
    // any other is worse than offering one.
    for state in [VMState.shutdown, .nostate, .unknown] {
      #expect(VMActionCatalog.actions(for: state) == [.forceStop], "\(state) offered more than Force Stop")
    }
  }

  @Test func everyStateOffersAtLeastOneAction() {
    // A state with no actions is a dead-end screen. All nine must offer a way
    // out, including the ones this build doesn't recognize.
    for state in everyState {
      #expect(!VMActionCatalog.actions(for: state).isEmpty, "\(state) offered nothing at all")
    }
  }

  @Test func powerCordActionsAreOrderedLast() {
    // Ordering is part of the safety story, not cosmetic: Reset sitting
    // directly under Stop is one mis-tap from a hard reboot. Force Stop and
    // Reset always come after every graceful action.
    for state in everyState {
      let actions = VMActionCatalog.actions(for: state)
      let isPowerCord: (VMAction) -> Bool = { $0 == .forceStop || $0 == .reset }
      let powerCordIndices = actions.indices.filter { isPowerCord(actions[$0]) }
      let gracefulIndices = actions.indices.filter { !isPowerCord(actions[$0]) }
      guard let firstPowerCord = powerCordIndices.min(), let lastGraceful = gracefulIndices.max() else {
        // A state offering only power-cord actions (indeterminate) or only
        // graceful ones (stopped) has nothing to order.
        continue
      }
      #expect(firstPowerCord > lastGraceful, "\(state) put a power-cord action before a graceful one")
    }
  }

  @Test func aPausedVMIsNotOfferedReboot() {
    // libvirt can't ask a paused guest to shut down cleanly, so Reboot would
    // always be refused. Force Stop and Reset remain, since neither needs the
    // guest to cooperate.
    #expect(!VMActionCatalog.actions(for: .paused).contains(.reboot))
    #expect(VMActionCatalog.actions(for: .paused).contains(.forceStop))
  }

  // MARK: - Confirmation copy

  @Test func startPauseAndResumeNeedNoConfirmation() {
    for action in [VMAction.start, .pause, .resume] {
      #expect(
        VMActionCatalog.confirmation(for: action, vmNamed: "Windows XP") == nil,
        "\(action.title) asked for a confirmation it doesn't need"
      )
    }
  }

  @Test func everyInterruptingActionConfirms() {
    for action in [VMAction.stop, .reboot, .forceStop, .reset] {
      #expect(
        VMActionCatalog.confirmation(for: action, vmNamed: "Windows XP") != nil,
        "\(action.title) would interrupt a running machine without asking"
      )
    }
  }

  @Test func forceStopSaysItCutsPowerAndLosesData() throws {
    // What this whole type exists for. "Force Stop" alone reads like a
    // slightly firmer Stop; the dialog has to say what it actually is.
    let confirmation = try #require(VMActionCatalog.confirmation(for: .forceStop, vmNamed: "Windows XP"))

    #expect(confirmation.title == "Force Stop Windows XP?")
    #expect(confirmation.message.contains("pulling the plug"))
    #expect(confirmation.message.contains("Unsaved data"))
    #expect(confirmation.confirmTitle == "Force Stop")
  }

  @Test func resetSaysItRestartsWithoutShuttingDownAndLosesData() throws {
    let confirmation = try #require(VMActionCatalog.confirmation(for: .reset, vmNamed: "Windows XP"))

    #expect(confirmation.title == "Reset Windows XP?")
    #expect(confirmation.message.contains("without shutting it down"))
    #expect(confirmation.message.contains("Unsaved data"))
  }

  @Test func stopAndRebootDoNotClaimDataLoss() {
    // The other half of the distinction: a graceful stop or reboot asks the
    // guest to shut down, so warning about lost data would be crying wolf and
    // would make the Force Stop warning mean less.
    for action in [VMAction.stop, .reboot] {
      let message = VMActionCatalog.confirmation(for: action, vmNamed: "Windows XP")?.message ?? ""
      #expect(!message.contains("Unsaved data"), "\(action.title) warned about data loss it doesn't cause")
      #expect(!message.isEmpty, "\(action.title)'s dialog says nothing beyond its title")
    }
  }

  @Test func everyConfirmationNamesTheVM() {
    // A dialog that says "Stop this VM?" while three rows are on screen is a
    // dialog nobody can safely confirm.
    for action in [VMAction.stop, .reboot, .forceStop, .reset] {
      let title = VMActionCatalog.confirmation(for: action, vmNamed: "Arcade Box")?.title ?? ""
      #expect(title.contains("Arcade Box"), "\(action.title)'s dialog doesn't name the VM")
    }
  }

  // MARK: - Presentation

  @Test func onlyInterruptingActionsAreDestructive() {
    #expect(!VMActionCatalog.isDestructive(.start))
    #expect(!VMActionCatalog.isDestructive(.resume))
    #expect(!VMActionCatalog.isDestructive(.pause))
    #expect(VMActionCatalog.isDestructive(.stop))
    #expect(VMActionCatalog.isDestructive(.reboot))
    #expect(VMActionCatalog.isDestructive(.forceStop))
    #expect(VMActionCatalog.isDestructive(.reset))
  }

  @Test func forceStopAndResetDoNotShareAGlyphWithTheirGracefulCounterparts() {
    // Same icon for Stop and Force Stop (or Reboot and Reset) would undo the
    // copy: at a glance the menu would read as two identical buttons.
    #expect(VMActionCatalog.systemImage(for: .forceStop) != VMActionCatalog.systemImage(for: .stop))
    #expect(VMActionCatalog.systemImage(for: .reset) != VMActionCatalog.systemImage(for: .reboot))
  }

  @Test func actionIdentifiersAreStableAndDistinct() {
    // UI tests name these. Derived from the title they'd break invisibly on a
    // copy change; duplicated they'd make two buttons indistinguishable.
    let identifiers = [VMAction.start, .stop, .forceStop, .pause, .resume, .reboot, .reset].map(\.identifier)
    #expect(Set(identifiers).count == identifiers.count)
    #expect(identifiers.allSatisfy { !$0.isEmpty })
    #expect(VMAction.forceStop.identifier == "forceStop")
  }
}
