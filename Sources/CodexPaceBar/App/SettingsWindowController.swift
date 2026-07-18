@preconcurrency import AppKit
import CodexPaceBarAppSupport
import SwiftUI

@MainActor
final class SettingsWindowController {
    private let settings: SettingsStore
    private let launchAtLogin: LaunchAtLoginController
    private let onOpenTaskMonitor: () -> Void
    private var window: NSWindow?

    init(
        settings: SettingsStore,
        launchAtLogin: LaunchAtLoginController,
        onOpenTaskMonitor: @escaping () -> Void
    ) {
        self.settings = settings
        self.launchAtLogin = launchAtLogin
        self.onOpenTaskMonitor = onOpenTaskMonitor
    }

    func show() {
        launchAtLogin.refresh()

        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let hostingController = NSHostingController(
            rootView: SettingsView(
                settings: settings,
                launchAtLogin: launchAtLogin,
                onOpenTaskMonitor: onOpenTaskMonitor
            )
        )
        let window = NSWindow(contentViewController: hostingController)
        window.title = "Settings"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 620, height: 1000))
        window.center()
        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func close() {
        window?.orderOut(nil)
    }
}
