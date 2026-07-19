import CodexPaceBarCore
import SwiftUI

struct PopoverTaskSummary: View {
    let model: TaskMonitorViewModel
    let onOpenTaskMonitor: () -> Void

    var body: some View {
        TimelineView(
            .periodic(
                from: .now,
                by: CodexTaskMonitorRefreshPolicy.activeDisplayUpdateInterval
            )
        ) { context in
            content(at: context.date)
                .frame(minHeight: 48)
        }
    }

    @ViewBuilder
    private func content(at now: Date) -> some View {
        let needsYou = model.needsYou(at: now)
        let working = model.working(at: now)
        let presentation = CodexTaskSummaryPresenter().present(
            needsYou: needsYou,
            working: working,
            history: model.tasks,
            now: now,
            lastUpdatedAt: model.lastReloadDate
        )

        HStack(spacing: 10) {
            Image(systemName: iconName(for: presentation.state))
                .foregroundStyle(iconColor(for: presentation.state))

            VStack(alignment: .leading, spacing: 2) {
                Text(presentation.title)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)

                if let projectName = presentation.projectName {
                    HStack(spacing: 6) {
                        Text(projectName)
                        if let elapsedText = presentation.elapsedText {
                            Text(elapsedText)
                        }
                        if let estimateText = presentation.estimateText {
                            Text(estimateText)
                        }
                    }
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    if let additionalTasksText = presentation.additionalTasksText {
                        Text(additionalTasksText)
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                } else {
                    Text("Local metadata only · optional")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

                Text(presentation.freshnessText)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }

            Spacer(minLength: 8)

            Button(action: onOpenTaskMonitor) {
                Image(systemName: "arrow.up.forward.app")
            }
            .buttonStyle(.borderless)
            .help("Open full task monitor")
        }
        .padding(10)
        .background(.quaternary.opacity(0.42), in: RoundedRectangle(cornerRadius: 9))
    }

    private func iconName(for state: CodexTaskSummaryState) -> String {
        switch state {
        case .noActiveTasks: return "circle"
        case .working: return "circle.fill"
        case .needsYou: return "exclamationmark.circle.fill"
        }
    }

    private func iconColor(for state: CodexTaskSummaryState) -> Color {
        switch state {
        case .noActiveTasks: return .secondary
        case .working: return .blue
        case .needsYou: return .orange
        }
    }
}
