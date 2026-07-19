import CodexPaceBarCore
import SwiftUI

struct TaskMonitorView: View {
    @Bindable var model: TaskMonitorViewModel
    @State private var showsClearHistoryConfirmation = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let needsYou = model.needsYou(at: context.date)
            let working = model.working(at: context.date)
            let finished = model.recentlyFinished(at: context.date)
            VStack(alignment: .leading, spacing: 0) {
                header(
                    needsYou: needsYou.count,
                    working: working.count,
                    updatedAt: model.lastReloadDate
                )
                    .padding(.bottom, 12)

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        if let title = model.health.title,
                           let detail = model.health.detail {
                            TaskMonitorStaleBanner(title: title, detail: detail)
                        }

                        if let rhythm = model.workRhythm(at: context.date) {
                            WorkRhythmSummary(estimate: rhythm)
                        }

                        if let prompt = model.checkInPrompt(at: context.date) {
                            DailyCheckIn(
                                period: prompt.period,
                                selection: model.currentCheckIn(on: prompt.day),
                                onSelect: { model.saveCheckIn($0, for: prompt) }
                            )
                        }

                        if !needsYou.isEmpty {
                            TaskSection(title: "Needs you", color: .orange) {
                                ForEach(needsYou) { task in
                                    TaskMonitorRow(
                                        task: task,
                                        estimate: nil,
                                        now: context.date,
                                        canNavigate: model.canNavigate(to: task),
                                        onNavigate: { model.navigate(to: task) }
                                    )
                                }
                            }
                        }

                        if !working.isEmpty {
                            TaskSection(title: "Working", color: .blue) {
                                ForEach(working) { task in
                                    TaskMonitorRow(
                                        task: task,
                                        estimate: model.estimate(for: task, now: context.date),
                                        now: context.date,
                                        canNavigate: model.canNavigate(to: task),
                                        onNavigate: { model.navigate(to: task) }
                                    )
                                }
                            }
                        }

                        if needsYou.isEmpty, working.isEmpty, finished.isEmpty {
                            ContentUnavailableView(
                                "No tasks",
                                systemImage: "checklist",
                                description: Text("New Codex tasks appear here automatically.")
                            )
                        }

                        TodaySummary(
                            summary: model.todaySummary
                        )

                        if !finished.isEmpty {
                            TaskSection(title: "Completed today", color: .green) {
                                ForEach(finished.prefix(6)) { task in
                                    TaskMonitorRow(
                                        task: task,
                                        estimate: nil,
                                        now: context.date,
                                        canNavigate: model.canNavigate(to: task),
                                        onNavigate: { model.navigate(to: task) }
                                    )
                                }
                            }
                        }

                        Text("Live approval status uses optional Codex Hooks. Task-finished alerts also work from local session logs.")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.bottom, 8)
                }
            }
            .padding(18)
        }
        .frame(width: 410, height: 560)
    }

    private func header(needsYou: Int, working: Int, updatedAt: Date?) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text("Codex tasks")
                    .font(.system(size: 20, weight: .semibold))
                Text(headerStatus(needsYou: needsYou, working: working, updatedAt: updatedAt))
                    .font(.system(size: 12))
                    .foregroundStyle(needsYou > 0 ? .orange : .secondary)
            }
            Spacer()
            HStack(spacing: 8) {
                Button { model.reload() } label: { Image(systemName: "arrow.clockwise") }
                    .accessibilityLabel("Refresh tasks")
                Button { showsClearHistoryConfirmation = true } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Delete local task history")
                .help("Delete local task history")
            }
                .buttonStyle(.borderless)
                .help("Refresh list")
        }
        .confirmationDialog(
            "Delete local task history?",
            isPresented: $showsClearHistoryConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete history", role: .destructive) { model.clearHistory() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes stored task activity, status events, and check-ins from this Mac.")
        }
    }

    private func headerStatus(needsYou: Int, working: Int, updatedAt: Date?) -> String {
        let workingText = "\(working) working"
        let updatedText = updatedAt.map { " · \(freshnessText($0))" } ?? ""
        guard needsYou > 0 else {
            return "\(workingText) · local timing and status\(updatedText)"
        }
        let needsText = needsYou == 1 ? "1 needs you" : "\(needsYou) need you"
        return "\(needsText) · \(workingText)\(updatedText)"
    }

    private func freshnessText(_ date: Date) -> String {
        let seconds = max(0, Int(Date().timeIntervalSince(date).rounded()))
        if seconds < 5 { return "updated just now" }
        if seconds < 60 { return "updated \(seconds) sec ago" }
        return "updated \(seconds / 60) min ago"
    }
}

private struct TaskMonitorStaleBanner: View {
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Refresh to try again.")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct TaskSection<Content: View>: View {
    let title: String
    let color: Color
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(color)
            content
        }
    }
}

private struct WorkRhythmSummary: View {
    let estimate: CodexWorkRhythmEstimate

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: estimate.level == .veryIntense ? "figure.walk" : "waveform.path.ecg")
                .foregroundStyle(estimate.level == .veryIntense ? .orange : .blue)
            VStack(alignment: .leading, spacing: 2) {
                Text(estimate.isPersonallyCalibrated
                    ? "Work rhythm: \(estimate.level.label)"
                    : "Work rhythm: Learning")
                    .font(.system(size: 12, weight: .medium))
                Text(estimate.detail)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(10)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct TodaySummary: View {
    let summary: CodexTaskDailySummary

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("TODAY")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
            HStack(spacing: 12) {
                metric("Active time", summary.activeWallTime.durationText)
                metric("Completed", "\(summary.completedTasks)")
                metric(
                    "Approval / input wait",
                    summary.waitingForUser > 0 ? summary.waitingForUser.durationText : "None"
                )
            }
            if summary.agentHours > summary.activeWallTime {
                Text("Parallel agent time \(summary.agentHours.durationText)")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Text("Wait counts only while Codex asks for approval or input; time after a task finishes is not counted.")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
            Text("Local task activity. The main pace bar forecasts your Codex limit.")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
        .padding(10)
        .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 8))
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value).font(.system(size: 13, weight: .semibold))
            Text(title).font(.system(size: 10)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct DailyCheckIn: View {
    let period: CodexDailyCheckInPeriod
    let selection: CodexDailyWorkRating?
    let onSelect: (CodexDailyWorkRating) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(period == .yesterday ? "How did work feel yesterday?" : "How did work feel today?")
                .font(.system(size: 12, weight: .medium))
            HStack {
                choice("Calm", .calm)
                choice("Intense", .intense)
                choice("Too much", .tooMuch)
            }
        }
    }

    private func choice(_ title: String, _ value: CodexDailyWorkRating) -> some View {
        Button(title) { onSelect(value) }
            .buttonStyle(.bordered)
            .tint(selection == value ? .accentColor : .secondary)
            .controlSize(.small)
    }
}

private struct TaskMonitorRow: View {
    let task: CodexTaskActivity
    let estimate: CodexTaskDurationEstimate?
    let now: Date
    let canNavigate: Bool
    let onNavigate: () -> Void

    var body: some View {
        let visibleStatus = task.visibleStatus
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: visibleStatus.symbol)
                .foregroundStyle(visibleStatus.color)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(task.projectName).font(.system(size: 13, weight: .medium)).lineLimit(1)
                    Spacer()
                    Text(visibleStatus.label).font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                }
                HStack(spacing: 8) {
                    Text(task.durationText(at: now))
                    if let estimate { Text(estimate.etaText) }
                }
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            }
            if canNavigate {
                Button(action: onNavigate) { Image(systemName: "arrow.up.forward.app") }
                    .buttonStyle(.borderless)
                    .help("Open the app for this task")
            }
        }
        .padding(10)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 8))
    }
}

private extension CodexTaskDurationEstimate {
    var etaText: String {
        guard let medianRemaining, let safeRemaining else {
            return "Not enough history (\(sampleCount) similar)"
        }
        return "Usually \(medianRemaining.durationText)–\(safeRemaining.durationText) · based on \(sampleCount) similar"
    }
}

private extension CodexTaskActivity {
    var projectName: String {
        projectDisplayName
    }

    func durationText(at now: Date) -> String {
        let seconds = duration ?? startedAt.map { max(0, now.timeIntervalSince($0)) } ?? 0
        if status.isWaitingForUser, let waitingStartedAt {
            return "waiting \(max(0, now.timeIntervalSince(waitingStartedAt)).durationText)"
        }
        return seconds.durationText
    }
}

private extension TimeInterval {
    var durationText: String {
        let totalMinutes = max(0, Int((self / 60).rounded()))
        if totalMinutes < 1 { return "<1 min" }
        if totalMinutes < 60 { return "\(totalMinutes) min" }
        return "\(totalMinutes / 60) h \(totalMinutes % 60) min"
    }
}

private extension CodexWorkRhythmLevel {
    var label: String {
        switch self { case .calm: "calm"; case .intense: "intense"; case .veryIntense: "very intense" }
    }
}

private extension CodexTaskStatus {
    var label: String {
        switch self {
        case .queued: "Queued"
        case .working: "Working"
        case .needsApproval: "Needs approval"
        case .needsInput: "Waiting for input"
        case .completed: "Completed"
        case .failed: "Failed"
        case .cancelled: "Cancelled"
        case .stale: "Inactive"
        }
    }

    var symbol: String {
        switch self {
        case .queued: "clock.fill"
        case .working: "circle.fill"
        case .needsApproval, .needsInput: "exclamationmark.circle.fill"
        case .completed: "checkmark.circle.fill"
        case .failed: "xmark.circle.fill"
        case .cancelled, .stale: "minus.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .queued: .secondary
        case .working: .blue
        case .needsApproval, .needsInput: .orange
        case .completed: .green
        case .failed: .red
        case .cancelled, .stale: .secondary
        }
    }
}
