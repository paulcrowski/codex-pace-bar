import CodexPaceBarCore
import Testing

struct TaskMonitorRefreshPolicyTests {
    @Test
    func updatesVisibleElapsedTimeOncePerMinuteWithoutPollingTheStore() {
        #expect(CodexTaskMonitorRefreshPolicy.activeDisplayUpdateInterval == 60)
        #expect(CodexTaskMonitorRefreshPolicy.reloadIsEventDriven)
    }
}
