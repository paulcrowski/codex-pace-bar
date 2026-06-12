@preconcurrency import AppKit
import CodexPaceBarCore
import SwiftUI

@MainActor
final class StatusBarController: NSObject {
    private let model: AppModel
    private let settings: SettingsStore
    private let statusItem: NSStatusItem
    private let popover: NSPopover
    private let renderer = MenuBarIconRenderer()
    private let onRefresh: () -> Void
    private let onOpenSettings: () -> Void
    private let onQuit: () -> Void

    init(
        model: AppModel,
        settings: SettingsStore,
        onRefresh: @escaping () -> Void,
        onOpenSettings: @escaping () -> Void,
        onQuit: @escaping () -> Void
    ) {
        self.model = model
        self.settings = settings
        self.onRefresh = onRefresh
        self.onOpenSettings = onOpenSettings
        self.onQuit = onQuit
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.popover = NSPopover()
        super.init()

        popover.behavior = .transient
        popover.contentSize = NSSize(width: 465, height: 440)
        popover.contentViewController = NSHostingController(
            rootView: PopoverView(
                model: model,
                settings: settings,
                onRefresh: onRefresh,
                onOpenSettings: onOpenSettings,
                onQuit: onQuit
            )
        )

        if let button = statusItem.button {
            button.target = self
            button.action = #selector(togglePopover)
            button.imagePosition = .imageOnly
            button.toolTip = "Codex Pace Bar"
        }

        model.onChange = { [weak self] in
            self?.updateIcon()
        }
        updateIcon()
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else {
            return
        }

        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    private func updateIcon() {
        statusItem.button?.image = renderer.render(
            snapshot: model.snapshot,
            state: model.displayState,
            isStale: model.snapshot?.isStale ?? false,
            colorScheme: settings.barColorScheme
        )
    }
}
