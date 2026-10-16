import AppKit

/// The app a session's terminal runs in: where the person has to go to answer it.
/// Known by where the app is on disk, not by its process: a terminal app can be closed and
/// opened again while the sessions it started run on.
struct OwnerApp: Equatable {
    let bundle: URL
    let name: String
    /// An address the app opens at the session's own place in it, when it has one. Without it
    /// the app comes forward and the person finds the session among its windows.
    var link: URL? = nil
    /// The session's own tab in the app, for a terminal that can be asked to show one, and
    /// only where the person has asked for that. Without it the app comes forward and no more.
    var tab: TabPlace? = nil

    /// Brings the app to the front, at the session's own place when that is known, opening it
    /// if it has been closed. Only ever called by the person's own doing: a click in the panel,
    /// or Return on the session the arrow keys chose.
    func bringForward() {
        // The address names the session's place, and goes to the app it runs in and to no other.
        if let link, Self.isOwn(opener: NSWorkspace.shared.urlForApplication(toOpen: link), of: bundle), NSWorkspace.shared.open(link) { return }
        NSWorkspace.shared.openApplication(at: bundle, configuration: NSWorkspace.OpenConfiguration())
        // And on to the session's own tab, where that is known.
        tab?.show()
    }

    /// Whether the app the system would open an address with is the one at `bundle`. Any app
    /// can tell the system it opens addresses of some kind.
    static func isOwn(opener: URL?, of bundle: URL) -> Bool {
        opener?.standardizedFileURL.path == bundle.standardizedFileURL.path
    }

    /// Superset names each of its terminals' workspace in this variable of the terminal's
    /// environment, and opens a workspace from an address of this shape.
    // ponytail: one app that is known to do this. A second one gets a second pair here.
    static let supersetBundle = "com.superset.desktop"
    static let supersetWorkspace = "SUPERSET_WORKSPACE_ID"

    /// The address of a Superset workspace, or nil unless `workspace` is an id and nothing
    /// else: it comes out of another process and goes into an address.
    static func supersetLink(workspace: String) -> URL? {
        guard let id = UUID(uuidString: workspace), id.uuidString.lowercased() == workspace.lowercased() else { return nil }
        return URL(string: "superset://v2-workspace/\(workspace)")
    }
}

/// Where a session's own tab is in its terminal: which terminal, and what finds the tab there.
/// Only for the terminals that can be asked to show a tab.
struct TabPlace: Equatable {
    enum Terminal: Equatable {
        case terminal, iterm, ghostty
    }

    let terminal: Terminal
    /// The tab's tty in Terminal and iTerm2. In Ghostty, which tells no tty, the folder the
    /// session was started in.
    let key: String

    /// The terminal an app is, by its bundle id, or nil when it is not one that can be asked.
    static func terminal(bundleID: String?) -> Terminal? {
        switch bundleID {
        case "com.apple.Terminal": return .terminal
        case "com.googlecode.iterm2": return .iterm
        case "com.mitchellh.ghostty": return .ghostty
        default: return nil
        }
    }

    /// A tty as the system names one, and nothing else: what is handed to a script is this
    /// or nothing.
    static func isTTY(_ path: String) -> Bool {
        let prefix = "/dev/ttys"
        guard path.hasPrefix(prefix) else { return false }
        let digits = path.dropFirst(prefix.count)
        // By the letter itself and not by where it sorts: a mark riding on a digit makes one
        // character of the two, and that one still sorts between "0" and "9".
        return (1...6).contains(digits.count) && digits.allSatisfy { $0.isASCII && $0.isNumber }
    }

    /// The tab of a session in the app with this bundle id. nil when the app cannot be asked,
    /// or what would find the tab is not known. Of `tty` and `folder`, only the one that
    /// terminal is asked by is read, and neither for any other app.
    static func place(bundleID: String?, tty: () -> String?, folder: () -> String?) -> TabPlace? {
        guard let terminal = terminal(bundleID: bundleID) else { return nil }
        switch terminal {
        case .terminal, .iterm:
            guard let tty = tty(), isTTY(tty) else { return nil }
            return TabPlace(terminal: terminal, key: tty)
        case .ghostty:
            // A whole path, which is also what keeps it from being read as an option of the
            // command that runs the script.
            guard let folder = folder(), folder.hasPrefix("/") else { return nil }
            return TabPlace(terminal: terminal, key: folder)
        }
    }

    /// What the terminal is asked: to show the one tab whose tty, or whose folder, is the
    /// script's argument. It selects, and does nothing else. A fixed text: the value is handed
    /// over beside it and never written into it, so nothing read from another process can
    /// become part of what is run.
    /// `w` in a loop over windows means "the window in that place", and bringing one forward
    /// changes the places. So the tab is dealt with before any window moves, and a window
    /// that is moved twice is named by its id.
    var script: String {
        switch terminal {
        case .terminal:
            return """
            on run argv
                set target to item 1 of argv
                tell application "Terminal"
                    repeat with w in windows
                        try
                            repeat with t in tabs of w
                                try
                                    if tty of t is target then
                                        set theID to id of w
                                        set selected tab of w to t
                                        if miniaturized of window id theID then set miniaturized of window id theID to false
                                        set index of window id theID to 1
                                        return
                                    end if
                                end try
                            end repeat
                        end try
                    end repeat
                end tell
            end run
            """
        case .iterm:
            return """
            on run argv
                set target to item 1 of argv
                tell application "iTerm2"
                    repeat with w in windows
                        repeat with t in tabs of w
                            repeat with s in sessions of t
                                try
                                    if tty of s is target then
                                        select s
                                        select t
                                        select w
                                        return
                                    end if
                                end try
                            end repeat
                        end repeat
                    end repeat
                end tell
            end run
            """
        case .ghostty:
            // With or without a slash at its end: both are the same folder.
            return """
            on run argv
                set target to item 1 of argv
                tell application "Ghostty"
                    repeat with t in terminals
                        try
                            set itsFolder to working directory of t
                            if itsFolder is target or itsFolder is (target & "/") then
                                focus t
                                return
                            end if
                        end try
                    end repeat
                end tell
            end run
            """
        }
    }

    /// What `osascript` is run with: the script, then the value as the script's own argument.
    /// After a divider, so that nothing in the value is read as an option here either,
    /// whatever `place` let through.
    var arguments: [String] { ["-e", script, "--", key] }

    /// Asks the terminal to show the tab. In a process of its own and not waited for: macOS
    /// may hold it while it asks the person whether this app may tell that one what to do.
    /// Only ever called by the person's own doing, as `OwnerApp.bringForward` is.
    // ponytail: not stopped if it hangs; an Apple event gives up by itself after two minutes.
    func show() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
    }
}

extension AgentStore {
    /// Runs `work` on the main thread and waits for it. AppKit is asked there; the store reads
    /// on a queue of its own, which the main thread never waits on.
    static func onMain<T>(_ work: () -> T) -> T {
        Thread.isMainThread ? work() : DispatchQueue.main.sync(execute: work)
    }

    /// The nearest ancestor of a process that is an ordinary app with windows, or part of one:
    /// the terminal, or the editor or workspace app whose terminal it is.
    // ponytail: a session inside tmux or screen hangs off their server, not off a window, and finds no app.
    static func ownerApp(ofProcess pid: Int32) -> OwnerApp? {
        onMain {
            let start = pid
            var pid = pid
            for _ in 0..<16 {
                guard let parent = parent(ofProcess: pid), parent > 1 else { return nil }
                if let app = app(ofProcess: parent), let name = app.localizedName, !name.isEmpty, let bundle = app.bundleURL {
                    // The session's own workspace, for the one app known to open at one.
                    let link = app.bundleIdentifier == OwnerApp.supersetBundle
                        ? environmentValue(OwnerApp.supersetWorkspace, ofProcess: start).flatMap(OwnerApp.supersetLink(workspace:)) : nil
                    return OwnerApp(bundle: bundle, name: name, link: link)
                }
                pid = parent
            }
            return nil
        }
    }

    /// The ordinary app a process is, or belongs to. A terminal's shells can hang off a helper
    /// that the app keeps running outside its own process tree, so where the helper's executable
    /// lives counts too: inside an app's bundle, it is that app's.
    /// `program` is where a process's executable is on disk; handed in, as a test cannot keep
    /// a process running whose program is gone.
    static func app(ofProcess pid: Int32, program: (Int32) -> String? = AgentStore.executable(ofProcess:)) -> NSRunningApplication? {
        if let app = NSRunningApplication(processIdentifier: pid), app.activationPolicy == .regular { return app }
        guard let executable = program(pid) else {
            // An app that updates itself can leave the helper running from the copy the update
            // took away, so the helper is on no path. Superset's terminals outlive its updates
            // that way. Its environment still names the app that started it.
            guard let id = environmentValue("__CFBundleIdentifier", ofProcess: pid) else { return nil }
            return NSRunningApplication.runningApplications(withBundleIdentifier: id).first { $0.activationPolicy == .regular }
        }
        guard let bundle = bundle(ofExecutable: executable) else { return nil }
        let url = URL(fileURLWithPath: bundle).standardizedFileURL
        return NSWorkspace.shared.runningApplications.first { $0.activationPolicy == .regular && $0.bundleURL?.standardizedFileURL == url }
    }

    /// One variable of a process's environment, or nil when it has none of that name. The
    /// environment holds secrets: it is read into memory, this one value is taken out, and the
    /// rest is let go. Nothing of it is kept, logged or shown.
    static func environmentValue(_ name: String, ofProcess pid: Int32) -> String? {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 3, &buffer, &size, nil, 0) == 0 else { return nil }
        // Wiped before it is let go: what else was in it is nobody's business here. All of it,
        // by the call the compiler may not drop. What the system did not fill is still zero,
        // and reads as the end.
        defer { buffer.withUnsafeMutableBytes { _ = memset_s($0.baseAddress, $0.count, 0, $0.count) } }
        return environmentValue(name, inProcessArguments: buffer)
    }

    /// The same, out of a process's arguments as the system hands them over: how many there
    /// are, the program's path, padding, the arguments, then the environment. The arguments
    /// are stepped over by their count, so that one written like a variable is not taken for one.
    static func environmentValue(_ name: String, inProcessArguments bytes: [UInt8]) -> String? {
        guard bytes.count > MemoryLayout<Int32>.size else { return nil }
        let count = bytes.withUnsafeBytes { $0.loadUnaligned(as: Int32.self) }
        guard count >= 0 else { return nil }
        var index = MemoryLayout<Int32>.size
        func skipString() {
            while index < bytes.count, bytes[index] != 0 { index += 1 }
        }
        skipString()
        while index < bytes.count, bytes[index] == 0 { index += 1 }
        var skipped: Int32 = 0
        while skipped < count, index < bytes.count {
            skipString()
            index += 1
            skipped += 1
        }
        let prefix = Array((name + "=").utf8)
        while index < bytes.count {
            let start = index
            skipString()
            if index == start { break }
            if bytes[start..<index].starts(with: prefix) { return String(decoding: bytes[(start + prefix.count)..<index], as: UTF8.self) }
            index += 1
        }
        return nil
    }

    /// Where the program a process runs is on disk, or nil when no such process is running.
    static func executable(ofProcess pid: Int32) -> String? {
        var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        return proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 ? String(cString: buffer) : nil
    }

    /// The app bundle an executable lives in: the outermost one on its path, so a helper app
    /// nested inside an app's bundle counts as that app.
    static func bundle(ofExecutable path: String) -> String? {
        let parts = path.components(separatedBy: "/")
        guard let index = parts.firstIndex(where: { $0.hasSuffix(".app") }) else { return nil }
        return parts[...index].joined(separator: "/")
    }

    /// The tab of a session's process in the app it runs in, read from the process itself.
    /// Not kept anywhere but on the card's app, and shown nowhere.
    /// The folder is the one the session was started in, as its environment has it: that is
    /// what the shell told the terminal. Where the process is now is no use. Claude Code
    /// moves itself into a worktree, and the system names a folder by its real path where
    /// the shell named it through a link.
    static func tabPlace(ofProcess pid: Int32, in app: OwnerApp) -> TabPlace? {
        TabPlace.place(bundleID: Bundle(url: app.bundle)?.bundleIdentifier, tty: { tty(ofProcess: pid) }, folder: { environmentValue("PWD", ofProcess: pid) })
    }
}
