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

        #expect(PopoverPresentation.paceStatus(snapshot: snapshot, windowDurationMins: 120) == "Rushing by <1 h")
    }

    @Test
    func formatsResetAndForecastStatusesAtProvidedTime() {
        let now = Date(timeIntervalSince1970: 5_000)
        let resetAt = now.addingTimeInterval(90 * 60)
        #expect(PopoverPresentation.hoursToReset(resetAt, now: now) == "2 h")

        let forecast = UsageForecast(
            ratePercentagePointsPerHour: 10,
            exhaustionAt: now.addingTimeInterval(30 * 60),
            resetAt: resetAt
        )
        #expect(PopoverPresentation.forecastStatus(forecast, now: now) == "Forecast: may run out in <1 h")
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
        let forecast = UsageForecast(ratePercentagePointsPerHour: 20, exhaustionAt: Date(timeIntervalSince1970: 10_000), resetAt: resetAt)
        let points = PopoverPresentation.forecastChartPoints(latest: latest, forecast: forecast)
        #expect(points.count == 2)
        #expect(points.last?.value == 45.55555555555556)
    }
}
