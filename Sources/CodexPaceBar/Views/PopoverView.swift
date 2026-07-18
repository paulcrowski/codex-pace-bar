import CodexPaceBarCore
import AppKit
import Charts
import SwiftUI

struct PopoverView: View {
    let model: AppModel
    let settings: SettingsStore
    let history: UsageHistoryStore
    let onRefresh: () -> Void
    let onOpenSettings: () -> Void
    let onQuit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if needsCodexSetup {
                missingCodexView
            } else if let failure = model.failure {
                Text("Could not read Codex weekly limit.")
                    .font(.headline)
                Text(failure.message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else if let snapshot = model.snapshot {
                ScrollView(.vertical, showsIndicators: false) {
                    metrics(snapshot)
                }
            } else {
                Text("Reading Codex rate limits...")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 260)
            }

            if needsCodexSetup {
                missingCodexActions
            } else {
                actions
            }
        }
        .padding(20)
        .frame(width: 465, height: 650)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(nsImage: largeBarImage)
                .frame(width: 425, height: 54)
                .accessibilityLabel(model.displayState.statusTitle)

            if model.isRefreshing {
                Text("Refreshing...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func metrics(_ snapshot: PaceSnapshot) -> some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                PopoverMetricCard(label: "Used", value: percent(snapshot.actualUsedPercent), color: usedMetricColor(snapshot))
                PopoverMetricCard(label: "Ideal", value: percent(snapshot.idealUsedPercent), color: .blue)
                PopoverMetricCard(label: "Remaining", value: percent(snapshot.remainingPercent), color: .gray)
            }

            PopoverStatusCard(
                title: paceStatus(snapshot),
                subtitle: forecastStatus,
                state: snapshot.state,
                isStale: snapshot.isStale
            )

            usageChart

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
                    value: hoursToReset(snapshot.resetAt)
                )
            }
            .padding(.horizontal, 16)
            .background(panelBackground)

            if snapshot.isStale {
                Text("Data may be stale after reset.")
                    .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }

    private var missingCodexView: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Codex CLI needs setup")
                .font(.system(size: 24, weight: .semibold))
                .lineLimit(1)

            Text("Codex Pace Bar needs a working `codex` command to read your weekly limit.")
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button(action: openCodexSetupGuide) {
                Label("Codex setup guide", systemImage: "book")
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
            .buttonBorderShape(.roundedRectangle(radius: 8))
        }
        .padding(.top, 112)
        .padding(.bottom, 22)
    }

    private var actions: some View {
        VStack(spacing: 16) {
            Divider()

            HStack(spacing: 10) {
                Button(action: onRefresh) {
                    Label("Refresh now", systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.isRefreshing)

                Button(action: onOpenSettings) {
                    Label("Settings", systemImage: "gearshape")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button(action: onQuit) {
                    Label("Quit", systemImage: "power")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            .controlSize(.large)
            .buttonBorderShape(.roundedRectangle(radius: 8))
        }
    }

    private var missingCodexActions: some View {
        VStack(spacing: 16) {
            Divider()

            HStack(spacing: 14) {
                Button(action: chooseCodexPath) {
                    Label("Choose codex path", systemImage: "folder.badge.questionmark")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button(action: onRefresh) {
                    Label("Refresh", systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.isRefreshing)
            }
            .controlSize(.large)
            .buttonBorderShape(.roundedRectangle(radius: 8))
        }
    }

    private var needsCodexSetup: Bool {
        model.failure?.requiresCodexSetup == true
    }

    private func openCodexSetupGuide() {
        guard let url = URL(string: "https://developers.openai.com/codex/cli") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    private func chooseCodexPath() {
        let panel = NSOpenPanel()
        panel.title = "Choose codex executable"
        panel.prompt = "Choose"
        panel.message = "Select the codex command-line executable."
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.resolvesAliases = true
        panel.showsHiddenFiles = true

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        if FileManager.default.isExecutableFile(atPath: url.path) {
            settings.codexExecutablePath = url.path
        } else {
            let alert = NSAlert()
            alert.messageText = "Selected file is not executable."
            alert.informativeText = "Choose the real codex command file."
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }

    private func percent(_ value: Double) -> String {
        "\(Int(value.rounded()))%"
    }

    private func usedMetricColor(_ snapshot: PaceSnapshot) -> Color {
        snapshot.deltaPercentagePoints > 0 ? .red : .green
    }

    private func paceStatus(_ snapshot: PaceSnapshot) -> String {
        guard snapshot.state != .onPace else {
            return "On pace"
        }

        let durationHours = (model.selectedWindow?.windowDurationMins ?? 0) / 60
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

    private func hours(_ value: Double) -> String {
        if value < 1, value > 0 {
            return "<1 h"
        }
        return "\(Int(value.rounded(.up))) h"
    }

    private func hoursToReset(_ resetAt: Date) -> String {
        let hours = max(0, resetAt.timeIntervalSinceNow / 3600)
        return self.hours(hours)
    }

    private var forecastStatus: String? {
        guard let forecast = model.forecast else {
            return nil
        }

        if forecast.willRunOutBeforeReset {
            return "Forecast: may run out in \(hours(forecast.hoursUntilExhaustion(at: Date())))"
        }

        return "Forecast: usage should last until reset"
    }

    private var usageChart: some View {
        VStack(alignment: .leading, spacing: 8) {
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

                ForEach(idealChartPoints) { point in
                    LineMark(
                        x: .value("Time", point.date),
                        y: .value("Ideal", point.value),
                        series: .value("Series", "Ideal")
                    )
                    .foregroundStyle(by: .value("Series", "Ideal"))
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                }

                ForEach(forecastChartPoints) { point in
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
            .frame(height: 145)

            HStack(spacing: 14) {
                PopoverChartLegendItem(label: "Actual", color: .blue)
                PopoverChartLegendItem(label: "Ideal pace", color: .gray)
                PopoverChartLegendItem(
                    label: model.forecast == nil ? "Forecast pending" : "Forecast",
                    color: model.forecast == nil ? .orange.opacity(0.4) : .orange
                )
            }
        }
        .padding(12)
        .background(panelBackground)
    }

    private var idealChartPoints: [PopoverUsageChartPoint] {
        guard let window = model.selectedWindow else {
            return []
        }

        let start = window.resetsAt.addingTimeInterval(-window.windowDurationMins * 60)
        return [
            PopoverUsageChartPoint(id: "ideal-start", date: start, value: 0),
            PopoverUsageChartPoint(id: "ideal-end", date: window.resetsAt, value: 100)
        ]
    }

    private var forecastChartPoints: [PopoverUsageChartPoint] {
        guard let latest = history.currentSamples.last, let forecast = model.forecast else {
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

    private var largeBarImage: NSImage {
        MenuBarIconRenderer(size: NSSize(width: 425, height: 54)).render(
            snapshot: model.snapshot,
            state: model.displayState,
            isStale: model.snapshot?.isStale ?? false,
            colorScheme: settings.barColorScheme
        )
    }

    private var panelBackground: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(.quaternary.opacity(0.5))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(.separator.opacity(0.35), lineWidth: 1)
            }
    }
}
