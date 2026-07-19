import CodexPaceBarAppSupport
import CodexPaceBarCore
import Testing

struct TaskNavigatorTests {
    @Test
    func mapsSupportedTerminalProgramsAndRejectsUnknownOnes() {
        let navigator = TaskNavigator()
        #expect(navigator.bundleIdentifier(for: task(program: "Apple_Terminal")) == "com.apple.Terminal")
        #expect(navigator.bundleIdentifier(for: task(program: "iTerm.app")) == "com.googlecode.iterm2")
        #expect(navigator.bundleIdentifier(for: task(program: "unknown")) == nil)
        let selection = navigator.appleTerminalSelection(for: task(
            program: "Apple_Terminal",
            sessionID: "w2t1p0:ABC"
        ))
        #expect(selection?.window == 3)
        #expect(selection?.tab == 2)
    }

    private func task(program: String, sessionID: String? = nil) -> CodexTaskActivity {
        CodexTaskActivity(sessionID: "s", turnID: "t", workingDirectory: nil, model: nil, effort: nil, status: .working, startedAt: nil, completedAt: nil, duration: nil, timeToFirstToken: nil, terminalProgram: program, terminalSessionID: sessionID)
    }
}
