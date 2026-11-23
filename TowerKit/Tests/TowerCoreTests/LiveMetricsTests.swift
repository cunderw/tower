import Testing
import TowerCore

private let polled = SystemInfo(
  distro: "Unraid OS", release: "7.3.0", bootTimestamp: nil,
  cpuBrand: nil, cpuCores: 8, cpuThreads: 16,
  cpuPercent: 12, memoryPercent: 88,
  memoryUsedBytes: 28_000_000_000, memoryTotalBytes: 32_000_000_000
)

@Test func anEmptyOverlayKeepsEveryPolledValue() {
  #expect(polled.overlaid(with: LiveMetrics()) == polled)
}

@Test func eachUpdateReplacesOnlyItsOwnMetric() {
  var live = LiveMetrics()
  live.apply(.cpu(percent: 47))
  let overlaid = polled.overlaid(with: live)
  #expect(overlaid.cpuPercent == 47)
  #expect(overlaid.memoryPercent == 88)
  #expect(overlaid.memoryUsedBytes == 28_000_000_000)
  #expect(overlaid.cpuCores == 8)
}

// A live percent beside a polled "X of Y" line would disagree with itself,
// so memory's three values move together.
@Test func memoryReplacesPercentUsedAndTotalTogether() {
  var live = LiveMetrics()
  live.apply(.memory(percent: 50, usedBytes: 16_000_000_000, totalBytes: 32_000_000_000))
  let overlaid = polled.overlaid(with: live)
  #expect(overlaid.cpuPercent == 12)
  #expect(overlaid.memoryPercent == 50)
  #expect(overlaid.memoryUsedBytes == 16_000_000_000)
  #expect(overlaid.memoryTotalBytes == 32_000_000_000)
}

@Test func clearingAMetricRestoresItsPolledValue() {
  var live = LiveMetrics()
  live.apply(.cpu(percent: 47))
  live.apply(.memory(percent: 50, usedBytes: 1, totalBytes: 2))
  live.clear(.cpu)
  #expect(live.cpuPercent == nil)
  #expect(live.memory?.percent == 50)
  #expect(polled.overlaid(with: live).cpuPercent == 12)
  live.clear(.memory)
  #expect(live.isEmpty)
}

// The dashboard keeps the CPU temperature itself, so it never lands here.
@Test func aTemperatureUpdateLeavesTheOverlayAlone() {
  var live = LiveMetrics()
  live.apply(.cpuTemperature(TemperatureReading(value: 52, unit: .celsius)))
  #expect(live.isEmpty)
}

@Test func eachUpdateNamesItsMetric() {
  #expect(LiveMetricsUpdate.cpu(percent: 1).metric == .cpu)
  #expect(LiveMetricsUpdate.memory(percent: 1, usedBytes: 1, totalBytes: 1).metric == .memory)
  #expect(LiveMetricsUpdate.cpuTemperature(nil).metric == .cpuTemperature)
}
