import Foundation

/// `AgentValley crew …`: what Claude Code runs for its status line and sub-agent rows, and the
/// install and uninstall lines the person pastes. It answers and exits; the app never starts.
enum Crew {
    static func run(_ arguments: [String]) -> Int32 {
        let environment = ProcessInfo.processInfo.environment
        let home = URL(fileURLWithPath: environment["HOME"] ?? NSHomeDirectory())
        switch arguments.first {
        case "status":
            // Whatever arrives, a face is printed and the exit is clean: Claude Code shows a
            // failed status line as nothing at all.
            let input = SafeJSON.object(FileHandle.standardInput.readDataToEndOfFile()) ?? [:]
            let columns = environment["COLUMNS"].flatMap { Int($0) } ?? 80
            let claude = (try? Data(contentsOf: CrewSetup.claudeJSON(home: home, environment: environment)))
                .flatMap(CrewSetup.oauthAccount).map { ["oauthAccount": $0] }
            let leads = try? Data(contentsOf: CrewSetup.folder(home).appendingPathComponent(CrewSetup.leadLooksName))
            let look = CrewSetup.look(for: input["session_id"] as? String ?? "", in: leads)
            print(CrewLine.status(input, columns: columns, plan: CrewLine.plan(fromClaudeJSON: claude), look: look, now: Date()))
            return 0
        case "agents":
            let input = SafeJSON.object(FileHandle.standardInput.readDataToEndOfFile()) ?? [:]
            for row in CrewLine.rows(input, now: Date(), branch: CrewLine.branch(of:)) { print(row) }
            return 0
        case "install":
            let executable = Format.stablePath(Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments[0]))
            let font = (Bundle.main.resourceURL ?? Bundle.main.bundleURL).appendingPathComponent(CrewFont.fileName)
            let apps = [URL(fileURLWithPath: "/Applications/Ghostty.app"), home.appendingPathComponent("Applications/Ghostty.app")]
            return finish { try CrewSetup.install(home: home, environment: environment, executable: executable, font: font, ghosttyApps: apps) }
        case "uninstall":
            return finish { try CrewSetup.uninstall(home: home, environment: environment) }
        default:
            FileHandle.standardError.write(Data("Usage: AgentValley crew status|agents|install|uninstall\n".utf8))
            return 2
        }
    }

    /// Prints what the step says it did, or why it stopped.
    private static func finish(_ step: () throws -> String) -> Int32 {
        let reason: String
        do {
            print(try step())
            return 0
        } catch CrewSetup.Failure.unreadableSettings(let path) {
            reason = "Can't read \(path): it isn't valid JSON. Nothing was changed. Fix the file and run this again."
        } catch CrewSetup.Failure.missingFont {
            reason = "Can't find the crew's font inside the app. Nothing was changed. Reinstall AgentValley and run this again."
        } catch {
            reason = error.localizedDescription
        }
        FileHandle.standardError.write(Data((reason + "\n").utf8))
        return 1
    }
}
