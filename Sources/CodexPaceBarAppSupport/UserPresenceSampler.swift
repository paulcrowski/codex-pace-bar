@preconcurrency import AppKit
import CoreGraphics
import Foundation

public enum UserPresenceState: Equatable, Sendable {
    case active
    case inactive
    case unavailable
}

@MainActor
public final class UserPresenceSampler: NSObject {
    public static let inactiveAfter: TimeInterval = 5 * 60

    private let notificationCenter: NotificationCenter
    private let idleReader: @MainActor @Sendable () -> TimeInterval
    private var isStarted = false
    private var systemAwake = true
    private var screenAwake = true
    private var sessionActive = true

    public init(
        notificationCenter: NotificationCenter = NSWorkspace.shared.notificationCenter,
        idleReader: @escaping @MainActor @Sendable () -> TimeInterval = {
            let anyInputEvent = CGEventType(rawValue: UInt32.max)!
            return CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: anyInputEvent)
        }
    ) {
        self.notificationCenter = notificationCenter
        self.idleReader = idleReader
    }

    public func start() {
        guard !isStarted else { return }
        isStarted = true
        notificationCenter.addObserver(
            self,
            selector: #selector(systemWillSleep),
            name: NSWorkspace.willSleepNotification,
            object: nil
        )
        notificationCenter.addObserver(
            self,
            selector: #selector(systemDidWake),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
        notificationCenter.addObserver(
            self,
            selector: #selector(screenDidSleep),
            name: NSWorkspace.screensDidSleepNotification,
            object: nil
        )
        notificationCenter.addObserver(
            self,
            selector: #selector(screenDidWake),
            name: NSWorkspace.screensDidWakeNotification,
            object: nil
        )
        notificationCenter.addObserver(
            self,
            selector: #selector(sessionDidResignActive),
            name: NSWorkspace.sessionDidResignActiveNotification,
            object: nil
        )
        notificationCenter.addObserver(
            self,
            selector: #selector(sessionDidBecomeActive),
            name: NSWorkspace.sessionDidBecomeActiveNotification,
            object: nil
        )
    }

    public func stop() {
        guard isStarted else { return }
        notificationCenter.removeObserver(self)
        isStarted = false
    }

    public func state() -> UserPresenceState {
        guard systemAwake, screenAwake, sessionActive else { return .unavailable }
        let idleSeconds = idleReader()
        guard idleSeconds.isFinite, idleSeconds >= 0 else { return .unavailable }
        return idleSeconds < Self.inactiveAfter ? .active : .inactive
    }

    @objc private func systemWillSleep(_ notification: Notification) { systemAwake = false }
    @objc private func systemDidWake(_ notification: Notification) { systemAwake = true }
    @objc private func screenDidSleep(_ notification: Notification) { screenAwake = false }
    @objc private func screenDidWake(_ notification: Notification) { screenAwake = true }
    @objc private func sessionDidResignActive(_ notification: Notification) { sessionActive = false }
    @objc private func sessionDidBecomeActive(_ notification: Notification) { sessionActive = true }
}
