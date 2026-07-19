import Foundation

public enum CodexTaskMonitorRefreshPolicy {
    /// The compact UI can update elapsed time without touching the local store.
    public static let activeDisplayUpdateInterval: TimeInterval = 60

    /// New log/hook data remains event-driven; this is not a polling interval.
    public static let reloadIsEventDriven = true
}
