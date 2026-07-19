import CodexPaceBarCore
import Testing

struct TaskMonitorHealthTests {
    @Test
    func loadingAndReadyAreNotReportedAsFailures() {
        #expect(CodexTaskMonitorHealth.loading.isStale == false)
        #expect(CodexTaskMonitorHealth.ready.isStale == false)
        #expect(CodexTaskMonitorHealth.loading.title == nil)
        #expect(CodexTaskMonitorHealth.ready.detail == nil)
    }

    @Test
    func staleStateCarriesAnExplicitRecoveryMessage() {
        let health = CodexTaskMonitorHealth.stale(
            message: "Could not read local Codex activity. Showing the last successful snapshot."
        )

        #expect(health.isStale)
        #expect(health.title == "Task monitor is stale")
        #expect(health.detail == "Could not read local Codex activity. Showing the last successful snapshot.")
    }
}
