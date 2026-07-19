@preconcurrency import AppKit
import CodexPaceBarAppSupport
import SwiftUI

@MainActor
final class SettingsWindowController {
    private let settings: SettingsStore
    private let launchAtLogin: LaunchAtLoginController
    private let onOpenTaskMonitor: () -> Void
    private let onGetTaskHookStatus: () -> CodexHookSetupStatus
    private let onSendMobileNotificationTest: () async -> Bool
    private var window: NSWindow?

    init(
        settings: SettingsStore,
        launchAtLogin: LaunchAtLoginController,
        onOpenTaskMonitor: @escaping () -> Void,
        onGetTaskHookStatus: @escaping () -> CodexHookSetupStatus,
        onSendMobileNotificationTest: @escaping () async -> Bool
    ) {
        self.settings = settings
        self.launchAtLogin = launchAtLogin
        self.onOpenTaskMonitor = onOpenTaskMonitor
        self.onGetTaskHookStatus = onGetTaskHookStatus
        self.onSendMobileNotificationTest = onSendMobileNotificationTest
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
                onOpenTaskMonitor: onOpenTaskMonitor,
                onGetTaskHookStatus: onGetTaskHookStatus,
                onSendMobileNotificationTest: onSendMobileNotificationTest
            )
        )
        let window = NSWindow(contentViewController: hostingController)
        window.title = "Settings"
        window.styleMask = [.titled, .closable, .resizable]
        window.isReleasedWhenClosed = false
        let visibleHeight = NSScreen.main?.visibleFrame.height ?? 900
        let initialHeight = max(560, min(760, visibleHeight - 100))
        window.contentMinSize = NSSize(width: 420, height: 520)
        window.contentMaxSize = NSSize(width: 760, height: max(560, visibleHeight))
        window.setContentSize(NSSize(width: 620, height: initialHeight))
        window.center()
        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func close() {
        window?.orderOut(nil)
    }
}
