import Apollo
import Foundation
import TowerAPI
import TowerCore

/// Reads Unraid's Docker container list. Apollo's generated types never
/// escape this module — `LiveDockerRepository` is the boundary where
/// `DockerContainersQuery.Data` gets mapped into the `TowerCore` domain
/// model. Follows `LiveSystemRepository`'s exact shape.
public protocol DockerRepositoryProtocol: Sendable {
  func containers() async throws -> [Container]

  /// One method per `DockerMutations` action Tower exposes —
  /// each returns only the `ContainerStateUpdate` its mutation's selection
  /// set actually asked for (`id`/`state`/`status`), not a full `Container`.
  /// See `ContainerStateUpdate`'s doc comment for why: fabricating the rest
  /// of `Container`'s shape from a response that never reported it would be
  /// worse than not claiming to know it. Callers merge the update into their
  /// own cached list via `Container.applyingStateUpdate(_:)`.
  func start(id: String) async throws -> ContainerStateUpdate
  func stop(id: String) async throws -> ContainerStateUpdate
  func restart(id: String) async throws -> ContainerStateUpdate
  func pause(id: String) async throws -> ContainerStateUpdate
  func unpause(id: String) async throws -> ContainerStateUpdate

  /// Pulls the container's latest image and recreates the container. Returns
  /// the recreated container, whose ID is **not** `id`: Docker gives a
  /// recreated container a new ID, so a caller that keys anything by the old
  /// one has to re-key it. Throws `AppError.stillRunning` when the client
  /// stops waiting before the server answers. The server keeps going, so the
  /// update can still finish.
  func update(id: String) async throws -> Container

  /// `tail` and `since` mirror the `DockerLogs` operation's own optional
  /// arguments — `nil` for either omits it from the request (Apollo's
  /// `GraphQLNullable.none`, not an explicit `null`). `tail` is a maximum,
  /// not an exact count: asking Unraid for 3 can return 2. See
  /// `ContainerLogs`'s doc comment for why `since` isn't what
  /// `ContainerLogsStore.loadMore()` uses to reach further into history.
  func logs(id: String, tail: Int?, since: String?) async throws -> ContainerLogs
}

public struct LiveDockerRepository: DockerRepositoryProtocol {
  /// How long `update(id:)` waits for an answer. `updateContainer` answers
  /// only after the image pull and the recreate finish, and sends nothing
  /// while it works, so the session's 60 s idle timeout would end a slow pull
  /// that is still going well. Ten minutes covers a large image on a slow
  /// line. Past it, `update(id:)` reports the update as still running.
  public static let defaultUpdateTimeout: TimeInterval = 600

  private let provider: ApolloClientProvider
  private let updateTimeout: TimeInterval

  /// - Parameter updateTimeout: How long `update(id:)` waits. A test passes a
  ///   short one to reach the timeout path.
  public init(provider: ApolloClientProvider, updateTimeout: TimeInterval = defaultUpdateTimeout) {
    self.provider = provider
    self.updateTimeout = updateTimeout
  }

  public func containers() async throws -> [Container] {
    let response = try await provider.client.fetch(
      query: DockerContainersQuery(),
      cachePolicy: .networkOnly
    )
    if let errors = response.errors, !errors.isEmpty {
      // With the Docker service off, the `containers` resolver itself throws
      // ("Docker socket unavailable."), so its error sits at exactly this
      // path. Matched exactly, not by the `docker` prefix, which would also
      // take in a failure of one container's field (`docker.containers.0.name`)
      // and every mutation's `docker.start`, none of which mean the service is
      // off. An auth error still wins, as `from(graphQLErrors:)` says.
      if !errors.contains(where: \.isAuthFailure),
         errors.contains(where: { $0.path == [.field("docker"), .field("containers")] }) {
        throw AppError.serviceUnavailable("Docker")
      }
      throw AppError.from(graphQLErrors: errors)
    }
    guard let data = response.data else {
      throw AppError.decoding("Empty response for DockerContainers.")
    }
    // `docker` is nullable from API 4.37 (issue #21). A null one arrives with
    // an error, which the check above has already thrown.
    guard let docker = data.docker else {
      throw AppError.decoding("No docker in DockerContainers response.")
    }
    // Sort by display name so list order is stable across refreshes — the
    // server does not guarantee `containers` order.
    return docker.containers
      .map { Container(from: $0.fragments.dockerContainerFields) }
      .sorted { $0.displayName < $1.displayName }
  }

  public func start(id: String) async throws -> ContainerStateUpdate {
    try await performAction(StartContainerMutation(id: id)) { $0.docker.start }
  }

  public func stop(id: String) async throws -> ContainerStateUpdate {
    try await performAction(StopContainerMutation(id: id)) { $0.docker.stop }
  }

  public func restart(id: String) async throws -> ContainerStateUpdate {
    try await performAction(RestartContainerMutation(id: id)) { $0.docker.restart }
  }

  public func pause(id: String) async throws -> ContainerStateUpdate {
    try await performAction(PauseContainerMutation(id: id)) { $0.docker.pause }
  }

  public func unpause(id: String) async throws -> ContainerStateUpdate {
    try await performAction(UnpauseContainerMutation(id: id)) { $0.docker.unpause }
  }

  /// One `updateContainer` request with its own timeout (see
  /// `defaultUpdateTimeout`). A request timeout overrides the session's idle
  /// timeout in both directions, so the other requests keep 60 s.
  ///
  /// `URLError.timedOut` becomes `AppError.stillRunning` here, not
  /// `.serverUnreachable` as `AppError.from(transport:)` maps it: the server
  /// answered the request by starting the update, and it keeps going after
  /// the client stops waiting.
  public func update(id: String) async throws -> Container {
    let response: GraphQLResponse<UpdateContainerMutation>
    do {
      response = try await provider.client.perform(
        mutation: UpdateContainerMutation(id: id),
        requestConfiguration: RequestConfiguration(requestTimeout: updateTimeout)
      )
    } catch let error as URLError where error.code == .timedOut {
      throw AppError.stillRunning("The update is still running on the server.")
    }
    if let errors = response.errors, !errors.isEmpty {
      throw AppError.from(graphQLErrors: errors)
    }
    guard let data = response.data else {
      throw AppError.decoding("Empty response for UpdateContainer.")
    }
    return Container(from: data.docker.updateContainer.fragments.dockerContainerFields)
  }

  /// Same `.networkOnly`/errors-check/nil-data-guard shape as `containers()`
  /// above — logs are never worth serving stale from cache, and a
  /// server-reported GraphQL error must not be swallowed as "empty logs".
  ///
  /// `tail`/`since` convert from plain `Int?`/`String?` to Apollo's
  /// `GraphQLNullable` here, at the boundary, rather than pushing
  /// `GraphQLNullable` up into `DockerRepositoryProtocol`'s signature — that
  /// type is `ApolloAPI`, and no public `TowerData` declaration may mention
  /// an Apollo type. `Int32(exactly:)` rather than a trapping `Int32.init`:
  /// every real call site passes a small page-size multiple (200, 400, …),
  /// but a `tail` value this repository doesn't control landing outside
  /// `Int32`'s range should silently omit the argument (an unbounded `tail`
  /// is what "no maximum was understood" degrades to), not crash the app.
  public func logs(id: String, tail: Int?, since: String?) async throws -> ContainerLogs {
    let response = try await provider.client.fetch(
      query: DockerLogsQuery(
        id: id,
        tail: tail.flatMap { Int32(exactly: $0) } ?? .none,
        since: since ?? .none
      ),
      cachePolicy: .networkOnly
    )
    if let errors = response.errors, !errors.isEmpty {
      throw AppError.from(graphQLErrors: errors)
    }
    guard let data = response.data else {
      throw AppError.decoding("Empty response for DockerLogs.")
    }
    guard let docker = data.docker else {
      throw AppError.decoding("No docker in DockerLogs response.")
    }
    return ContainerLogs(from: docker.logs)
  }

  /// Shared body for `start`/`stop`/`restart`/`pause`/`unpause`: Apollo
  /// generates a distinct nominal `Data`/result type per mutation even
  /// though `StartContainerMutation.Data.Docker.Start`,
  /// `...Docker.Stop`, etc. are structurally identical (see
  /// `DockerActionFields` below and `SystemRepository.swift`'s
  /// `DashboardDiskFields` for the same shape-vs-nominal-type situation).
  /// `extract` picks the one field this call's mutation actually selected
  /// out of its own `Data`; everything else — errors, empty-data guard,
  /// mapping — is identical across all five actions.
  private func performAction<Mutation: GraphQLMutation, Fields: DockerActionFields>(
    _ mutation: Mutation,
    extract: (Mutation.Data) -> Fields
  ) async throws -> ContainerStateUpdate where Mutation.ResponseFormat == SingleResponseFormat {
    let response = try await provider.client.perform(mutation: mutation)
    if let errors = response.errors, !errors.isEmpty {
      throw AppError.from(graphQLErrors: errors)
    }
    guard let data = response.data else {
      throw AppError.decoding("Empty response for \(Mutation.operationName).")
    }
    return ContainerStateUpdate(from: extract(data))
  }
}

/// Structural shape shared by every `DockerMutations` action's selection
/// set (`id`/`state`/`status`) — see `performAction(_:extract:)` above for
/// why one initializer needs this rather than five copies.
///
/// Deliberately **not** public: this mentions Apollo-generated types
/// (`TowerAPI.PrefixedID`, `GraphQLEnum<TowerAPI.ContainerState>`), which
/// must never leak past this module's boundary.
private protocol DockerActionFields {
  var id: TowerAPI.PrefixedID { get }
  var state: GraphQLEnum<TowerAPI.ContainerState> { get }
  var status: String { get }
}

extension StartContainerMutation.Data.Docker.Start: DockerActionFields {}
extension StopContainerMutation.Data.Docker.Stop: DockerActionFields {}
extension RestartContainerMutation.Data.Docker.Restart: DockerActionFields {}
extension PauseContainerMutation.Data.Docker.Pause: DockerActionFields {}
extension UnpauseContainerMutation.Data.Docker.Unpause: DockerActionFields {}

extension ContainerStateUpdate {
  /// Deliberately **not** public — see `DockerActionFields` above.
  fileprivate init(from fields: some DockerActionFields) {
    self.init(id: fields.id, state: ContainerState(rawValue: fields.state.rawValue), status: fields.status)
  }
}

extension Container {
  /// Maps Apollo's generated `DockerContainerFields` fragment into the
  /// domain model. `DockerContainers` and `UpdateContainer` both select it.
  ///
  /// Deliberately **not** public: its parameter is an Apollo-generated type,
  /// and a public signature mentioning one would let callers construct a
  /// domain model straight from hand-rolled GraphQL data, skipping the
  /// error and nil-data guards in `containers()` that are supposed to be the
  /// only way in.
  init(from container: DockerContainerFields) {
    self.init(
      id: container.id,
      names: container.names,
      image: container.image,
      state: ContainerState(rawValue: container.state.rawValue),
      status: container.status,
      autoStart: container.autoStart,
      isUpdateAvailable: container.isUpdateAvailable,
      isOrphaned: container.isOrphaned,
      // **All five through `OpenableURL`.** Four of these are rendered
      // as `Link`s on the container row and detail screen. `iconURL` is kept
      // for parity, but no view shows it. `URL(string:)` accepts a scheme-less
      // address and returns a URL a `Link` cannot open, so the link does
      // nothing when tapped. A container template with a malformed `WebUI` is
      // exactly the kind of thing a homelab has.
      webUiURL: OpenableURL.from(container.webUiUrl),
      iconURL: OpenableURL.from(container.iconUrl),
      projectURL: OpenableURL.from(container.projectUrl),
      supportURL: OpenableURL.from(container.supportUrl),
      registryURL: OpenableURL.from(container.registryUrl),
      templatePath: container.templatePath,
      networkMode: container.hostConfig?.networkMode,
      ports: container.ports.map(ContainerPort.init(from:))
    )
  }
}

extension ContainerPort {
  /// Deliberately **not** public — see `Container.init(from:)` above.
  init(from port: DockerContainerFields.Port) {
    self.init(
      ip: port.ip,
      // `TowerAPI.Port` is a `String` custom scalar (unmapped in
      // apollo-codegen-config.json, same as `DateTime`), not `Int` — despite
      // the schema documenting it as "a valid TCP port within 0-65535".
      // Converting here, rather than carrying the wire string through to the
      // domain model, keeps `ContainerPort` numeric for formatting/sorting;
      // an unparseable value degrades to `nil` rather than crashing.
      privatePort: port.privatePort.flatMap(Int.init),
      publicPort: port.publicPort.flatMap(Int.init),
      type: port.type.rawValue
    )
  }
}

extension ContainerLogs {
  /// Deliberately **not** public — its parameter is an Apollo-generated
  /// type; see `Container.init(from:)` above for why that must stay this
  /// module's problem, not a caller's.
  init(from logs: DockerLogsQuery.Data.Docker.Logs) {
    self.init(
      containerId: logs.containerId,
      lines: logs.lines.map(ContainerLogLine.init(from:)),
      cursor: logs.cursor
    )
  }
}

extension ContainerLogLine {
  /// Deliberately **not** public — see `Container.init(from:)` above.
  ///
  /// `line.timestamp` is a non-null `DateTime` on the wire, but that's a
  /// promise about presence, not about being parseable — `Formatters
  /// .parseTimestamp` degrades an unparseable string to `nil` rather than
  /// throwing, and this initializer always keeps `message` regardless of
  /// which way that goes. Never drop a line for a bad timestamp.
  init(from line: DockerLogsQuery.Data.Docker.Logs.Line) {
    self.init(timestamp: Formatters.parseTimestamp(line.timestamp), message: line.message)
  }
}
