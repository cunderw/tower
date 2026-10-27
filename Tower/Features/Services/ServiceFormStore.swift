import Foundation
import Observation
import TowerCore
import TowerData

/// The service form's state, and the two things it can do: test the connection,
/// and save the instance.
///
/// One store for both add and edit: the fields, validation, and test are
/// identical, and the only difference is whether `editing` carries the instance
/// being replaced. A separate edit store would be this file with one line
/// changed, and would drift from it.
///
/// All of it lives here rather than in the view so the validation rules and the
/// test-result copy are exercisable without SwiftUI — the same reason
/// `ConnectStore` exists for the Unraid connect screen.
@MainActor
@Observable
final class ServiceFormStore: Identifiable {
  /// `Identifiable` only so the hub can present it with `.sheet(item:)`, which
  /// is what guarantees the sheet gets a *fresh* store per presentation rather
  /// than reusing one holding the last attempt's credentials.
  let id = UUID()

  var kind: ServiceKind = .radarr {
    didSet {
      guard oldValue != kind else { return }
      // Changing the kind changes which credential fields exist, so anything
      // typed into the ones that just disappeared must go with them — otherwise
      // a password typed for NZBGet would be silently saved onto a Radarr.
      clearCredentials()
      testResult = nil
      if isNameAuto { name = kind.displayName }
    }
  }
  /// Free text; defaults to the kind's display name until the user types
  /// something, so "Radarr" needs no typing and "Radarr 4K" needs three keys.
  var name: String = ServiceKind.radarr.displayName {
    didSet { isNameAuto = name.isEmpty || name == kind.displayName }
  }
  var urlText: String = ""
  var apiKey: String = ""
  var username: String = ""
  var password: String = ""
  var customHeaders: [HeaderDraft] = []

  private(set) var isTesting = false
  /// `nil` until the user tests, and cleared whenever an input that would change
  /// the answer changes.
  private(set) var testResult: ServiceStatus?
  private(set) var saveError: AppError?

  /// Services recognised among the Unraid box's running containers. Empty when
  /// there is no server attached, when the list can't be fetched, or when
  /// nothing on it is recognised — in all three cases the form is unchanged and
  /// manual entry carries on.
  private(set) var candidates: [ServiceCandidate] = []

  private var isNameAuto = true
  private let directory: any ServiceDirectoryStoring
  private let checker: any ServiceStatusChecking
  private let assist: DockerServiceAssist?
  /// The instance being edited, or `nil` when this is an add. Its id and
  /// `isEnabled` are carried through the save so an edit updates the record in
  /// place rather than adding a second one.
  private let editing: ServiceInstance?

  var isEditing: Bool { editing != nil }

  init(
    directory: any ServiceDirectoryStoring,
    checker: any ServiceStatusChecking,
    assist: DockerServiceAssist? = nil,
    editing: ServiceInstance? = nil
  ) {
    self.directory = directory
    self.checker = checker
    self.assist = assist
    self.editing = editing
    if let editing {
      kind = editing.kind
      name = editing.name
      isNameAuto = false
      urlText = editing.baseURL.absoluteString
      switch editing.credentials {
      case .apiKey(let key):
        apiKey = key
      case .usernamePassword(let user, let password):
        username = user
        self.password = password
      }
      customHeaders = editing.customHeaders
        .sorted { $0.key < $1.key }
        .map { HeaderDraft(field: $0.key, value: $0.value) }
    }
  }

  /// Loads the Docker-assisted candidates. Deliberately non-throwing: the
  /// assist is a convenience on top of a form that already works without it, so
  /// a failed container query must not put an error in front of someone who was
  /// about to type an address anyway.
  func loadCandidates() async {
    guard let assist else { return }
    candidates = await assist.candidates()
  }

  /// Fills in what the container list can prove — kind, name, address — and
  /// nothing it can't. **No credential is ever taken from a container**, not
  /// from its environment, not from its template.
  func apply(_ candidate: ServiceCandidate) {
    kind = candidate.kind
    name = candidate.containerName
    urlText = candidate.baseURL.absoluteString
    testResult = nil
  }

  /// One editable custom header. Identified so `ForEach` can address rows the
  /// user is still typing into — a dictionary would reorder under them.
  struct HeaderDraft: Identifiable, Equatable {
    let id = UUID()
    var field: String = ""
    var value: String = ""
  }

  // MARK: - Validation

  /// The same normalisation the connect screen applies to the Unraid address:
  /// an explicit scheme is required, because a bare host produces a relative URL
  /// that fails much later with a confusing error. Deliberately shared rather
  /// than reimplemented — two rules for "what is a valid address" is how the two
  /// screens end up disagreeing about the same typo.
  var normalizedURL: URL? {
    ConnectStore.normalizedURL(from: urlText)
  }

  /// Whether the credentials this kind *requires* are present.
  ///
  /// **Only the API-key kinds require anything.** An *arr cannot answer
  /// without a key, so a blank one is a form error. The download client can:
  /// NZBGet with no `ControlUsername`/`ControlPassword` serves unauthenticated,
  /// which is an ordinary homelab setup. Demanding a username and password
  /// for it would make the service impossible to add, with Test and Save
  /// both dead and nothing on screen explaining why.
  ///
  /// A half-filled pair is deliberately allowed through rather than treated as
  /// blank: it is sent as typed, and the service is the authority on whether it
  /// is enough.
  var hasRequiredCredentials: Bool {
    switch kind.credentialStyle {
    case .apiKey: !apiKey.trimmingCharacters(in: .whitespaces).isEmpty
    case .usernamePassword: true
    }
  }

  var canSubmit: Bool {
    normalizedURL != nil && hasRequiredCredentials
      && !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  /// Why Save is disabled, for the form's footer. `nil` when it isn't.
  var validationMessage: String? {
    if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "Give this service a name." }
    if normalizedURL == nil { return "Include http:// or https:// and the service's address." }
    if !hasRequiredCredentials {
      return "Paste the API key from \(kind.displayName)'s settings."
    }
    return nil
  }

  // MARK: - Actions

  /// Runs the real status check against the details as typed.
  func test() async {
    guard let draft = makeInstance() else { return }
    isTesting = true
    testResult = nil
    defer { isTesting = false }
    testResult = await checker.status(for: draft)
  }

  /// Writes the instance to the keychain directory. Returns it so the caller can
  /// dismiss and refresh; `nil` means the save failed and `saveError` says why.
  @discardableResult
  func save() -> ServiceInstance? {
    guard let draft = makeInstance() else { return nil }
    do {
      let saved = try directory.save(draft)
      saveError = nil
      return saved
    } catch {
      saveError = AppError.wrapping(error)
      return nil
    }
  }

  /// Clears a stale test result. Called by the view when an input changes: a
  /// green "Connected" left over from the previous address is worse than none.
  func inputChanged() {
    testResult = nil
  }

  func addHeader() {
    customHeaders.append(HeaderDraft())
  }

  func removeHeaders(at offsets: IndexSet) {
    customHeaders.remove(atOffsets: offsets)
  }

  // MARK: - Building

  private func makeInstance() -> ServiceInstance? {
    guard let url = normalizedURL, hasRequiredCredentials else { return nil }
    let credentials: ServiceCredentials = switch kind.credentialStyle {
    case .apiKey:
      .apiKey(apiKey.trimmingCharacters(in: .whitespacesAndNewlines))
    case .usernamePassword:
      .usernamePassword(
        username: username.trimmingCharacters(in: .whitespacesAndNewlines), password: password)
    }
    return ServiceInstance(
      // The existing id on an edit — this is a replacement, not a second
      // record — and a fresh one on an add.
      id: editing?.id ?? UUID(),
      kind: kind,
      name: name.trimmingCharacters(in: .whitespacesAndNewlines),
      baseURL: url,
      credentials: credentials,
      customHeaders: headerDictionary,
      // Editing a disabled instance must not silently switch it back on.
      isEnabled: editing?.isEnabled ?? true
    )
  }

  /// Blank rows are dropped rather than saved as an empty header, which some
  /// proxies reject outright.
  private var headerDictionary: [String: String] {
    var headers: [String: String] = [:]
    for draft in customHeaders {
      let field = draft.field.trimmingCharacters(in: .whitespaces)
      guard !field.isEmpty else { continue }
      headers[field] = draft.value
    }
    return headers
  }

  private func clearCredentials() {
    apiKey = ""
    username = ""
    password = ""
  }
}

extension ServiceStatus {
  /// The test button's headline. Distinct copy per outcome is the point: a
  /// rejected key and an unreachable host are fixed on different screens.
  var testHeadline: String {
    switch self {
    case .reachable(let version):
      version.map { "Connected — version \($0)" } ?? "Connected"
    case .unauthorized:
      AppError.unauthorized.message
    case .unreachable(let error):
      error.message
    }
  }

  var testDetail: String? {
    switch self {
    case .reachable: nil
    case .unauthorized: AppError.serviceUnauthorizedRecovery
    case .unreachable(let error): error.serviceRecoverySuggestion
    }
  }
}
