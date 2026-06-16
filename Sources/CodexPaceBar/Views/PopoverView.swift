import CodexPaceBarCore
import AppKit
import SwiftUI

struct PopoverView: View {
    let model: AppModel
    let settings: SettingsStore
    let onRefresh: () -> Void
    let onOpenSettings: () -> Void
    let onQuit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if let errorMessage = model.errorMessage {
                Text("Could not read Codex weekly limit.")
                    .font(.headline)
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else if let snapshot = model.snapshot {
                metrics(snapshot)
            } else {
                Text("Reading Codex rate limits...")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 260)
            }

            actions
        }
        .padding(20)
        .frame(width: 465)
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

            StatusCard(title: paceStatus(snapshot), state: snapshot.state, isStale: snapshot.isStale)

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

            Text(title)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)

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
