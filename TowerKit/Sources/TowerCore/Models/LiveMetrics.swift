import Foundation

/// A source of live system metrics. `TowerData` implements it over the
/// server's GraphQL subscriptions; demo mode and the UI tests supply their own.
///
/// The stream ends when the consumer cancels it, or when the source stops.
/// A thrown error means only that the live values stopped: the caller falls
/// back to the polled values and shows no error.
public protocol MetricsStreaming: Sendable {
  func liveMetrics() -> AsyncThrowingStream<LiveMetricsUpdate, any Error>
}

/// The three metrics a live stream carries.
public enum LiveMetric: Hashable, Sendable, CaseIterable {
  case cpu
  case memory
  case cpuTemperature
}

/// One reading of one metric. The server sends each metric on its own cadence
/// (CPU about every second, memory every 2 s, temperature every 5 s), so an
/// update carries one metric, never a full set.
public enum LiveMetricsUpdate: Equatable, Sendable {
  case cpu(percent: Double)
  case memory(percent: Double, usedBytes: Int64, totalBytes: Int64)
  /// `nil` when the server reports no CPU sensor.
  case cpuTemperature(TemperatureReading?)

  public var metric: LiveMetric {
    switch self {
    case .cpu: .cpu
    case .memory: .memory
    case .cpuTemperature: .cpuTemperature
    }
  }
}

/// A temperature in the unit the server reports. Tower does not convert it.
public struct TemperatureReading: Equatable, Sendable {
  public enum Unit: Equatable, Sendable {
    case celsius
    case fahrenheit
    case kelvin
    case rankine
  }

  public let value: Double
  public let unit: Unit

  public init(value: Double, unit: Unit) {
    self.value = value
    self.unit = unit
  }
}

/// The live values the dashboard shows over its polled snapshot. A `nil`
/// field means "no live value": the polled value shows instead, or for the
/// CPU temperature, which the poll does not read, no row.
public struct LiveMetrics: Equatable, Sendable {
  public struct Memory: Equatable, Sendable {
    public let percent: Double
    public let usedBytes: Int64
    public let totalBytes: Int64
  }

  public private(set) var cpuPercent: Double?
  public private(set) var memory: Memory?
  public private(set) var cpuTemperature: TemperatureReading?

  public init() {}

  public var isEmpty: Bool { self == LiveMetrics() }

  public mutating func apply(_ update: LiveMetricsUpdate) {
    switch update {
    case .cpu(let percent):
      cpuPercent = percent
    case .memory(let percent, let usedBytes, let totalBytes):
      memory = Memory(percent: percent, usedBytes: usedBytes, totalBytes: totalBytes)
    case .cpuTemperature(let reading):
      cpuTemperature = reading
    }
  }

  public mutating func clear(_ metric: LiveMetric) {
    switch metric {
    case .cpu: cpuPercent = nil
    case .memory: memory = nil
    case .cpuTemperature: cpuTemperature = nil
    }
  }
}

extension SystemInfo {
  /// This reading with each live value in place of its polled value. A field
  /// with no live value keeps the polled value.
  ///
  /// Memory replaces its percent, used and total together. A live percent
  /// beside a polled "X of Y" line would disagree with itself.
  public func overlaid(with live: LiveMetrics) -> SystemInfo {
    SystemInfo(
      distro: distro, release: release, bootTimestamp: bootTimestamp,
      cpuBrand: cpuBrand, cpuCores: cpuCores, cpuThreads: cpuThreads,
      cpuPercent: live.cpuPercent ?? cpuPercent,
      memoryPercent: live.memory?.percent ?? memoryPercent,
      memoryUsedBytes: live.memory?.usedBytes ?? memoryUsedBytes,
      memoryTotalBytes: live.memory?.totalBytes ?? memoryTotalBytes
    )
  }
}
