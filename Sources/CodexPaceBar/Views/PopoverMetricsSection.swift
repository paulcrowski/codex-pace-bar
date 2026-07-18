import CodexPaceBarAppSupport
import CodexPaceBarCore
import SwiftUI

struct PopoverMetricsSection: View {
    let model: AppModel
    let history: UsageHistoryStore
    let snapshot: PaceSnapshot

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                PopoverMetricCard(label: "Used", value: PopoverPresentation.percent(snapshot.actualUsedPercent), color: usedMetricColor)
                PopoverMetricCard(label: "Ideal", value: PopoverPresentation.percent(snapshot.idealUsedPercent), color: .blue)
                PopoverMetricCard(label: "Remaining", value: PopoverPresentation.percent(snapshot.remainingPercent), color: .gray)
            }

            PopoverStatusCard(
                title: PopoverPresentation.paceStatus(
                    snapshot: snapshot,
                    windowDurationMins: model.selectedWindow?.windowDurationMins
                ),
                subtitle: PopoverPresentation.forecastStatus(model.forecast, now: Date()),
                state: snapshot.state,
                isStale: snapshot.isStale
            )

            PopoverUsageChart(model: model, history: history)

            VStack(spacing: 0) {
                PopoverDetailRow(
                    icon: "clock",
                    label: "Resets",
                    value: DateFormatters.resetFormatter.string(from: snapshot.resetAt)
                )

                Divider()
                    .padding(.leading, 48)

                PopoverDetailRow(
                    icon: "hourglass",
                    label: "Hours to reset",
                    value: PopoverPresentation.hoursToReset(snapshot.resetAt, now: Date())
                )
            }
            .padding(.horizontal, 16)
            .background(PopoverPanelBackground())

            if snapshot.isStale {
                Text("Data may be stale after reset.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if history.lastPersistenceError != nil {
                Text("Local history could not be saved. Forecast learning may be limited.")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    private var usedMetricColor: Color {
        snapshot.deltaPercentagePoints > 0 ? .red : .green
    }
}
