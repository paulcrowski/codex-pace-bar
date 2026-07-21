import Foundation
import SQLite3

// Bounded, read-only local report. It intentionally reads only scalar timing
// and plan-feature columns; prompts, responses, and raw plan text are absent.
let databasePath = CommandLine.arguments.dropFirst().first
    ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("CodexPaceBar/task-activity.sqlite").path

var database: OpaquePointer?
guard sqlite3_open_v2(databasePath, &database, SQLITE_OPEN_READONLY, nil) == SQLITE_OK,
      let database else {
    fputs("Could not open local Task Monitor database: \(databasePath)\n", stderr)
    exit(2)
}
defer { sqlite3_close(database) }

func scalarRows(_ sql: String) -> [Double] {
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
          let statement else { return [] }
    defer { sqlite3_finalize(statement) }
    var values: [Double] = []
    while sqlite3_step(statement) == SQLITE_ROW {
        values.append(sqlite3_column_double(statement, 0))
    }
    return values
}

func count(_ sql: String) -> Int {
    Int(scalarRows(sql).first ?? 0)
}

func tableExists(_ name: String) -> Bool {
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(
        database,
        "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = '\(name)' LIMIT 1;",
        -1,
        &statement,
        nil
    ) == SQLITE_OK,
    let statement else { return false }
    defer { sqlite3_finalize(statement) }
    return sqlite3_step(statement) == SQLITE_ROW
}

func quantile(_ p: Double, _ values: [Double]) -> Double {
    guard !values.isEmpty else { return 0 }
    if values.count == 1 { return values[0] }
    let position = p * Double(values.count - 1)
    let lower = Int(floor(position))
    let upper = min(values.count - 1, lower + 1)
    return values[lower] + (values[upper] - values[lower]) * (position - Double(lower))
}

let cutoff = Date().timeIntervalSince1970 - 90 * 24 * 60 * 60
let durations = scalarRows("""
SELECT MAX(0, duration - COALESCE(waiting_duration, 0))
FROM task_activity
WHERE status = 'completed'
  AND completed_at >= \(cutoff)
  AND duration IS NOT NULL
  AND duration > 2;
""").filter { $0.isFinite && $0 > 2 }.sorted()

guard !durations.isEmpty else {
    print("No completed task durations available in the bounded 90-day window.")
    exit(0)
}

let mean = durations.reduce(0, +) / Double(durations.count)
let variance = durations.count > 1
    ? durations.reduce(0) { $0 + pow($1 - mean, 2) } / Double(durations.count - 1)
    : 0
let sigma = sqrt(max(0, variance))
let logs = durations.map(log)
let logMean = logs.reduce(0, +) / Double(logs.count)
let logVariance = logs.count > 1
    ? logs.reduce(0) { $0 + pow($1 - logMean, 2) } / Double(logs.count - 1)
    : 0
let logSigma = sqrt(max(0, logVariance))
let logNormalP50 = exp(logMean)
let logNormalP85 = exp(logMean + 1.036433 * logSigma)
let logNormalP90 = exp(logMean + 1.281552 * logSigma)
let hasPlanTable = tableExists("task_initial_plan")
let hasForecastTable = tableExists("forecast_observation")
let planCount = hasPlanTable ? count("SELECT COUNT(*) FROM task_initial_plan WHERE observed_at >= \(cutoff);") : 0
let forecastCount = hasForecastTable ? count("SELECT COUNT(*) FROM forecast_observation WHERE entity_type = 'task' AND observed_at >= \(cutoff);") : 0

func minutes(_ seconds: Double) -> String { String(format: "%.2f", seconds / 60) }
print("Plan-aware Task Monitor backtest")
print("window_days=90 sample=\(durations.count) plans=\(planCount) task_forecasts=\(forecastCount)")
print("mean_min=\(minutes(mean)) sigma_min=\(minutes(sigma)) median_min=\(minutes(quantile(0.5, durations)))")
print("p80_min=\(minutes(quantile(0.80, durations))) p85_min=\(minutes(quantile(0.85, durations))) p90_min=\(minutes(quantile(0.90, durations)))")
print("normal_lower_2sigma_min=\(minutes(mean - 2 * sigma))")
print("log_normal_p50_min=\(minutes(logNormalP50)) log_normal_p85_min=\(minutes(logNormalP85)) log_normal_p90_min=\(minutes(logNormalP90))")
let planCoverage = String(format: "%.1f%%", 100 * Double(planCount) / Double(durations.count))
print("plan_coverage=\(planCoverage)")
if !hasPlanTable { print("plan_table=missing (database predates plan telemetry)") }
if !hasForecastTable { print("forecast_table=missing (database predates forecast telemetry)") }

if hasForecastTable {
    let p85TotalRows = scalarRows("""
    SELECT CASE WHEN actual_duration <= upper_total THEN 1.0 ELSE 0.0 END
    FROM forecast_observation
    WHERE entity_type = 'task' AND observed_at >= \(cutoff)
      AND actual_duration IS NOT NULL AND upper_total IS NOT NULL;
    """)
    let p85Coverage = p85TotalRows.isEmpty ? "n/a" : String(format: "%.1f%%", 100 * p85TotalRows.reduce(0, +) / Double(p85TotalRows.count))
    print("persisted_p85_coverage=\(p85Coverage) samples=\(p85TotalRows.count)")
}
