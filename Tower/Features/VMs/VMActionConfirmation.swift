import SwiftUI
import TowerCore

/// Routes a requested action either straight to `perform` or through a
/// confirmation, according to `VMActionCatalog`.
///
/// Shared by the row (swipe actions and context menu) and the detail screen's
/// Actions section, so the two can never disagree about which actions confirm.
/// Each surface deciding for itself means two copies of the same rule set.
func requestVMAction(
  _ action: VMAction,
  vmNamed name: String,
  pending: Binding<VMAction?>,
  perform: (VMAction) -> Void
) {
  if VMActionCatalog.confirmation(for: action, vmNamed: name) == nil {
    perform(action)
  } else {
    pending.wrappedValue = action
  }
}

extension View {
  /// Attaches the confirmation dialog for whatever action `pending` holds,
  /// with the title, message, and button label `VMActionCatalog` specifies.
  ///
  /// `presenting: pending.wrappedValue` hands the action into the button
  /// closure as a non-optional value **captured when SwiftUI builds the
  /// dialog** — not re-read from state when the button is tapped. Reading it at
  /// tap time races `isPresented`'s own dismissal setter, which nils it out: if
  /// SwiftUI drives `isPresented → false` before invoking the action (undefined
  /// ordering, not guaranteed by the API), the tap becomes a silent no-op with
  /// no mutation, no error, and no haptic.
  func vmActionConfirmation(
    pending: Binding<VMAction?>,
    vmNamed name: String,
    perform: @escaping (VMAction) -> Void
  ) -> some View {
    let confirmation = pending.wrappedValue.flatMap {
      VMActionCatalog.confirmation(for: $0, vmNamed: name)
    }
    return confirmationDialog(
      confirmation?.title ?? "",
      isPresented: Binding(
        get: { pending.wrappedValue != nil },
        set: { isPresented in if !isPresented { pending.wrappedValue = nil } }
      ),
      titleVisibility: .visible,
      presenting: pending.wrappedValue
    ) { action in
      Button(
        VMActionCatalog.confirmation(for: action, vmNamed: name)?.confirmTitle ?? action.title,
        role: .destructive
      ) {
        perform(action)
      }
      Button("Cancel", role: .cancel) {}
    } message: { action in
      if let message = VMActionCatalog.confirmation(for: action, vmNamed: name)?.message {
        Text(message)
      }
    }
  }
}
