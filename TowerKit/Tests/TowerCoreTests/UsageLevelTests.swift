import Testing
import TowerCore

struct UsageLevelTests {
  @Test func capacityBecomesWarningAtEightyFivePercent() {
    #expect(UsageLevel.forFraction(0.5) == .normal)
    #expect(UsageLevel.forFraction(0.849) == .normal)
    #expect(UsageLevel.forFraction(0.85) == .warning)
    #expect(UsageLevel.forFraction(0.94) == .warning)
    #expect(UsageLevel.forFraction(0.95) == .critical)
    #expect(UsageLevel.forFraction(1.0) == .critical)
  }

  @Test func temperatureBecomesWarningAtFortyFive() {
    #expect(UsageLevel.forTemperature(30) == .normal)
    #expect(UsageLevel.forTemperature(44) == .normal)
    #expect(UsageLevel.forTemperature(45) == .warning)
    #expect(UsageLevel.forTemperature(54) == .warning)
    #expect(UsageLevel.forTemperature(55) == .critical)
  }

  /// A disk that reports no temperature is not a cool disk — it is an
  /// unknown one, and must not render in the "healthy" colour.
  @Test func missingTemperatureIsUnknownNotNormal() {
    #expect(UsageLevel.forTemperature(nil) == .unknown)
  }
}
