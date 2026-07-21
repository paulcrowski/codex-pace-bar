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
                MetricCard(label: "Used", value: percent(snapshot.actualUsedPercent), color: usedMetricColor(snapshot))
                MetricCard(label: "Ideal", value: percent(snapshot.idealUsedPercent), color: .blue)
                MetricCard(label: "Remaining", value: percent(snapshot.remainingPercent), color: .gray)
            }

            StatusCard(
                title: paceStatus(snapshot),
                subtitle: forecastStatus,
                state: snapshot.state,
                isStale: snapshot.isStale
            )

            usageChart

            VStack(spacing: 0) {
                DetailRow(
                    icon: "clock",
                    label: "Resets",
                    value: DateFormatters.resetFormatter.string(from: snapshot.resetAt)
                )

                Divider()
                    .padding(.leading, 48)

                DetailRow(
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

                ForEach(forecastChartPoints) { point in
                    LineMark(
                        x: .value("Time", point.date),
                        y: .value("Forecast", point.value),
                        series: .value("Series", "Forecast")
                    )
                    .foregroundStyle(by: .value("Series", "Forecast"))
                    .lineStyle(StrokeStyle(lineWidth: 2, dash: [6, 3]))
                    .interpolationMethod(.linear)
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
                ChartLegendItem(label: "Actual", color: .blue)
                ChartLegendItem(
                    label: model.forecast == nil ? "Forecast pending" : "Forecast",
                    color: model.forecast == nil ? .orange.opacity(0.4) : .orange
                )
            }
        }
        .padding(12)
        .background(panelBackground)
    }

    private var forecastChartPoints: [UsageChartPoint] {
        guard let forecast = model.forecast else {
            return []
        }

        return forecast.projection.enumerated().map { index, point in
            UsageChartPoint(
                id: "forecast-\(index)",
                date: point.timestamp,
                value: point.usedPercent
            )
        }
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

private struct UsageChartPoint: Identifiable {
    let id: String
    let date: Date
    let value: Double
}

private struct ChartLegendItem: View {
    let label: String
    let color: Color

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct MetricCard: View {
    let label: String
    let value: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Circle()
                    .fill(color)
                    .frame(width: 9, height: 9)

                Text(label)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
            }

            Text(value)
                .font(.system(size: 30, weight: .regular))
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.quaternary.opacity(0.5))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(.separator.opacity(0.35), lineWidth: 1)
                }
        }
    }
}

private struct StatusCard: View {
    let title: String
    let subtitle: String?
    let state: PaceState
    let isStale: Bool

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(iconColor.opacity(0.25))

                Image(systemName: iconName)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(iconColor)
            }
            .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.quaternary.opacity(0.5))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(.separator.opacity(0.35), lineWidth: 1)
                }
        }
    }

    private var iconColor: Color {
        if isStale {
            return .gray
        }

        switch state {
        case .abovePace:
            return .blue
        case .belowPace:
            return .green
        case .onPace:
            return .blue
        case .loading, .error:
            return .gray
        }
    }

    private var iconName: String {
        switch state {
        case .abovePace:
            return "waveform.path.ecg"
        case .belowPace:
            return "arrow.down.right"
        case .onPace:
            return "checkmark"
        case .loading:
            return "clock"
        case .error:
            return "exclamationmark"
        }
    }
}

private struct DetailRow: View {
    let icon: String
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .regular))
                .foregroundStyle(.blue)
                .frame(width: 24)

            Text(label)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.secondary)

            Spacer()

            Text(value)
                .font(.system(size: 14, weight: .semibold))
                .monospacedDigit()
        }
        .frame(height: 42)
    }
}
