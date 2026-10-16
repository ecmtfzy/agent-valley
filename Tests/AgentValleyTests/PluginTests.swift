import XCTest

/// Runs a shell script the way Claude Code runs a hook: JSON on stdin, a chosen HOME.
func runHookScript(_ script: URL, home: URL, input: String) throws -> (output: String, status: Int32) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/sh")
    process.arguments = [script.path]
    process.environment = ["HOME": home.path, "PATH": "/usr/bin:/bin"]
    let stdin = Pipe()
    let stdout = Pipe()
    process.standardInput = stdin
    process.standardOutput = stdout
    process.standardError = FileHandle.nullDevice
    try process.run()
    stdin.fileHandleForWriting.write(Data(input.utf8))
    try stdin.fileHandleForWriting.close()
    let output = stdout.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    return (String(decoding: output, as: UTF8.self), process.terminationStatus)
}

/// A short folder under /tmp: a Unix socket path may not exceed 104 bytes, which the usual temp folder would.
func shortTempFolder() throws -> URL {
    let url = URL(fileURLWithPath: "/tmp/av-" + UUID().uuidString.prefix(8))
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

/// Leaves a socket file with nothing listening on it, as a crashed app would.
func makeStaleSocket(at path: String) {
    let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
    var address = sockaddr_un()
    address.sun_family = sa_family_t(AF_UNIX)
    withUnsafeMutablePointer(to: &address.sun_path) { pointer in
        pointer.withMemoryRebound(to: CChar.self, capacity: 104) { _ = strlcpy($0, path, 104) }
    }
    let size = socklen_t(MemoryLayout<sockaddr_un>.size)
    _ = withUnsafePointer(to: &address) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(descriptor, $0, size) } }
    close(descriptor)
}

final class PluginTests: XCTestCase {
    /// The repo root, found from this file's own path.
    static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    static let marketplace = root.appendingPathComponent("plugin")
    static let plugin = marketplace.appendingPathComponent("notch-answers")
    static let script = plugin.appendingPathComponent("ask.sh")

    private func json(_ url: URL) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    }

    // One hook and no more: every extra event is code that runs inside someone's Claude Code.
    func testThePluginRegistersOnlyThePermissionRequestHook() throws {
        let hooks = try XCTUnwrap(json(Self.plugin.appendingPathComponent("hooks/hooks.json"))["hooks"] as? [String: Any])
        XCTAssertEqual(Array(hooks.keys), ["PermissionRequest"])
        let groups = try XCTUnwrap(hooks["PermissionRequest"] as? [[String: Any]])
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0]["matcher"] as? String, "*")
        let handlers = try XCTUnwrap(groups[0]["hooks"] as? [[String: Any]])
        XCTAssertEqual(handlers.count, 1)
        XCTAssertEqual(handlers[0]["type"] as? String, "command")
        XCTAssertEqual(handlers[0]["command"] as? String, "\"${CLAUDE_PLUGIN_ROOT}\"/ask.sh")
        XCTAssertEqual(handlers[0]["timeout"] as? Int, 600)
    }

    func testTheManifestsNameWhatTheInstallCommandsUse() throws {
        let market = try json(Self.marketplace.appendingPathComponent(".claude-plugin/marketplace.json"))
        XCTAssertEqual(market["name"] as? String, "agent-valley")
        let listed = try XCTUnwrap(market["plugins"] as? [[String: Any]])
        XCTAssertEqual(listed.count, 1)
        XCTAssertEqual(listed[0]["name"] as? String, "notch-answers")
        XCTAssertEqual(listed[0]["source"] as? String, "./notch-answers")
        let manifest = try json(Self.plugin.appendingPathComponent(".claude-plugin/plugin.json"))
        XCTAssertEqual(manifest["name"] as? String, "notch-answers")
        for key in ["version", "description", "author"] { XCTAssertNotNil(manifest[key], key) }
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: Self.script.path))
    }

    // Without the app there must be no trace of the plugin in a session: no output, no error.
    func testTheHookScriptSaysNothingWhenTheAppIsNotThere() throws {
        let home = try shortTempFolder()
        defer { try? FileManager.default.removeItem(at: home) }
        let result = try runHookScript(Self.script, home: home, input: #"{"tool_name":"Bash"}"#)
        XCTAssertEqual(result.output, "")
        XCTAssertEqual(result.status, 0)
    }

    func testTheHookScriptSaysNothingWhenNothingListensOnTheSocket() throws {
        let home = try shortTempFolder()
        defer { try? FileManager.default.removeItem(at: home) }
        let folder = home.appendingPathComponent("Library/Application Support/AgentValley")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        makeStaleSocket(at: folder.appendingPathComponent("answers.sock").path)
        let result = try runHookScript(Self.script, home: home, input: #"{"tool_name":"Bash"}"#)
        XCTAssertEqual(result.output, "")
        XCTAssertEqual(result.status, 0)
    }
}
