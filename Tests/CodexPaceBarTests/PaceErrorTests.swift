import CodexPaceBarCore
import Testing

@Suite
struct PaceErrorTests {
    @Test
    func identifiesOnlySetupErrors() {
        #expect(PaceError.codexExecutableNotFound.requiresCodexSetup)
        #expect(PaceError.appServerExited(127).requiresCodexSetup)
        #expect(!PaceError.appServerExited(1).requiresCodexSetup)
        #expect(!PaceError.noWeeklyWindowFound.requiresCodexSetup)
    }
}
