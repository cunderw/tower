import SwiftUI
import TowerCore

/// Start Array on a stopped array, Stop Array on a started one (issue #25).
/// Nothing for any other state; see `ArrayStatus.canStart`.
///
/// Stop asks for confirmation and names what stops with the array. Start on an
/// encrypted array asks for the passphrase in a sheet. Start on a plain array
/// runs at once: starting is what the server is for, and nothing stops.
///
/// **The passphrase.** It lives in this view's `@State` while the sheet is up,
/// goes straight into `perform`, and is cleared when the sheet closes, however
/// it closes. It never reaches an identifier, a label or a log.
struct ArrayStateControls: View {
  let array: ArrayStatus
  /// The array action in flight, which shows its progress line in place of
  /// the button.
  let actionInFlight: ArrayAction?
  /// Disables the button while any action runs, parity included.
  let isDisabled: Bool
  /// The action and, for an encrypted start, the passphrase.
  let perform: (ArrayAction, String?) -> Void

  @State private var isConfirmingStop = false
  @State private var isAskingForPassphrase = false

  var body: some View {
    if let actionInFlight {
      // A disabled button in the same style, so the card does not change
      // height when the action starts and ends.
      Button {} label: {
        HStack(spacing: 6) {
          ProgressView()
          Text(actionInFlight.progressTitle)
        }
      }
      .buttonStyle(.bordered)
      .disabled(true)
      .accessibilityIdentifier("array.progress")
    } else if let action = array.availableActions.first {
      button(for: action)
        .buttonStyle(.bordered)
        .disabled(isDisabled)
    }
  }

  @ViewBuilder
  private func button(for action: ArrayAction) -> some View {
    switch action {
    case .start:
      Button {
        if array.isEncrypted { isAskingForPassphrase = true } else { perform(.start, nil) }
      } label: {
        label(action, systemImage: "play.fill")
      }
      .accessibilityIdentifier("array.action.start")
      .sheet(isPresented: $isAskingForPassphrase) {
        ArrayPassphraseSheet { passphrase in perform(.start, passphrase) }
      }
    case .stop:
      Button(role: .destructive) { isConfirmingStop = true } label: {
        label(action, systemImage: "stop.fill")
      }
      .accessibilityIdentifier("array.action.stop")
      // On the button, not the container, so the iPad popover points at it.
      .confirmationDialog("Stop the array?", isPresented: $isConfirmingStop, titleVisibility: .visible) {
        Button("Stop Array", role: .destructive) { perform(.stop, nil) }
        Button("Cancel", role: .cancel) {}
      } message: {
        Text(
          "The Docker containers and VMs that use the array stop too, "
            + "and its shares are unavailable until the array starts again."
        )
      }
    }
  }

  /// Icon and title at a fixed spacing, as `ParityControls` draws them.
  private func label(_ action: ArrayAction, systemImage: String) -> some View {
    HStack(spacing: 6) {
      Image(systemName: systemImage)
        .accessibilityHidden(true)
      Text(action.title)
    }
  }
}

/// The passphrase prompt for an encrypted array's start.
///
/// No `.textContentType(.password)`: that offers to save the passphrase to
/// the user's passwords, and Tower must not store it anywhere. A fresh sheet
/// makes a fresh `@State`, so the field is empty every time it opens.
private struct ArrayPassphraseSheet: View {
  let start: (String) -> Void

  @State private var passphrase = ""
  @FocusState private var isFieldFocused: Bool
  @Environment(\.dismiss) private var dismiss

  private var isValid: Bool { ArrayPassphrase.isValid(passphrase) }
  /// Only after something is typed. An empty field is not an error yet.
  private var showsInvalidCharacters: Bool { !passphrase.isEmpty && !isValid }

  var body: some View {
    NavigationStack {
      Form {
        Section {
          SecureField("Passphrase", text: $passphrase)
            .focused($isFieldFocused)
            .submitLabel(.go)
            .onSubmit(submit)
            .accessibilityIdentifier("array.passphrase.field")
        } footer: {
          if showsInvalidCharacters {
            Text("Use only letters, digits, spaces and the symbols on a US keyboard.")
              .foregroundStyle(.red)
              .accessibilityIdentifier("array.passphrase.invalid")
          } else {
            Text("The array is encrypted. Tower sends the passphrase to your server to start the array, and does not save it.")
          }
        }
      }
      .navigationTitle("Unlock the Array")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { close() }
            .accessibilityIdentifier("array.passphrase.cancel")
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Start", action: submit)
            .disabled(!isValid)
            .accessibilityIdentifier("array.passphrase.start")
        }
      }
    }
    // One field and a footer: a full-height sheet is mostly empty.
    .presentationDetents([.medium])
    .onAppear { isFieldFocused = true }
    // A swipe down closes the sheet without `close()`.
    .onDisappear { passphrase = "" }
  }

  private func submit() {
    guard isValid else { return }
    let entered = passphrase
    close()
    start(entered)
  }

  private func close() {
    passphrase = ""
    dismiss()
  }
}
