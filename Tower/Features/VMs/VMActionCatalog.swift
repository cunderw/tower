import Foundation
import TowerCore

/// Which actions a VM in a given state may be offered, and what each one has to
/// say before it runs.
///
/// A single type rather than logic duplicated across the row's context menu, its
/// swipe actions, and the detail screen's Actions section. `ContainerRow` and
/// `ContainerDetailView` deliberately kept two copies of the equivalent Docker
/// rules, with a comment saying the third surface would be the time to extract —
/// VMs open with three surfaces and seven actions, four of which need distinct
/// confirmation copy, so the copy lives here once and is unit-tested. Two
/// surfaces disagreeing about whether a paused VM can be started, or about what
/// Force Stop does to unsaved data, is exactly the kind of drift a shared
/// catalog prevents.
///
/// The views still own their own `@State` for presenting a dialog — SwiftUI
/// requires that per view — but not the decision of *whether* to present one.
enum VMActionCatalog {
  /// Every action offered for `state`, in the order they should appear:
  /// graceful first, power-cord last. Ordering is part of the safety story, not
  /// cosmetic — Reset sitting directly under Stop is a mis-tap away from a hard
  /// reboot.
  ///
  /// Derived from `VMState.activity`, so all nine states are covered by four
  /// rules and a new server-side state can't silently fall into the wrong one.
  static func actions(for state: VMState) -> [VMAction] {
    switch state.activity {
    case .running:
      // No Start: libvirt rejects it on a domain that is already up.
      [.stop, .pause, .reboot, .forceStop, .reset]
    case .paused:
      // Resume, not Start — and Stop still applies, since a paused VM is up.
      // Reboot is omitted: libvirt cannot ask a paused guest to shut down
      // cleanly, so it would be an action that always fails.
      [.resume, .stop, .forceStop, .reset]
    case .stopped:
      [.start]
    case .indeterminate:
      // `SHUTDOWN` (mid-shutdown), `NOSTATE`, or a state this build doesn't
      // recognize. Force Stop is the only action that makes sense for a VM
      // stuck on its way down, and offering Start to something Tower cannot
      // classify would be a guess. If the server disagrees, the refusal
      // surfaces through `AppError.actionRefused` rather than being hidden.
      [.forceStop]
    }
  }

  /// The confirmation an action needs before it runs, or `nil` when it needs
  /// none.
  ///
  /// Start, Pause, and Resume have nothing to lose and skip it. The other four
  /// interrupt a machine someone is using, and **Force Stop and Reset say what
  /// they actually do**: "Force Stop" on its own reads like a slightly firmer
  /// Stop, when it is the equivalent of pulling the power cord out of a running
  /// computer.
  static func confirmation(for action: VMAction, vmNamed name: String) -> Confirmation? {
    switch action {
    case .start, .pause, .resume:
      nil
    case .stop:
      Confirmation(
        title: "Stop \(name)?",
        message: "The VM is asked to shut down. This may take a while.",
        confirmTitle: "Stop"
      )
    case .reboot:
      Confirmation(
        title: "Reboot \(name)?",
        message: "The VM is asked to restart. Anything running inside it stops.",
        confirmTitle: "Reboot"
      )
    case .forceStop:
      Confirmation(
        title: "Force Stop \(name)?",
        message: "This cuts power to the VM immediately, like pulling the plug. Unsaved data inside it is lost.",
        confirmTitle: "Force Stop"
      )
    case .reset:
      Confirmation(
        title: "Reset \(name)?",
        message: "This restarts the VM immediately without shutting it down, like holding the reset button. Unsaved data inside it is lost.",
        confirmTitle: "Reset"
      )
    }
  }

  /// Whether an action should be styled as destructive wherever it appears.
  /// Everything that interrupts a running machine is; nothing that starts or
  /// resumes one is.
  static func isDestructive(_ action: VMAction) -> Bool {
    switch action {
    case .start, .pause, .resume: false
    case .stop, .reboot, .forceStop, .reset: true
    }
  }

  /// The SF Symbol for an action, so the row menu and the detail buttons can't
  /// pick different glyphs for the same thing.
  static func systemImage(for action: VMAction) -> String {
    switch action {
    case .start: "play.fill"
    case .stop: "stop.fill"
    case .forceStop: "bolt.slash.fill"
    case .pause: "pause.fill"
    case .resume: "play.fill"
    case .reboot: "arrow.clockwise"
    case .reset: "exclamationmark.arrow.circlepath"
    }
  }

  /// What a confirmation dialog needs to render. `message` is never optional:
  /// every confirmed action here has something worth saying beyond its own
  /// title, and an action whose dialog is just its name repeated twice is one
  /// nobody reads.
  struct Confirmation: Equatable {
    let title: String
    let message: String
    /// The destructive button's own label — the verb alone ("Force Stop"),
    /// since the title already names the VM.
    let confirmTitle: String
  }
}
