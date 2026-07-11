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

public struct UsageForecast: Equatable, Sendable {
    public let ratePercentagePointsPerHour: Double
    public let exhaustionAt: Date
    public let resetAt: Date

    public init(ratePercentagePointsPerHour: Double, exhaustionAt: Date, resetAt: Date) {
        self.ratePercentagePointsPerHour = ratePercentagePointsPerHour
        self.exhaustionAt = exhaustionAt
        self.resetAt = resetAt
    }

    public var willRunOutBeforeReset: Bool {
        exhaustionAt < resetAt
    }

    public func hoursUntilExhaustion(at date: Date) -> Double {
        max(0, exhaustionAt.timeIntervalSince(date) / 3600)
    }
}
