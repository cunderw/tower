import SwiftUI
import TowerCore

/// A small filled state indicator for list rows.
///
/// The primitive is colour + label, with one convenience initializer per
/// state type below (`ContainerState`, `VMState`), because more than one
/// state enum and several callers share it.
///
/// **Colour is never the only signal.** An orange-glyph-only indicator is
/// silent to VoiceOver. Every `StateDot` carries an accessibility label naming
/// its state regardless of colour, and the rows that use it repeat that same
/// wording in visible text wherever colour alone wouldn't distinguish two
/// states — see `ContainerRow.subtitle` and `VMRow.subtitle`.
struct StateDot: View {
  let color: Color
  /// Spoken instead of the dot itself, which has no visual text. Always the
  /// state's `displayName`, so VoiceOver and sighted users hear and read the
  /// same word.
  let label: String

  var body: some View {
    Circle()
      .fill(color)
      .frame(width: 8, height: 8)
      .accessibilityLabel(label)
  }
}

extension StateDot {
  init(state: ContainerState) {
    self.init(color: state.dotColor, label: state.displayName)
  }

  init(state: VMState) {
    self.init(color: state.dotColor, label: state.displayName)
  }
}

// The colour mappings live here, in the app layer, and not on the enums
// themselves: `TowerCore` imports `Foundation` only and must stay usable from
// a non-SwiftUI context. Same split
// `UsageLevel+Color.swift` already uses for the same reason.

extension ContainerState {
  /// `.green` running, `.orange` paused, `.secondary` exited and unknown.
  var dotColor: Color {
    switch self {
    case .running: .green
    case .paused: .orange
    case .exited, .unknown: .secondary
    }
  }
}

extension VMState {
  /// Driven by `activity`, not by the nine raw states: `IDLE` is a *running*
  /// VM (up, not executing) and must not read as stopped, and `PMSUSPENDED` is
  /// a paused one. `.indeterminate` — a VM mid-shutdown, or a state Tower
  /// can't classify — deliberately shares `.secondary` with stopped rather
  /// than inventing a fourth colour: the row's visible text carries the
  /// distinction ("Shutting Down"), and one more shade of grey would not.
  var dotColor: Color {
    switch activity {
    case .running: .green
    case .paused: .orange
    case .stopped, .indeterminate: .secondary
    }
  }
}

#Preview("Container states") {
  ZStack {
    Color(.systemGroupedBackground).ignoresSafeArea()
    HStack(spacing: 20) {
      VStack { StateDot(state: ContainerState.running); Text("Running").font(.caption2) }
      VStack { StateDot(state: ContainerState.paused); Text("Paused").font(.caption2) }
      VStack { StateDot(state: ContainerState.exited); Text("Exited").font(.caption2) }
      VStack { StateDot(state: ContainerState.unknown); Text("Unknown").font(.caption2) }
    }
    .padding()
  }
}

#Preview("VM states") {
  ZStack {
    Color(.systemGroupedBackground).ignoresSafeArea()
    VStack(spacing: 16) {
      HStack(spacing: 20) {
        VStack { StateDot(state: VMState.running); Text("Running").font(.caption2) }
        VStack { StateDot(state: VMState.idle); Text("Idle").font(.caption2) }
        VStack { StateDot(state: VMState.paused); Text("Paused").font(.caption2) }
        VStack { StateDot(state: VMState.pmSuspended); Text("Suspended").font(.caption2) }
      }
      HStack(spacing: 20) {
        VStack { StateDot(state: VMState.shutoff); Text("Stopped").font(.caption2) }
        VStack { StateDot(state: VMState.crashed); Text("Crashed").font(.caption2) }
        VStack { StateDot(state: VMState.shutdown); Text("Shutting Down").font(.caption2) }
        VStack { StateDot(state: VMState.unknown); Text("Unknown").font(.caption2) }
      }
    }
    .padding()
  }
}
