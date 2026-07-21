@preconcurrency import AppKit
import CodexPaceBarAppSupport
import CodexPaceBarCore
import SwiftUI

@MainActor
final class TaskMonitorStatusBarController: NSObject, NSPopoverDelegate {
    private let statusItem: NSStatusItem
    private let popover: NSPopover
    private let model: TaskMonitorViewModel
    private let freshnessPolicy = CodexTaskFreshnessPolicy()
    private var activeGoalThreadIDs = Set<String>()
    private var outsideClickMonitor: Any?
    private var liveRefreshTimer: Timer?

    init(model: TaskMonitorViewModel) {
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.popover = NSPopover()
        self.model = model
        super.init()

        popover.behavior = .transient
        popover.delegate = self
        popover.contentSize = NSSize(width: 410, height: 560)
        popover.contentViewController = NSHostingController(
            rootView: TaskMonitorView(model: model)
        )

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "checklist", accessibilityDescription: "Codex tasks")
            button.imagePosition = .imageOnly
            button.toolTip = "Codex tasks"
            button.target = self
            button.action = #selector(togglePopover)
        }
        let previousReloadHandler = model.onTasksReloaded
        model.onTasksReloaded = { [weak self] tasks in
            previousReloadHandler?(tasks)
            self?.updateStatusItem(tasks: tasks)
        }
        let previousActivityReloadHandler = model.onActivityReloaded
        model.onActivityReloaded = { [weak self] tasks, goals, swarms in
            previousActivityReloadHandler?(tasks, goals, swarms)
            self?.activeGoalThreadIDs = Set(
                goals.filter { $0.isActive }.map { $0.threadID }
            )
            self?.updateStatusItem(tasks: tasks)
        }
    }

    private func updateStatusItem(tasks: [CodexTaskActivity]) {
        guard let button = statusItem.button else { return }
        let now = Date()
        let fresh = tasks.filter {
            $0.status.isActive
                && freshnessPolicy.isFresh(
                    task: $0,
                    now: now,
                    activeGoalThreadIDs: activeGoalThreadIDs
                )
        }
        let needs = fresh.filter { $0.status.isWaitingForUser }.count
        let working = fresh.filter(\.isRunning).count
        button.imagePosition = (needs + working) > 0 ? .imageLeading : .imageOnly
        button.title = needs > 0 ? " !\(needs)" : (working > 0 ? " \(working)" : "")
        button.toolTip = needs > 0 ? "Codex needs you" : "Codex tasks"
    }

    func setFocusLoadEnabled(_ enabled: Bool) {
        model.focusLoadEnabled = enabled
    }

    func stop() {
        liveRefreshTimer?.invalidate()
        liveRefreshTimer = nil
        if let outsideClickMonitor {
            NSEvent.removeMonitor(outsideClickMonitor)
            self.outsideClickMonitor = nil
        }
        popover.performClose(nil)
    }

    func show() {
        guard let button = statusItem.button, !popover.isShown else {
            return
        }
        NSApp.activate(ignoringOtherApps: true)
        model.reload()
        startLiveRefreshTimer()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        startOutsideClickMonitor()
    }

    @objc private func togglePopover() {
        guard statusItem.button != nil else {
            return
        }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            show()
        }
    }

    func popoverDidClose(_ notification: Notification) {
        liveRefreshTimer?.invalidate()
        liveRefreshTimer = nil
        stopOutsideClickMonitor()
    }

    private func startLiveRefreshTimer() {
        liveRefreshTimer?.invalidate()
        liveRefreshTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.model.reload()
            }
        }
    }

    private func startOutsideClickMonitor() {
        guard outsideClickMonitor == nil else {
            return
        }
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] _ in
            Task { @MainActor in
                self?.popover.performClose(nil)
            }
        }
    }

    private func stopOutsideClickMonitor() {
        guard let outsideClickMonitor else {
            return
        }
        NSEvent.removeMonitor(outsideClickMonitor)
        self.outsideClickMonitor = nil
    }
}
