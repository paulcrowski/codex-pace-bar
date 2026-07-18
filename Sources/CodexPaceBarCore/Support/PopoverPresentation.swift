import Foundation

public struct PopoverUsageChartPoint: Identifiable, Equatable, Sendable {
    public let id: String
    public let date: Date
    public let value: Double

    public init(id: String, date: Date, value: Double) {
        self.id = id
        self.date = date
        self.value = value
    }
}

public enum PopoverPresentation {
    public static func percent(_ value: Double) -> String {
        "\(Int(value.rounded()))%"
    }

    public static func paceStatus(snapshot: PaceSnapshot, windowDurationMins: Double?) -> String {
        guard snapshot.state != .onPace else {
            return "On pace"
        }

        let durationHours = (windowDurationMins ?? 0) / 60
        let deltaHours = abs(snapshot.deltaPercentagePoints) / 100 * durationHours

        switch snapshot.state {
        case .abovePace:
            return "Rushing by \(hours(deltaHours))"
        case .belowPace:
            return "Dragging by \(hours(deltaHours))"
        case .onPace, .loading, .error:
            return "On pace"
        }
    }

    public static func hoursToReset(_ resetAt: Date, now: Date) -> String {
        hours(max(0, resetAt.timeIntervalSince(now) / 3600))
    }

    public static func forecastStatus(_ forecast: UsageForecast?, now: Date) -> String? {
        guard let forecast else {
            return nil
        }

        if forecast.willRunOutBeforeReset {
            return "Forecast: may run out in \(hours(forecast.hoursUntilExhaustion(at: now)))"
        }

        return "Forecast: usage should last until reset"
    }

    public static func idealChartPoints(for window: CodexLimitWindow?) -> [PopoverUsageChartPoint] {
        guard let window else {
            return []
        }

        let start = window.resetsAt.addingTimeInterval(-window.windowDurationMins * 60)
        return [
            PopoverUsageChartPoint(id: "ideal-start", date: start, value: 0),
            PopoverUsageChartPoint(id: "ideal-end", date: window.resetsAt, value: 100)
        ]
    }

    public static func forecastChartPoints(latest: UsageSample?, forecast: UsageForecast?) -> [PopoverUsageChartPoint] {
        guard let latest, let forecast else {
            return []
        }

        let end = min(forecast.exhaustionAt, forecast.resetAt)
        let forecastHours = max(0, end.timeIntervalSince(latest.timestamp) / 3600)
        let endValue = min(100, latest.usedPercent + forecast.ratePercentagePointsPerHour * forecastHours)
        return [
            PopoverUsageChartPoint(id: "forecast-start", date: latest.timestamp, value: latest.usedPercent),
            PopoverUsageChartPoint(id: "forecast-end", date: end, value: endValue)
        ]
    }

    private static func hours(_ value: Double) -> String {
        if value < 1, value > 0 {
            return "<1 h"
        }
        return "\(Int(value.rounded(.up))) h"
    }
}
