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
            }

            Divider()

            HStack {
                Button("Refresh now", action: onRefresh)
                    .disabled(model.isRefreshing)
                Button("Settings", action: onOpenSettings)
                Spacer()
                Button("Quit", action: onQuit)
            }
        }
        .padding(14)
        .frame(width: 310)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(nsImage: largeBarImage)
                .frame(width: 260, height: 42)
                .accessibilityLabel(model.displayState.statusTitle)

            if model.isRefreshing {
                Text("Refreshing...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func metrics(_ snapshot: PaceSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            MetricRow(label: "Used this week", value: percent(snapshot.actualUsedPercent))
            MetricRow(label: idealByNowLabel(snapshot), value: percent(snapshot.idealUsedPercent))
            MetricRow(label: "Remaining", value: percent(snapshot.remainingPercent))
            MetricRow(label: "Resets", value: DateFormatters.resetFormatter.string(from: snapshot.resetAt))
            MetricRow(label: "Hours to reset", value: hoursToReset(snapshot.resetAt))

            if snapshot.isStale {
                Text("Data may be stale after reset.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func percent(_ value: Double) -> String {
        "\(Int(value.rounded()))%"
    }

    private func idealByNowLabel(_ snapshot: PaceSnapshot) -> String {
        guard
            let selectedWindow = model.selectedWindow,
            let waitHours = PaceCalculator.hoursUntilOnPace(snapshot: snapshot, window: selectedWindow)
        else {
            return "Ideal by now"
        }

        return "Ideal by now (wait \(hours(waitHours)))"
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

    private func color(for state: PaceState, isStale: Bool) -> Color {
        if isStale {
            return .gray
        }

        switch state {
        case .belowPace:
            return .green
        case .onPace:
            return .blue
        case .abovePace:
            return .red
        case .loading, .error:
            return .gray
        }
    }

    private var largeBarImage: NSImage {
        MenuBarIconRenderer(size: NSSize(width: 260, height: 42)).render(
            snapshot: model.snapshot,
            state: model.displayState,
            isStale: model.snapshot?.isStale ?? false,
            colorScheme: settings.barColorScheme
        )
    }
}

private struct MetricRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .monospacedDigit()
        }
        .font(.system(size: 13))
    }
}
