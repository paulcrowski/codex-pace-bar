import CodexPaceBarCore
import Foundation
import Testing

@Suite
struct PopoverPresentationTests {
    @Test
    func formatsPercentAndPaceStatus() {
        #expect(PopoverPresentation.percent(49.6) == "50%")

        let snapshot = PaceSnapshot(
            actualUsedPercent: 60,
            remainingPercent: 40,
            idealUsedPercent: 40,
            deltaPercentagePoints: 20,
            usedFraction: 0.6,
            elapsedFraction: 0.4,
            resetAt: Date(timeIntervalSince1970: 10_000),
            state: .abovePace,
            fetchedAt: Date(timeIntervalSince1970: 5_000),
            isStale: false
        )

        #expect(PopoverPresentation.paceStatus(snapshot: snapshot, windowDurationMins: 120) == "High usage pace · <1 h ahead")
    }

    @Test
    func formatsResetAndForecastStatusesAtProvidedTime() {
        let now = Date(timeIntervalSince1970: 5_000)
        let resetAt = now.addingTimeInterval(90 * 60)
        #expect(PopoverPresentation.hoursToReset(resetAt, now: now) == "2 h")
        #expect(PopoverPresentation.forecastLabel == "Adaptive forecast")

        let forecast = UsageForecast(
            ratePercentagePointsPerHour: 10,
            exhaustionAt: now.addingTimeInterval(30 * 60),
            resetAt: resetAt
        )
        #expect(PopoverPresentation.forecastStatus(forecast, now: now) == "Adaptive forecast: may run out in <1 h")
    }

    @Test
    func labelsLowConfidenceExhaustionWarningDuringWarmup() {
        let now = Date(timeIntervalSince1970: 5_000)
        let forecast = UsageForecast(
            ratePercentagePointsPerHour: 10,
            exhaustionAt: now.addingTimeInterval(30 * 60),
            resetAt: now.addingTimeInterval(90 * 60),
            confidence: .low
        )

        #expect(PopoverPresentation.forecastStatus(forecast, now: now) == "Adaptive forecast: may run out in <1 h · low confidence")
    }

    @Test
    func derivesIdealAndForecastChartPoints() {
        let resetAt = Date(timeIntervalSince1970: 10_000)
        let window = CodexLimitWindow(limitId: "codex", source: "test", usedPercent: 40, windowDurationMins: 100, resetsAt: resetAt)
        let ideal = PopoverPresentation.idealChartPoints(for: window)
        #expect(ideal.count == 2)
        #expect(ideal.first?.value == 0)
        #expect(ideal.last?.value == 100)

        let latest = UsageSample(timestamp: Date(timeIntervalSince1970: 9_000), usedPercent: 40, resetAt: resetAt, limitId: "codex")
        let forecast = UsageForecast(
            ratePercentagePointsPerHour: 20,
            exhaustionAt: Date(timeIntervalSince1970: 10_000),
            resetAt: resetAt,
            projection: [
                UsageForecastPoint(timestamp: latest.timestamp, usedPercent: 40),
                UsageForecastPoint(timestamp: Date(timeIntervalSince1970: 9_500), usedPercent: 40),
                UsageForecastPoint(timestamp: resetAt, usedPercent: 45.55555555555556)
            ]
        )
        let points = PopoverPresentation.forecastChartPoints(latest: latest, forecast: forecast)
        #expect(points.count == 3)
        #expect(points[1].value == 40)
        #expect(points.last?.value == 45.55555555555556)
    }
}
