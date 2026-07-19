import CodexPaceBarCore
import Testing

struct TaskMonitorRuntimeFailureTests {
    @Test
    func failedReadIsVisibleAndALaterSuccessfulReadRecoversToReady() {
        var tracker = CodexTaskMonitorHealthTracker()
        #expect(tracker.state == .loading)

        tracker.markStale(
            message: "Could not read local Codex activity. Showing the last successful snapshot."
        )
        #expect(tracker.state == .stale(
            message: "Could not read local Codex activity. Showing the last successful snapshot."
        ))

        tracker.markReady()
        #expect(tracker.state == .ready)
    }
}
