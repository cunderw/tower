import Apollo
import Foundation
import TowerAPI
import TowerCore

/// Reads Unraid's VM list and runs the seven `VmMutations` actions. Apollo's
/// generated types never escape this module — `LiveVMRepository` is the
/// boundary where `VMsQuery.Data` becomes a `TowerCore` `VMInventory`.
/// Follows `LiveDockerRepository`'s shape, with one deliberate difference in
/// the action methods (see below).
public protocol VMRepositoryProtocol: Sendable {
  func domains() async throws -> VMInventory

  /// One method per `VmMutations` action, all returning `Void` rather than a
  /// state update.
  ///
  /// This is where VMs genuinely differ from Docker: `DockerMutations`
  /// actions return `id`/`state`/`status`, so `DockerRepositoryProtocol`
  /// hands back a `ContainerStateUpdate` its caller merges into the row it
  /// already has. Every `VmMutations` action returns a bare `Boolean!`. There
  /// is nothing to merge, and inventing a `VMDomain` from a `true` would be
  /// fabricating the state the caller actually needs — libvirt transitions
  /// are asynchronous, so the VM may well still report its old state for a
  /// moment. Callers re-fetch `domains()` instead; see
  /// `VMStore.perform(_:on:)`.
  ///
  /// A `false` response throws `AppError.actionRefused`. It is not an error
  /// in the transport or GraphQL sense — the request succeeded and the server
  /// said no — but it absolutely is a failure from the caller's point of
  /// view, and treating it as success would leave a user watching a row that
  /// never changes with no explanation.
  func start(id: String) async throws
  func stop(id: String) async throws
  func forceStop(id: String) async throws
  func pause(id: String) async throws
  func resume(id: String) async throws
  func reboot(id: String) async throws
  func reset(id: String) async throws
}

public struct LiveVMRepository: VMRepositoryProtocol {
  private let provider: ApolloClientProvider

  public init(provider: ApolloClientProvider) {
    self.provider = provider
  }

  public func domains() async throws -> VMInventory {
    let response = try await provider.client.fetch(
      query: VMsQuery(),
      cachePolicy: .networkOnly
    )
    if let errors = response.errors, !errors.isEmpty {
      throw AppError.from(graphQLErrors: errors)
    }
    guard let data = response.data else {
      throw AppError.decoding("Empty response for VMs.")
    }
    // `?.map` and not `??  []`: a nil `domains` must stay nil all the way to
    // the UI. See `VMInventory`'s doc comment — collapsing it to an empty
    // array here would tell a user whose VM manager is off that they have no VMs.
    //
    // Sorted by display name so list order is stable across refreshes; the
    // server does not guarantee `domains` order, and a list that reshuffles
    // under a 30-second poll is unusable.
    return VMInventory(
      domains: data.vms.domains?
        .map(VMDomain.init(from:))
        .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    )
  }

  public func start(id: String) async throws {
    try await performAction(StartVMMutation(id: id), named: "start") { $0.vm.start }
  }

  public func stop(id: String) async throws {
    try await performAction(StopVMMutation(id: id), named: "stop") { $0.vm.stop }
  }

  public func forceStop(id: String) async throws {
    try await performAction(ForceStopVMMutation(id: id), named: "force stop") { $0.vm.forceStop }
  }

  public func pause(id: String) async throws {
    try await performAction(PauseVMMutation(id: id), named: "pause") { $0.vm.pause }
  }

  public func resume(id: String) async throws {
    try await performAction(ResumeVMMutation(id: id), named: "resume") { $0.vm.resume }
  }

  public func reboot(id: String) async throws {
    try await performAction(RebootVMMutation(id: id), named: "reboot") { $0.vm.reboot }
  }

  public func reset(id: String) async throws {
    try await performAction(ResetVMMutation(id: id), named: "reset") { $0.vm.reset }
  }

  /// Shared body for all seven actions: Apollo generates a distinct nominal
  /// `Data` type per mutation even though every one of them is a single
  /// `Bool` in the same position, so `extract` picks this call's own field
  /// out of its own `Data` (the same reason `LiveDockerRepository
  /// .performAction(_:extract:)` takes a closure).
  ///
  /// No `DockerActionFields`-style protocol is needed here because the
  /// extracted value is a plain `Bool` rather than a set of generated types.
  ///
  /// `actionName` exists only to build the refusal message. It is a verb
  /// phrase in lower case ("force stop"), so the sentence reads as a sentence
  /// — the message goes straight to the user through `AppError.message`.
  private func performAction<Mutation: GraphQLMutation>(
    _ mutation: Mutation,
    named actionName: String,
    extract: (Mutation.Data) -> Bool
  ) async throws where Mutation.ResponseFormat == SingleResponseFormat {
    let response = try await provider.client.perform(mutation: mutation)
    if let errors = response.errors, !errors.isEmpty {
      throw AppError.from(graphQLErrors: errors)
    }
    guard let data = response.data else {
      throw AppError.decoding("Empty response for \(Mutation.operationName).")
    }
    guard extract(data) else {
      throw AppError.actionRefused("Unraid didn't \(actionName) this VM.")
    }
  }
}

extension VMDomain {
  /// Maps Apollo's generated `VMsQuery.Data.Vms.Domain` into the domain
  /// model.
  ///
  /// Deliberately **not** public: its parameter is an Apollo-generated type,
  /// and a public signature mentioning one would let callers build a domain
  /// model straight from hand-rolled GraphQL data, skipping the error and
  /// nil-data guards in `domains()` that are supposed to be the only way in.
  ///
  /// An empty `name` maps to `nil` rather than through: `""` is not a name
  /// the server *has*, it is the absence of one, and `displayName`'s UUID
  /// fallback is the right answer for both. Doing this here rather than in
  /// the model keeps "the wire sends empty strings for absent values" as a
  /// mapping-layer fact.
  init(from domain: VMsQuery.Data.Vms.Domain) {
    self.init(
      id: domain.id,
      name: domain.name?.isEmpty == true ? nil : domain.name,
      state: VMState(rawValue: domain.state.rawValue)
    )
  }
}
