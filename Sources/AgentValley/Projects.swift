import Foundation

/// Which project a folder belongs to, told by its path, and by git where it was asked while the
/// folder was there: most folders sessions worked in are gone by the time anyone asks (144 of
/// 163 on the owner's Mac on 2026-10-15), so git cannot be asked then.
enum Projects {
    static let scratch = "Scratch"
    static let temporary = "Temporary folders"
    static let supersetSessions = "Superset sessions"
    static let unknown = "Unknown folder"

    /// A folder as Claude Code spells it in the names of its own folders: everything but
    /// letters and digits as "-".
    static func encoded(_ folder: String) -> String {
        String(folder.unicodeScalars.map { scalar -> Character in
            scalar.isASCII && CharacterSet.alphanumerics.contains(scalar) ? Character(scalar) : "-"
        })
    }

    /// Encoded folders back to the folders, to name a session's scratch folder by.
    static func known(_ folders: [String]) -> [String: String] {
        Dictionary(folders.map { (encoded($0), $0) }, uniquingKeysWith: { first, _ in first })
    }

    /// The project's name, by the first rule that fits. `checkouts`: folders to the checkouts
    /// git said they were in, while they were there to ask.
    static func name(of folder: String, home: String, known: [String: String] = [:], checkouts: [String: String] = [:]) -> String {
        if folder.isEmpty { return unknown }
        // A home folder kept in git, for its settings, is no project.
        if let checkout = checkouts[folder], checkout != home { return (checkout as NSString).lastPathComponent }
        // A session's scratch folder: /tmp/claude-<uid>/<its session's folder, encoded>/<session>/…
        for tmp in ["/tmp/claude-", "/private/tmp/claude-"] where folder.hasPrefix(tmp) {
            let parts = folder.dropFirst(tmp.count).split(separator: "/")
            guard parts.count >= 2, let real = known[String(parts[1])], !isTemporary(real) else { return scratch }
            return name(of: real, home: home, checkouts: checkouts)
        }
        if isTemporary(folder) { return temporary }
        var path = folder
        if let worktrees = path.range(of: "/.claude/worktrees/") { path = String(path[..<worktrees.lowerBound]) }
        let superset = home + "/.superset/worktrees/"
        if path.hasPrefix(superset), let repo = path.dropFirst(superset.count).split(separator: "/").first {
            // Superset names the folder by its own name for the project, which need not be the
            // checkout's: a worktree of the same project that git was asked about says which.
            let workspaces = superset + repo + "/"
            let asked = checkouts.filter { $0.key.hasPrefix(workspaces) && $0.value != home }.min { $0.key < $1.key }
            return asked.map { ($0.value as NSString).lastPathComponent } ?? String(repo)
        }
        if path.hasPrefix(home + "/.superset/sessions/") { return supersetSessions }
        if path == home || path == home + "/" { return "~" }
        return (path as NSString).lastPathComponent
    }

    private static func isTemporary(_ folder: String) -> Bool {
        ["/tmp", "/private/tmp", "/var/folders", "/private/var/folders"].contains { folder == $0 || folder.hasPrefix($0 + "/") }
    }
}
