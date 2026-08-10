import Foundation

public struct UsageSample: Codable, Equatable, Sendable {
    public let timestamp: Date
    public let usedPercent: Double
    public let resetAt: Date
    public let limitId: String

    public init(timestamp: Date, usedPercent: Double, resetAt: Date, limitId: String) {
        self.timestamp = timestamp
        self.usedPercent = clamp(usedPercent, 0, 100)
        self.resetAt = resetAt
        self.limitId = limitId
    }
}

public enum UsageForecastConfidence: String, Equatable, Sendable {
    case low
    case medium
    case high
}

public struct UsageForecastPoint: Equatable, Sendable {
    public let timestamp: Date
    public let usedPercent: Double

    public init(timestamp: Date, usedPercent: Double) {
        self.timestamp = timestamp
        self.usedPercent = clamp(usedPercent, 0, 100)
    }
}

public struct UsageForecast: Equatable, Sendable {
    public let ratePercentagePointsPerHour: Double
    public let exhaustionAt: Date
    public let resetAt: Date
    public let confidence: UsageForecastConfidence
    public let projection: [UsageForecastPoint]

    public init(
        ratePercentagePointsPerHour: Double,
        exhaustionAt: Date,
        resetAt: Date,
        confidence: UsageForecastConfidence = .medium,
        projection: [UsageForecastPoint] = []
    ) {
        self.ratePercentagePointsPerHour = ratePercentagePointsPerHour
        self.exhaustionAt = exhaustionAt
        self.resetAt = resetAt
        self.confidence = confidence
        self.projection = projection
    }

    public var willRunOutBeforeReset: Bool {
        exhaustionAt < resetAt
    }

    public func hoursUntilExhaustion(at date: Date) -> Double {
        max(0, exhaustionAt.timeIntervalSince(date) / 3600)
    }
}
