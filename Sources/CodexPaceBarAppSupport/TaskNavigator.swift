@preconcurrency import AppKit
import CodexPaceBarCore
import Foundation

public struct TaskNavigator: Sendable {
    public init() {}

    public func bundleIdentifier(for activity: CodexTaskActivity) -> String? {
        if let source = activity.sourceBundleIdentifier,
           source.contains("."),
           source != "com.apple.xpc.launchd" {
            return source
        }
        switch activity.terminalProgram?.lowercased() {
        case "apple_terminal", "terminal":
            return "com.apple.Terminal"
        case "iterm.app", "iterm2":
            return "com.googlecode.iterm2"
        case "warpterminal", "warp":
            return "dev.warp.Warp-Stable"
        case "wezterm":
            return "com.github.wez.wezterm"
        case "vscode":
            return "com.microsoft.VSCode"
        default:
            return nil
        }
    }

    @MainActor
    @discardableResult
    public func navigate(to activity: CodexTaskActivity) -> Bool {
        guard let bundleIdentifier = bundleIdentifier(for: activity) else { return false }
        if bundleIdentifier == "com.apple.Terminal",
           let selection = appleTerminalSelection(for: activity),
           selectAppleTerminal(selection) {
            return true
        }
        guard
              let application = NSRunningApplication.runningApplications(
                  withBundleIdentifier: bundleIdentifier
              ).first
        else { return false }
        return application.activate(options: [.activateAllWindows])
    }

    public func appleTerminalSelection(for activity: CodexTaskActivity) -> (window: Int, tab: Int)? {
        guard let value = activity.terminalSessionID,
              let match = value.firstMatch(of: /w(\d+)t(\d+)/),
              let window = Int(match.1),
              let tab = Int(match.2)
        else { return nil }
        return (window + 1, tab + 1)
    }

    @MainActor
    private func selectAppleTerminal(_ selection: (window: Int, tab: Int)) -> Bool {
        let script = """
        tell application "Terminal"
            activate
            if (count of windows) >= \(selection.window) then
                set targetWindow to window \(selection.window)
                if (count of tabs of targetWindow) >= \(selection.tab) then
                    set selected tab of targetWindow to tab \(selection.tab) of targetWindow
                    set index of targetWindow to 1
                end if
            end if
        end tell
        """
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }
}
