import ApolloTestSupport
import Testing
@testable import TowerAPI
import TowerAPITestMocks
@testable import TowerData
import TowerCore

// Exercises `ContainerLogs.init(from:)`/`ContainerLogLine.init(from:)`, the
// Apollo → domain mapping behind `LiveDockerRepository.logs(id:tail:since:)`.
// See `DashboardMappingTests.swift` for the canonical writeup of the Apollo
// `Mock<O>` crash this file's helpers guard against: `Docker
// .logs` is an entity-typed field, so every `Mock<Docker>` built below
// passes it explicitly — never left to its declared `Mock<DockerContainerLogs
// >()` default.

private func emptyInfo() -> Mock<TowerAPITestMocks.Info> {
  Mock<TowerAPITestMocks.Info>(
    cpu: Mock<TowerAPITestMocks.InfoCpu>(),
    os: Mock<TowerAPITestMocks.InfoOs>()
  )
}

private func emptyMetrics() -> Mock<TowerAPITestMocks.Metrics> {
  Mock<TowerAPITestMocks.Metrics>()
}

private func emptyVms() -> Mock<TowerAPITestMocks.Vms> {
  Mock<TowerAPITestMocks.Vms>(domains: [])
}

private func zeroCapacity() -> Mock<TowerAPITestMocks.ArrayCapacity> {
  Mock<TowerAPITestMocks.ArrayCapacity>(
    kilobytes: Mock<TowerAPITestMocks.Capacity>(free: "0", total: "0", used: "0")
  )
}

private func emptyArray() -> Mock<TowerAPITestMocks.UnraidArray> {
  Mock<TowerAPITestMocks.UnraidArray>(
    capacity: zeroCapacity(),
    parityCheckStatus: Mock<TowerAPITestMocks.ParityCheck>(status: .case(.neverRun)),
    state: .case(.started)
  )
}

/// Assembles the full `Query` mock from already-explicit pieces — only
/// `docker.logs` varies test to test, since this query selects nothing else.
private func makeQuery(logs: Mock<TowerAPITestMocks.DockerContainerLogs>) -> Mock<TowerAPITestMocks.Query> {
  Mock<TowerAPITestMocks.Query>(
    array: emptyArray(),
    docker: Mock<TowerAPITestMocks.Docker>(containers: [], logs: logs),
    info: emptyInfo(), metrics: emptyMetrics(), shares: [], vms: emptyVms()
  )
}

@Test func mapsTimestampAndMessage() async throws {
  let mock = makeQuery(logs: Mock<TowerAPITestMocks.DockerContainerLogs>(
    containerId: "1", cursor: "2026-07-29T19:00:08.192Z",
    lines: [
      Mock<TowerAPITestMocks.DockerContainerLogLine>(message: "hello", timestamp: "2026-07-29T18:00:08.828Z"),
    ]
  ))

  let data = await DockerLogsQuery.Data.from(mock)
  let logs = ContainerLogs(from: data.docker.logs)

  #expect(logs.containerId == "1")
  #expect(logs.cursor == "2026-07-29T19:00:08.192Z")
  let line = try #require(logs.lines.first)
  #expect(line.message == "hello")
  #expect(line.timestamp == Formatters.parseTimestamp("2026-07-29T18:00:08.828Z"))
}

/// The central rule of log mapping: a line whose timestamp fails to parse must
/// still render — the message is the payload, the timestamp is decoration.
/// Never drop a log line because its metadata was unparseable.
@Test func unparseableTimestampStillRendersMessage() async throws {
  let mock = makeQuery(logs: Mock<TowerAPITestMocks.DockerContainerLogs>(
    containerId: "1", cursor: nil,
    lines: [
      Mock<TowerAPITestMocks.DockerContainerLogLine>(message: "still here", timestamp: "not-a-timestamp"),
    ]
  ))

  let data = await DockerLogsQuery.Data.from(mock)
  let logs = ContainerLogs(from: data.docker.logs)

  let line = try #require(logs.lines.first)
  #expect(line.timestamp == nil)
  #expect(line.message == "still here")
}

@Test func cursorIsNilWhenServerOmitsIt() async throws {
  let mock = makeQuery(logs: Mock<TowerAPITestMocks.DockerContainerLogs>(
    containerId: "1", cursor: nil, lines: []
  ))

  let data = await DockerLogsQuery.Data.from(mock)
  let logs = ContainerLogs(from: data.docker.logs)

  #expect(logs.cursor == nil)
}

/// Empty logs are a real state, not an error — the mapping layer must
/// produce a valid, empty `lines` array rather than something the repository
/// or store has to special-case.
@Test func emptyLinesMapsToEmptyArray() async throws {
  let mock = makeQuery(logs: Mock<TowerAPITestMocks.DockerContainerLogs>(
    containerId: "1", cursor: nil, lines: []
  ))

  let data = await DockerLogsQuery.Data.from(mock)
  let logs = ContainerLogs(from: data.docker.logs)

  #expect(logs.lines.isEmpty)
}

@Test func mapsMultipleLinesPreservingOrder() async throws {
  let mock = makeQuery(logs: Mock<TowerAPITestMocks.DockerContainerLogs>(
    containerId: "1", cursor: nil,
    lines: [
      Mock<TowerAPITestMocks.DockerContainerLogLine>(message: "first", timestamp: "2026-07-29T18:00:00Z"),
      Mock<TowerAPITestMocks.DockerContainerLogLine>(message: "second", timestamp: "2026-07-29T18:00:01Z"),
    ]
  ))

  let data = await DockerLogsQuery.Data.from(mock)
  let logs = ContainerLogs(from: data.docker.logs)

  #expect(logs.lines.map(\.message) == ["first", "second"])
}
