import Charts
import CodexPaceBarAppSupport
import CodexPaceBarCore
import SwiftUI

struct PopoverUsageChart: View {
    let model: AppModel
    let history: UsageHistoryStore

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text("Weekly limit usage (%)")
                    .font(.system(size: 14, weight: .semibold))

                Spacer()

                Text("Current weekly window")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Chart {
                ForEach(history.currentSamples, id: \.timestamp) { sample in
                    LineMark(
                        x: .value("Time", sample.timestamp),
                        y: .value("Used", sample.usedPercent),
                        series: .value("Series", "Actual")
                    )
                    .foregroundStyle(by: .value("Series", "Actual"))
                    .interpolationMethod(.linear)
                }

                ForEach(PopoverPresentation.idealChartPoints(for: model.selectedWindow)) { point in
                    LineMark(
                        x: .value("Time", point.date),
                        y: .value("Ideal", point.value),
                        series: .value("Series", "Ideal")
                    )
                    .foregroundStyle(by: .value("Series", "Ideal"))
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                }

                ForEach(PopoverPresentation.forecastChartPoints(latest: history.currentSamples.last, forecast: model.forecast)) { point in
                    LineMark(
                        x: .value("Time", point.date),
                        y: .value("Forecast", point.value),
                        series: .value("Series", "Forecast")
                    )
                    .foregroundStyle(by: .value("Series", "Forecast"))
                    .lineStyle(StrokeStyle(lineWidth: 2, dash: [6, 3]))
                }

                if let latest = history.currentSamples.last {
                    PointMark(
                        x: .value("Time", latest.timestamp),
                        y: .value("Used", latest.usedPercent)
                    )
                    .foregroundStyle(by: .value("Series", "Actual"))
                }
            }
            .chartForegroundStyleScale([
                "Actual": Color.blue,
                "Ideal": Color.gray,
                "Forecast": Color.orange
            ])
            .chartLegend(.hidden)
            .chartYScale(domain: 0...100)
            .chartYAxis {
                AxisMarks(position: .leading, values: [0, 50, 100]) {
                    AxisGridLine()
                    AxisValueLabel()
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) {
                    AxisGridLine()
                    AxisValueLabel(format: .dateTime.weekday(.abbreviated).hour())
                }
            }
            .frame(height: 105)

            HStack(spacing: 10) {
                PopoverChartLegendItem(label: "Actual", color: .blue)
                PopoverChartLegendItem(label: "Ideal pace", color: .gray)
                PopoverChartLegendItem(
                    label: model.forecast == nil ? "Forecast pending" : "Forecast",
                    color: model.forecast == nil ? .orange.opacity(0.4) : .orange
                )
            }
        }
        .padding(10)
        .background(PopoverPanelBackground())
    }
}

struct PopoverPanelBackground: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(.quaternary.opacity(0.5))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(.separator.opacity(0.35), lineWidth: 1)
            }
    }
}
