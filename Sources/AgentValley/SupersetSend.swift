import Foundation

/// Tells a Superset terminal what to type, through Superset's own command.
enum SupersetSend {
    static func binary(home: URL) -> URL {
        home.appendingPathComponent(".superset/bin/superset")
    }

    /// The text, staged without Enter. It rides in one `--text=` argument, so a message starting
    /// with dashes is never read as an option.
    static func arguments(workspace: String, terminal: String, text: String) -> [String] {
        ["terminals", "send", "--local", "--workspace", workspace, "--terminal", terminal, "--no-submit", "--text=\(text)"]
    }

    static func enterArguments(workspace: String, terminal: String) -> [String] {
        ["terminals", "send", "--local", "--workspace", workspace, "--terminal", terminal, "--keys", "enter"]
    }

    /// As in a tab: the text, then after a pause and a second look, Enter on its own.
    /// `check` is whether Claude is still in front and asks nothing; it is asked before the text and again before Enter.
    static func send(workspace: String, terminal: String, text: String, check: () -> Bool,
                     run: ([String]) -> ScriptRun, wait: (TimeInterval) -> Void) -> TypingResult {
        guard check() else { return .stoppedBeforeText }
        if let bad = failure(of: run(arguments(workspace: workspace, terminal: terminal, text: text))) { return bad }
        wait(TabTyping.pause)
        guard check() else { return .stoppedBeforeEnter }
        if let bad = failure(of: run(enterArguments(workspace: workspace, terminal: terminal))) { return bad }
        return .typed
    }

    /// nil when the command exited 0.
    private static func failure(of result: ScriptRun) -> TypingResult? {
        if result.timedOut { return .timedOut }
        if result.status == 0 { return nil }
        let reason = [result.err, result.out].lazy
            .compactMap { $0.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.first { !$0.isEmpty } }
            .first
        return .failed(reason ?? "Superset's command failed.")
    }

    /// Runs the command, 15 s at most. With no command on disk it answers as a failed run saying so.
    static func run(_ binary: URL) -> ([String]) -> ScriptRun {
        guard FileManager.default.isExecutableFile(atPath: binary.path) else {
            return { _ in ScriptRun(status: 127, out: "", err: "Superset's command isn't installed.", timedOut: false) }
        }
        return { ScriptRun.run(binary, $0, timeout: 15) }
    }
}
