import Foundation

public struct CodexDurationDistributionStats: Equatable, Sendable {
    public let sampleCount: Int
    public let mean: TimeInterval
    public let standardDeviation: TimeInterval
    public let median: TimeInterval
    public let p20: TimeInterval
    public let p50: TimeInterval
    public let p80: TimeInterval
    public let p85: TimeInterval
    public let p90: TimeInterval
    public let coefficientOfVariation: Double
    public let skewness: Double
    public let logMean: Double?
    public let logStandardDeviation: Double?

    public init(
        sampleCount: Int,
        mean: TimeInterval,
        standardDeviation: TimeInterval,
        median: TimeInterval,
        p20: TimeInterval,
        p50: TimeInterval,
        p80: TimeInterval,
        p85: TimeInterval,
        p90: TimeInterval,
        coefficientOfVariation: Double,
        skewness: Double,
        logMean: Double?,
        logStandardDeviation: Double?
    ) {
        self.sampleCount = sampleCount
        self.mean = mean
        self.standardDeviation = standardDeviation
        self.median = median
        self.p20 = p20
        self.p50 = p50
        self.p80 = p80
        self.p85 = p85
        self.p90 = p90
        self.coefficientOfVariation = coefficientOfVariation
        self.skewness = skewness
        self.logMean = logMean
        self.logStandardDeviation = logStandardDeviation
    }
}

/// Walk-forward quality metrics for forecasts that have since received an
/// actual completion outcome.  These metrics are deliberately descriptive:
/// they never change a user's estimate by themselves, but make calibration
/// measurable for each user's own history.
public struct CodexForecastCalibrationReport: Equatable, Sendable {
    public let sampleCount: Int
    public let medianAbsoluteError: TimeInterval?
    public let p85Coverage: Double?
    public let safeAwayCoverage: Double?
    public let probabilityBrierScore: Double?

    public init(
        sampleCount: Int,
        medianAbsoluteError: TimeInterval?,
        p85Coverage: Double?,
        safeAwayCoverage: Double?,
        probabilityBrierScore: Double?
    ) {
        self.sampleCount = max(0, sampleCount)
        self.medianAbsoluteError = medianAbsoluteError
        self.p85Coverage = p85Coverage
        self.safeAwayCoverage = safeAwayCoverage
        self.probabilityBrierScore = probabilityBrierScore
    }
}

public struct CodexDurationDistributionModel: Sendable {
    public let kind: CodexTaskForecastModel
    public let values: [TimeInterval]
    public let stats: CodexDurationDistributionStats

    public init(kind: CodexTaskForecastModel, values: [TimeInterval], stats: CodexDurationDistributionStats) {
        self.kind = kind
        self.values = values.sorted()
        self.stats = stats
    }

    public func cdf(_ value: TimeInterval) -> Double {
        guard value.isFinite, value > 0 else { return 0 }
        switch kind {
        case .logNormal:
            guard let mean = stats.logMean,
                  let standardDeviation = stats.logStandardDeviation,
                  standardDeviation > 0
            else { return empiricalCDF(value) }
            return codexNormalCDF((log(value) - mean) / standardDeviation)
        default:
            return empiricalCDF(value)
        }
    }

    public func quantile(_ probability: Double) -> TimeInterval {
        let p = min(max(probability, 0), 1)
        switch kind {
        case .logNormal:
            if let mean = stats.logMean, let standardDeviation = stats.logStandardDeviation {
                return exp(mean + standardDeviation * codexInverseNormalCDF(p))
            }
            return empiricalQuantile(p)
        default:
            return empiricalQuantile(p)
        }
    }

    public func conditionalCompletionProbability(elapsed: TimeInterval, horizon: TimeInterval) -> Double {
        guard elapsed >= 0, horizon >= 0 else { return 0 }
        let lower = cdf(max(elapsed, 0))
        let upper = cdf(max(elapsed + horizon, 0))
        let survival = max(1e-9, 1 - lower)
        return min(max((upper - lower) / survival, 0), 1)
    }

    public func conditionalRemainingQuantile(_ probability: Double, elapsed: TimeInterval) -> TimeInterval {
        let lower = cdf(max(elapsed, 0))
        let target = lower + (1 - lower) * min(max(probability, 0), 1)
        return max(0, quantile(target) - elapsed)
    }

    private func empiricalCDF(_ value: TimeInterval) -> Double {
        guard !values.isEmpty else { return 0 }
        let count = values.lastIndex { $0 <= value }.map { $0 + 1 } ?? 0
        return Double(count + 1) / Double(values.count + 2)
    }

    private func empiricalQuantile(_ probability: Double) -> TimeInterval {
        guard !values.isEmpty else { return 0 }
        if values.count == 1 { return values[0] }
        let position = probability * Double(values.count - 1)
        let lower = Int(floor(position))
        let upper = min(values.count - 1, lower + 1)
        let fraction = position - Double(lower)
        return values[lower] + (values[upper] - values[lower]) * fraction
    }
}

public struct CodexTaskDurationDistributionAnalyzer: Sendable {
    public let minimumSamples: Int

    public init(minimumSamples: Int = 10) {
        self.minimumSamples = max(1, minimumSamples)
    }

    public func stats(for rawValues: [TimeInterval]) -> CodexDurationDistributionStats? {
        let values = clean(rawValues)
        guard values.count >= minimumSamples else { return nil }
        let mean = values.reduce(0, +) / Double(values.count)
        let variance = values.count > 1
            ? values.reduce(0) { $0 + pow($1 - mean, 2) } / Double(values.count - 1)
            : 0
        let standardDeviation = sqrt(max(0, variance))
        let thirdMoment = values.reduce(0) { $0 + pow($1 - mean, 3) } / Double(values.count)
        let skewness = standardDeviation > 0 ? thirdMoment / pow(standardDeviation, 3) : 0
        let logValues = values.map(log)
        let logMean = logValues.reduce(0, +) / Double(logValues.count)
        let logVariance = logValues.count > 1
            ? logValues.reduce(0) { $0 + pow($1 - logMean, 2) } / Double(logValues.count - 1)
            : 0
        return CodexDurationDistributionStats(
            sampleCount: values.count,
            mean: mean,
            standardDeviation: standardDeviation,
            median: quantile(0.5, values: values),
            p20: quantile(0.2, values: values),
            p50: quantile(0.5, values: values),
            p80: quantile(0.8, values: values),
            p85: quantile(0.85, values: values),
            p90: quantile(0.9, values: values),
            coefficientOfVariation: mean > 0 ? standardDeviation / mean : 0,
            skewness: skewness,
            logMean: logMean,
            logStandardDeviation: sqrt(max(0, logVariance))
        )
    }

    public func model(for rawValues: [TimeInterval]) -> CodexDurationDistributionModel? {
        let values = clean(rawValues)
        guard let stats = stats(for: values) else { return nil }
        // The global history is strongly right-skewed. Use log-normal for
        // sufficiently large, positive, skewed cohorts; retain the empirical
        // model for sparse, symmetric, or irregular cohorts.
        let kind: CodexTaskForecastModel = values.count >= 30
            && stats.coefficientOfVariation >= 0.75
            && stats.skewness >= 0.75
            && (stats.logStandardDeviation ?? 0) > 0
            ? .logNormal
            : .empirical
        return CodexDurationDistributionModel(kind: kind, values: values, stats: stats)
    }

    public func clean(_ rawValues: [TimeInterval]) -> [TimeInterval] {
        rawValues.filter { $0.isFinite && $0 > 2 }.sorted()
    }

    /// Evaluates persisted forecasts without assuming a normal distribution.
    /// A forecast is included only after the monitor has attached an actual
    /// duration, which makes this suitable for walk-forward/backtest reports.
    public func calibrationReport(
        for observations: [CodexForecastObservation],
        entityType: CodexForecastEntityType? = .task
    ) -> CodexForecastCalibrationReport {
        let completed = observations.filter { observation in
            (entityType == nil || observation.entityType == entityType) &&
            observation.actualDuration.map { $0.isFinite && $0 > 2 } == true
        }

        var errors: [TimeInterval] = []
        var p85Hits = 0
        var p85Count = 0
        var safeAwayHits = 0
        var safeAwayCount = 0
        var brierValues: [Double] = []

        for observation in completed {
            guard let actualDuration = observation.actualDuration else { continue }
            let actualRemaining = max(0, actualDuration - observation.elapsedDuration)
            if let median = observation.medianRemaining, median.isFinite {
                errors.append(abs(median - actualRemaining))
            }
            if let upperTotal = observation.upperTotal, upperTotal.isFinite {
                p85Count += 1
                if actualDuration <= upperTotal { p85Hits += 1 }
            } else if let safe = observation.safeRemaining, safe.isFinite {
                p85Count += 1
                if actualRemaining <= safe { p85Hits += 1 }
            }
            if let safeAway = observation.safeAwayRemaining, safeAway.isFinite {
                safeAwayCount += 1
                if actualRemaining <= safeAway { safeAwayHits += 1 }
            }
            if let probability = observation.probabilityWithinHorizon,
               let horizon = observation.horizon,
               probability.isFinite,
               horizon.isFinite,
               horizon >= 0 {
                let outcome = actualRemaining <= horizon ? 1.0 : 0.0
                let clamped = min(max(probability, 0), 1)
                brierValues.append(pow(clamped - outcome, 2))
            }
        }

        return CodexForecastCalibrationReport(
            sampleCount: completed.count,
            medianAbsoluteError: median(of: errors),
            p85Coverage: p85Count > 0 ? Double(p85Hits) / Double(p85Count) : nil,
            safeAwayCoverage: safeAwayCount > 0 ? Double(safeAwayHits) / Double(safeAwayCount) : nil,
            probabilityBrierScore: brierValues.isEmpty ? nil : brierValues.reduce(0, +) / Double(brierValues.count)
        )
    }

    private func quantile(_ probability: Double, values: [TimeInterval]) -> TimeInterval {
        guard !values.isEmpty else { return 0 }
        if values.count == 1 { return values[0] }
        let position = probability * Double(values.count - 1)
        let lower = Int(floor(position))
        let upper = min(values.count - 1, lower + 1)
        return values[lower] + (values[upper] - values[lower]) * (position - Double(lower))
    }

    private func median(of values: [TimeInterval]) -> TimeInterval? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        if sorted.count % 2 == 1 { return sorted[sorted.count / 2] }
        let upper = sorted.count / 2
        return (sorted[upper - 1] + sorted[upper]) / 2
    }

}

private func codexNormalCDF(_ value: Double) -> Double {
    let sign = value < 0 ? -1.0 : 1.0
    let x = abs(value) / sqrt(2)
    let t = 1 / (1 + 0.3275911 * x)
    let polynomial = (((((1.061405429 * t - 1.453152027) * t) + 1.421413741) * t - 0.284496736) * t + 0.254829592) * t
    let erfApproximation = sign * (1 - polynomial * exp(-x * x))
    return 0.5 * (1 + erfApproximation)
}

private func codexInverseNormalCDF(_ probability: Double) -> Double {
    let p = min(max(probability, 1e-7), 1 - 1e-7)
    let a = [-39.6968302866538, 220.946098424521, -275.928510446969, 138.357751867269, -30.6647980661472, 2.50662827745924]
    let b = [-54.4760987982241, 161.585836858041, -155.698979859887, 66.8013118877197, -13.2806815528857]
    let c = [-0.00778489400243029, -0.322396458041136, -2.40075827716184, -2.54973253934373, 4.37466414146497, 2.93816398269878]
    let d = [0.00778469570904146, 0.32246712907004, 2.445134137143, 3.75440866190742]
    if p < 0.02425 {
        let q = sqrt(-2 * log(p))
        let numerator = ((((c[0] * q + c[1]) * q + c[2]) * q + c[3]) * q + c[4]) * q + c[5]
        let denominator = (((d[0] * q + d[1]) * q + d[2]) * q + d[3]) * q + 1
        return numerator / denominator
    }
    if p > 1 - 0.02425 {
        let q = sqrt(-2 * log(1 - p))
        let numerator = ((((c[0] * q + c[1]) * q + c[2]) * q + c[3]) * q + c[4]) * q + c[5]
        let denominator = (((d[0] * q + d[1]) * q + d[2]) * q + d[3]) * q + 1
        return -numerator / denominator
    }
    let q = p - 0.5
    let r = q * q
    let numerator = (((((a[0] * r + a[1]) * r + a[2]) * r + a[3]) * r + a[4]) * r + a[5]) * q
    let denominator = ((((b[0] * r + b[1]) * r + b[2]) * r + b[3]) * r + b[4]) * r + 1
    return numerator / denominator
}
